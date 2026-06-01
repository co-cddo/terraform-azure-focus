import azure.functions as func
import logging
import os
import pyarrow.parquet as pq
import pyarrow.fs as fs
import io
import json
import requests
from azure.storage.blob import BlobServiceClient
from azure.identity import ManagedIdentityCredential
from datetime import datetime, timezone, timedelta
from common import(
  Config,
  is_uuid,
)
from api.s3Api import getS3FileSystem
from carbonExport import (
  get_carbon_api_date_range,
  is_month_within_api_range,
  make_carbon_api_request_batched,
  carbon_export_api_latest_fetch_date,
  check_carbon_data_exists,
  save_carbon_data_to_s3,
  carbon_emissions_backfill_imp,
)
from costExport import (
    cost_export_backfill_impl,
)
from billing import (
    extract_subscription_ids_from_billing_scope,
    extract_billing_account_from_blob_path,
)
from api.tokens import TokenManager

logger = logging.getLogger("cost_export")
logger.setLevel(os.environ.get('LOGGING_LEVEL', 'INFO'))

app = func.FunctionApp()

# Log billing account configuration at startup
logger.info("=== Billing Account Configuration ===")
logger.info(f"Billing account mapping: {Config.billing_account_mapping}")
logger.info(f"Number of billing accounts: {len(Config.billing_account_mapping)}")
for idx, account_id in Config.billing_account_mapping.items():
    logger.info(f"Export index {idx} -> Billing Account {account_id}")
logger.info("====================================")

@app.function_name(name="CostExportProcessor")
@app.queue_trigger(arg_name="msg", queue_name="costdata", connection="StorageAccountManagedIdentity")
def cost_export_processor(msg: func.QueueMessage) -> None:
    """Queue trigger function that processes parquet files when messages are received"""
    utc_timestamp = datetime.now(timezone.utc).isoformat()

    logger.info(f'Cost export processor triggered at: {utc_timestamp}')
    logger.info(f'Processing message: {msg.get_body().decode("utf-8")}')

    try:
        # Parse the EventGrid message to get the specific blob
        message_body = json.loads(msg.get_body().decode("utf-8"))
        blob_url = message_body.get("subject")
        if not blob_url:
           # log an error
           return

        # Extract blob name from the subject (format: /blobServices/default/containers/{container}/blobs/{blobname})
        blob_name = None
        if blob_url.startswith("/blobServices/default/containers/"):
            parts = blob_url.split("/blobs/", 1)
            if len(parts) == 2:
                blob_name = parts[1]

        if not blob_name:
            logger.error(f"Could not extract blob name from message subject: {blob_url}")
            return

        if not blob_name.endswith('.parquet'):
            logger.info(f"Skipping non-parquet file: {blob_name}")
            return

        logger.info(f"Processing specific parquet file: {blob_name}")

        # Initialize blob service client using the function's managed identity
        # (the cost_export storage account has shared access keys disabled)
        blob_service_client = BlobServiceClient(
            account_url=Config.storage_account_blob_endpoint,
            credential=ManagedIdentityCredential(),
        )
        container_client = blob_service_client.get_container_client(Config.container_name)

        # Get S3 filesystem
        s3 = getS3FileSystem()

        # Process the specific blob from the message
        try:
            # Download blob content
            blob_client = container_client.get_blob_client(blob_name)
            blob_data = blob_client.download_blob().readall()
            blob_to_read = io.BytesIO(blob_data)

            # Read parquet table
            table = pq.read_table(blob_to_read)

            ### Any deployment specific requirements can be implemented here ###
            table = table.drop_columns("ResourceName")

            # Extract billing account ID before dropping it, for S3 path organization
            billing_account_id = None
            billing_profile_from_data = None
            if "BillingAccountId" in table.column_names:
                # Get the first BillingAccountId value to determine the billing account
                billing_account_ids = table.select(["BillingAccountId"]).to_pylist()
                if billing_account_ids:
                    full_billing_path = billing_account_ids[0]["BillingAccountId"]
                    logger.info(f"Found billing account path in data: {full_billing_path}")

                    # Extract billing account ID and profile from the full path
                    # Example: /providers/Microsoft.Billing/billingAccounts/bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31/billingProfiles/OC35-AR3W-BG7-PGB
                    if "/providers/Microsoft.Billing/billingAccounts/" in full_billing_path:
                        # Extract the part after billingAccounts/
                        account_part = full_billing_path.split("/providers/Microsoft.Billing/billingAccounts/")[1]

                        # Check if there's a billingProfiles part
                        if "/billingProfiles/" in account_part:
                            billing_account_id = account_part.split("/billingProfiles/")[0]
                            billing_profile_from_data = account_part.split("/billingProfiles/")[1]
                        else:
                            billing_account_id = account_part

                        logger.info(f"Extracted billing account ID: {billing_account_id}")
                        if billing_profile_from_data:
                            logger.info(f"Extracted billing profile from data: {billing_profile_from_data}")
                    else:
                        # Fallback: use the full path as billing account ID
                        billing_account_id = full_billing_path
                        logger.warning(f"Could not parse billing account path, using full path: {billing_account_id}")

            table = table.drop_columns("BillingAccountId")
            table = table.drop_columns("BillingAccountName")
            table = table.drop_columns("BillingAccountType")
            table = table.drop_columns("ChargeDescription")
            table = table.drop_columns("CommitmentDiscountName")
            table = table.drop_columns("RegionId")
            table = table.drop_columns("ResourceId")
            table = table.drop_columns("SubAccountId")
            table = table.drop_columns("SubAccountName")
            table = table.drop_columns("SubAccountType")
            table = table.drop_columns("Tags")

            # Drop any columns that start with "x_"
            columns_to_drop = [col for col in table.column_names if col.startswith("x_")]
            if columns_to_drop:
                table = table.drop_columns(columns_to_drop)
            ### End of deployment specific requirements ###

            # Transform S3 path
            # Example: /7a770e35-b455-4df2-a276-b07408438d9a/gds-focus-v1/focus-backfill-2025-06/billing_period=20250601/providers/Microsoft.Billing/billingAccounts/billing-account-id:profile-id/billingProfiles/profile-name/part_0_0001.parquet
            # Becomes: /7a770e35-b455-4df2-a276-b07408438d9a/gds-focus-v1/billing_period=20250601/billing-account-id:profile-id_profile-name_part_0_0001.parquet
            path_parts = blob_name.split('/')
            modified_parts = []
            billing_account_path_part = None
            billing_profile_path_part = None

            # Find and extract billing account and profile info from path
            i = 0
            while i < len(path_parts):
                part = path_parts[i]

                if part == "focus-daily-cost-export" or part.startswith("focus-daily-cost-export-"):
                    # Skip this part entirely
                    i += 1
                    continue
                elif part.startswith("focus-backfill-"):
                    # Skip focus-backfill-YYYY-MM directories
                    logger.info(f"Skipping focus-backfill directory: {part}")
                    i += 1
                    continue
                elif len(part) == 12 and part.isdigit():
                    # Validate that this is actually a valid YYYYMMDDHHMM timestamp
                    try:
                        datetime.strptime(part, "%Y%m%d%H%M")
                        logger.info(f"Skipping timestamp directory: {part}")
                        i += 1
                        continue
                    except ValueError:
                        # Not a valid timestamp, continue processing normally
                        pass
                elif "-" in part and len(part) == 17 and part[:8].isdigit() and part[9:17].isdigit():
                    # Transform date range (e.g., "20250801-20250831" -> "billing_period=20250801")
                    billing_period = part.split("-")[0]
                    modified_parts.append(f"billing_period={billing_period}")
                    i += 1
                    continue
                elif is_uuid(part):
                    # Skip UUID directories - these should be flattened
                    logger.info(f"Skipping UUID directory: {part}")
                    i += 1
                    continue
                elif part == "providers":
                    # Skip providers/Microsoft.Billing/billingAccounts structure and extract info
                    if (i + 3 < len(path_parts) and
                        path_parts[i + 1] == "Microsoft.Billing" and
                        path_parts[i + 2] == "billingAccounts"):
                        billing_account_path_part = path_parts[i + 3]
                        logger.info(f"Found billing account in path: {billing_account_path_part}")
                        # Skip providers, Microsoft.Billing, billingAccounts, and the billing account ID
                        i += 4
                        continue
                    else:
                        modified_parts.append(part)
                        i += 1
                        continue
                elif part == "billingProfiles":
                    # Extract billing profile name from next part
                    if i + 1 < len(path_parts):
                        billing_profile_path_part = path_parts[i + 1]
                        logger.info(f"Found billing profile in path: {billing_profile_path_part}")
                        # Skip billingProfiles and the profile name
                        i += 2
                        continue
                    else:
                        i += 1
                        continue
                else:
                    modified_parts.append(part)
                    i += 1

            # Determine billing account folder for S3 path organization
            billing_account_folder = None
            if billing_account_id:
                # Use the billing account ID directly
                billing_account_folder = billing_account_id
                logger.info(f"Using billing account ID from data: {billing_account_folder}")
            elif billing_account_path_part:
                # Use the billing account ID from the path
                billing_account_folder = billing_account_path_part
                logger.info(f"Using billing account ID from path: {billing_account_folder}")
            else:
                # Fallback: try to extract from blob path structure
                export_index = extract_billing_account_from_blob_path(blob_name)
                if export_index is not None and str(export_index) in Config.billing_account_mapping:
                    billing_account_folder = Config.billing_account_mapping[str(export_index)]
                    logger.info(f"Mapped export index {export_index} to billing account: {billing_account_folder}")
                else:
                    logger.warning(f"Could not determine billing account folder for {blob_name}")
                    billing_account_folder = "unknown-billing-account"

            # Extract filename from the modified path and construct flattened filename
            modified_path_parts = [part for part in modified_parts if part]  # Remove empty parts

            if modified_path_parts:
                # Get the original filename (last part)
                original_filename = modified_path_parts[-1]
                directory_parts = modified_path_parts[:-1]

                # Construct flattened filename: billing_account_id_billing_profile_original_filename
                filename_parts = []
                if billing_account_folder:
                    # Replace colons with dashes for filesystem compatibility
                    safe_billing_account = billing_account_folder.replace(':', '-')
                    filename_parts.append(safe_billing_account)

                # Prefer billing profile from data over path
                billing_profile_to_use = billing_profile_from_data or billing_profile_path_part
                if billing_profile_to_use:
                    filename_parts.append(billing_profile_to_use)

                filename_parts.append(original_filename)

                flattened_filename = '_'.join(filename_parts)
                logger.info(f"Flattened filename: {original_filename} -> {flattened_filename}")

                # Reconstruct path with flattened filename
                if directory_parts:
                    modified_path = '/'.join(directory_parts) + '/' + flattened_filename
                else:
                    modified_path = flattened_filename
            else:
                modified_path = '/'.join(modified_parts)
                logger.warning(f"Could not extract filename from path parts: {modified_parts}")

            # Construct S3 path with flattened structure
            s3_path = f"{Config.s3_focus_path.rstrip('/')}/{modified_path.lstrip('/')}"

            pq.write_table(table, where=s3_path, filesystem=s3, compression='snappy')
            logger.info(f"Successfully uploaded {blob_name} to S3 at path: {s3_path} (billing account: {billing_account_folder})")

            # Delete source file after successful upload
            blob_client.delete_blob()
            logger.info(f"Successfully deleted source file: {blob_name}")

        except Exception as e:
            logger.error(f"Failed to process {blob_name}: {str(e)}")
            raise

    except Exception as e:
        logger.error(f"Error in daily cost export processor: {str(e)}")
        raise

def sanitize_recommendations_data(data):
    """Remove sensitive data from recommendations for security reasons"""
    if not isinstance(data, dict) or "value" not in data:
        return data

    sanitized_data = data.copy()
    sanitized_recommendations = []

    for recommendation in data.get("value", []):
        sanitized_rec = recommendation.copy()

        # Remove impactedValue from properties
        if "properties" in sanitized_rec and "impactedValue" in sanitized_rec["properties"]:
            del sanitized_rec["properties"]["impactedValue"]

        # Remove resourceMetadata object entirely
        if "properties" in sanitized_rec and "resourceMetadata" in sanitized_rec["properties"]:
            del sanitized_rec["properties"]["resourceMetadata"]

        sanitized_recommendations.append(sanitized_rec)

    sanitized_data["value"] = sanitized_recommendations
    return sanitized_data

def save_recommendations_to_s3(data, file_name):
    """Save Azure Advisor recommendations data to S3"""
    try:
        # Sanitize data before saving to remove sensitive information
        sanitized_data = sanitize_recommendations_data(data)

        # Convert to JSON string
        json_data = json.dumps(sanitized_data, indent=2).encode('utf-8')

        # Get S3 filesystem
        s3 = getS3FileSystem()

        # Use current date directly for billing period instead of parsing from filename
        current_date = datetime.now(timezone.utc)
        billing_period = current_date.strftime("%Y%m%d")  # Current date as YYYYMMDD (e.g., 20250814)
        s3_path = f"{Config.s3_recommendations_path.rstrip('/')}/gds-recommendations-v1/billing_period={billing_period}/{file_name}"

        logger.info(f"Saving recommendations with billing_period={billing_period} to path: {s3_path}")

        # Upload to S3
        with s3.open_output_stream(s3_path) as f:
            f.write(json_data)

        logger.info(f"Successfully uploaded recommendations data to S3: {s3_path}")

    except Exception as e:
        logger.error(f"Error saving recommendations data to S3: {str(e)}")
        raise

@app.function_name(name="AdvisorRecommendationsExporter")
@app.timer_trigger(schedule="0 0 2 * * *", arg_name="timer", run_on_startup=False)
def advisor_recommendations_exporter(timer: func.TimerRequest) -> None:
    """Timer trigger function that exports Azure Advisor cost recommendations daily at 2 AM"""
    utc_timestamp = datetime.now(timezone.utc).isoformat()

    logger.info(f'Azure Advisor recommendations exporter triggered at: {utc_timestamp}')

    if timer.past_due:
        logger.info('The timer is past due!')

    try:
        # Get access token using managed identity
        token = TokenManager().azure_token

        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }

        # Extract subscription IDs from billing scope
        subscription_ids = extract_subscription_ids_from_billing_scope(Config.billing_scope)

        logger.info(f"Fetching cost recommendations for {len(subscription_ids)} subscriptions")

        all_recommendations = []

        # Fetch cost recommendations for each subscription
        for subscription_id in subscription_ids:
            try:
                logger.info(f"Fetching cost recommendations for subscription: {subscription_id}")

                # Azure Advisor Recommendations API endpoint
                api_url = f"https://management.azure.com/subscriptions/{subscription_id}/providers/Microsoft.Advisor/recommendations"
                api_version = "2025-01-01"

                # Filter for cost category recommendations only
                params = {
                    "api-version": api_version,
                    "$filter": "Category eq 'Cost'"
                }

                logger.info(f"Calling API: {api_url} with params: {params}")

                response = requests.get(
                    api_url,
                    headers=headers,
                    params=params,
                    timeout=300
                )

                logger.info(f"API Response Status: {response.status_code}")

                if response.status_code == 200:
                    recommendations_data = response.json()
                    recommendations = recommendations_data.get("value", [])

                    logger.info(f"Raw API response for subscription {subscription_id}: {recommendations_data}")

                    # Add subscription ID to each recommendation for tracking
                    for rec in recommendations:
                        rec["subscriptionId"] = subscription_id

                    all_recommendations.extend(recommendations)
                    logger.info(f"Retrieved {len(recommendations)} cost recommendations for subscription {subscription_id}")

                else:
                    logger.error(f"Failed to fetch recommendations for subscription {subscription_id}: {response.status_code}")
                    logger.error(f"Response text: {response.text}")
                    logger.error(f"Response headers: {dict(response.headers)}")

            except Exception as e:
                logger.error(f"Error fetching recommendations for subscription {subscription_id}: {str(e)}")
                continue

        if all_recommendations:
            # Save recommendations to S3
            current_date = datetime.now(timezone.utc)
            file_name = f"advisor-cost-recommendations-{current_date.strftime('%Y-%m-%d')}.json"
            save_recommendations_to_s3({"value": all_recommendations}, file_name)

            logger.info(f"Successfully exported {len(all_recommendations)} cost recommendations from {len(subscription_ids)} subscriptions")
        else:
            logger.warning("No cost recommendations found across all subscriptions")

    except Exception as e:
        logger.error(f"Error in Azure Advisor recommendations exporter: {str(e)}")
        raise

@app.function_name(name="CarbonApiDateRangeInfo")
@app.route(route="carbon-date-range", auth_level=func.AuthLevel.FUNCTION)
def carbon_api_date_range_info(req: func.HttpRequest) -> func.HttpResponse:
    """HTTP trigger function that returns the current Carbon API available date range

    Query parameters:
    - check_existing: Set to 'true' to also check which months already have data in S3 (default: false)
    """
    try:
        # Parse query parameters
        check_existing = req.params.get('check_existing', 'false').lower() == 'true'

        # Get current API available date range dynamically
        api_start_date, api_end_date = get_carbon_api_date_range()

        # Calculate what month would be processed by the regular exporter
        today = datetime.now(timezone.utc)
        last_month = today.replace(day=1) - timedelta(days=1)

        # Check if last month is within range
        is_last_month_available = is_month_within_api_range(last_month)

        # Prepare response data
        response_data = {
            "current_date": today.strftime("%Y-%m-%d"),
            "api_available_range": {
                "start_date": api_start_date.strftime("%Y-%m-%d"),
                "end_date": api_end_date.strftime("%Y-%m-%d"),
                "total_months": ((api_end_date.year - api_start_date.year) * 12 +
                               (api_end_date.month - api_start_date.month) + 1)
            },
            "last_month_processing": {
                "target_month": last_month.strftime("%Y-%m-%d"),
                "is_available": is_last_month_available,
                "would_be_processed": last_month.strftime("%Y-%m-01") if is_last_month_available else "N/A"
            },
            "calculation_logic": {
                "data_available_by_day": 19,
                "rolling_window_months": 12,
                "description": "Data for previous month available by day 19. API provides 12-month rolling window."
            }
        }

        # Optionally check which months already have data
        if check_existing:
            existing_data = []
            missing_data = []

            # Check a sample of months from 2022 to current API range
            start_check = datetime(2022, 1, 1, tzinfo=timezone.utc)
            end_check = api_end_date

            current = start_check
            while current <= end_check:
                file_name = f"carbon-emissions-{current.strftime('%Y-%m')}.json"
                exists, s3_path = check_carbon_data_exists(file_name)

                month_info = {
                    "month": current.strftime("%Y-%m"),
                    "file_name": file_name,
                    "within_api_range": is_month_within_api_range(current)
                }

                if exists:
                    month_info["s3_path"] = s3_path
                    existing_data.append(month_info)
                else:
                    missing_data.append(month_info)

                # Move to next month
                if current.month == 12:
                    current = current.replace(year=current.year + 1, month=1)
                else:
                    current = current.replace(month=current.month + 1)

            response_data["existing_data_check"] = {
                "total_existing": len(existing_data),
                "total_missing": len(missing_data),
                "existing_months": [item["month"] for item in existing_data],
                "missing_months": [item["month"] for item in missing_data],
                "note": "This check covers 2022-01 through current API range"
            }

        logger.info(f"Carbon API date range info requested: check_existing={check_existing}")

        return func.HttpResponse(
            json.dumps(response_data, indent=2),
            status_code=200,
            headers={"Content-Type": "application/json"}
        )

    except Exception as e:
        error_msg = f"Error getting Carbon API date range info: {str(e)}"
        logger.error(error_msg)
        return func.HttpResponse(
            json.dumps({"error": error_msg}),
            status_code=500,
            headers={"Content-Type": "application/json"}
        )

@app.function_name(name="CarbonEmissionsExporter")
@app.timer_trigger(schedule="0 0 12 * * *", arg_name="timer", run_on_startup=False)
def carbon_emissions_exporter(timer: func.TimerRequest) -> None:
    """Timer trigger function that exports carbon emissions data monthly on the 20th

    Runs every day to collect the latest carbon export, if not already existing.
    But the export data for the previous month is only released on the 19th of next month.

    So each day this timer event runs, it attempts to download the previous months data if
    not already existing.

    By running every day, it allows for late release of the data by Microsoft.
    """
    utc_timestamp = datetime.now(timezone.utc).isoformat()

    logger.info(f'Carbon emissions exporter triggered at: {utc_timestamp}')

    if timer.past_due:
        logging.debug('The timer is past due!')

    try:
        # Get previous month date range using dynamic API range calculation
        carbon_api_fetch_date = carbon_export_api_latest_fetch_date()
        logger.info(f'Exporting carbon data month: {carbon_api_fetch_date.strftime("%Y-%m")}')

        # Get access token using managed identity
        token = TokenManager().azure_token
        logger.debug(f"cost_mgmt_export_exists: token: {token}")

        # Prepare the API request
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }

        # Save to storage and upload to S3
        file_name = f"carbon-emissions-{carbon_api_fetch_date.strftime('%Y-%m')}.json"

        # Check if data already exists
        exists, existing_path = check_carbon_data_exists(file_name)
        if exists:
            logger.info(f"Carbon data for {carbon_api_fetch_date.strftime('%Y-%m')} already exists at {existing_path}.")
            return  # Exit early if data already exists

        # Extract subscription IDs from billing scope
        subscription_ids = extract_subscription_ids_from_billing_scope(Config.billing_scope)

        # Log the full request payload (excluding sensitive headers)
        logger.info(f"Carbon API request will include {len(subscription_ids)} subscriptions target date")

        # Call Carbon Optimization API using batched helper function
        success, emissions_data, error_message = make_carbon_api_request_batched(
            headers, subscription_ids, carbon_api_fetch_date.strftime('%Y-%m-%d')
        )

        if success:
            # Log response details for confirmation
            logger.info(f"Carbon API response received successfully")

            # Log batching information if available
            if "_batchingMetadata" in emissions_data:
                metadata = emissions_data["_batchingMetadata"]
                logger.info(f"Batching summary: {metadata['successful_batches']}/{metadata['total_batches']} batches successful, {metadata['total_subscriptions']} total subscriptions")
                if metadata['failed_batches'] > 0:
                    logger.warning(f"Note: {metadata['failed_batches']} batches failed - some subscription data may be missing")

            logger.info(f"Response data structure: {json.dumps(emissions_data, indent=2)[:1000]}...")  # First 1000 chars

            if 'value' in emissions_data and len(emissions_data['value']) > 0:
                first_record = emissions_data['value'][0]
                logger.info(f"First record - Date: {first_record.get('date')}, Emissions: {first_record.get('latestMonthEmissions')}, Data Type: {first_record.get('dataType')}")
                logger.info(f"Total records in response: {len(emissions_data['value'])}")
            else:
                logger.warning("No data found in Carbon API response")

            # Save to storage and upload to S3
            save_carbon_data_to_s3(emissions_data, file_name)

            logger.info(f"Successfully exported carbon emissions data for {carbon_api_fetch_date.strftime('%Y-%m-%d')}")

        else:
            logger.error(f"Carbon API request failed: {error_message}")
            logger.error(f"Request was for {len(subscription_ids)} subscriptions")
            logger.error(f"Attempted date: {carbon_api_fetch_date.strftime('%Y-%m-%d')}")
            raise Exception(f"Carbon API request failed: {error_message}")

    except Exception as e:
        logger.error(f"Error in carbon emissions exporter: {str(e)}")
        raise

@app.function_name(name="CarbonEmissionsBackfill")
@app.route(route="carbon-backfill", auth_level=func.AuthLevel.FUNCTION)
def carbon_emissions_backfill(req: func.HttpRequest) -> func.HttpResponse:
    """HTTP trigger function for carbon emissions backfill from given start date in ISO format (YYYY-MM-DD)
    Query parameters:
    - start_date: Required parameter; is the ISO date (YYYY-MM-DD) to start backfill from, e.g. 2024-01-01
    - write_empty_object: Set to 'false' to skip writing an empty result set - if date range exists Azure API range (default: true)
    - force_overwrite: Set to 'true' to overwrite existing data (default: false)
    - skip_existing: Set to 'false' to process all months regardless of existing data (default: true)
    """
    utc_timestamp = datetime.now(timezone.utc).isoformat()

    logger.info(f'Carbon emissions backfill triggered at: {utc_timestamp}')

    # Parse query parameters
    force_overwrite = req.params.get('force_overwrite', 'false').lower() == 'true'
    write_empty_object = req.params.get('write_empty_object', 'true').lower() == 'true'
    skip_existing = req.params.get('skip_existing', 'true').lower() == 'true'
    start_date_param = req.params.get('start_date')
    logger.info(f"Backfill parameters: force_overwrite={force_overwrite}, skip_existing={skip_existing}, start_date={start_date_param}, write_empty_object={write_empty_object}")

    try:
        # check parameters
        try:
            start_date = datetime.strptime(start_date_param, '%Y-%m-%d')
        except:
            raise Exception(f"Invalid start_date parameter: {start_date_param}. Given start date in format: 'YYYY-MM-DD'")

        processed_months, skipped_months = carbon_emissions_backfill_imp(
            start_date=start_date,
            skip_existing=skip_existing,
            force_overwrite=force_overwrite,
            write_empty_object=write_empty_object,
        )
        logger.info(f"Carbon backfill completed. Processed {processed_months} months, skipped {skipped_months} existing months.")

        return func.HttpResponse(
            f"Carbon backfill completed successfully. Processed {processed_months} months, skipped {skipped_months} existing months.",
            status_code=200
        )

    except Exception as e:
        error_msg = f"Error in carbon emissions backfill: {str(e)}"
        logger.error(error_msg)
        return func.HttpResponse(
            error_msg,
            status_code=500
        )

@app.function_name(name="BackfillTrigger")
@app.timer_trigger(schedule="0 0 6 * * 1-5", arg_name="timer", run_on_startup=False)
def backfill_trigger(timer: func.TimerRequest) -> None:
    """Timer trigger function that triggers the running of backfill for both cost export and carbon export.

    Checks for backfill export lock objects on the target S3 bucket; if exists, does nothing, else
    run the associated CostExportBackfill and CarbonEmissionsBackfill.
    """
    utc_timestamp = datetime.now(timezone.utc).isoformat()

    logger.info(f'Exporter backfill trigger at: {utc_timestamp}')

    try:
        # get the backfill start date from ENV VAR on the function
        logging.debug(f"Backfill start date from ENV VAR: {Config.backfill_start_date}")

        start_date = datetime.strptime(Config.backfill_start_date, '%Y-%m-%d')
        cost_export_backfill_impl(
            start_date=start_date,
            force_overwrite=False,
            skip_existing=True,
        )

        processed_months, skipped_months = carbon_emissions_backfill_imp(
            start_date=start_date,
            skip_existing=True,
            force_overwrite=False,
            write_empty_object=True,
        )
        logger.info(f"Carbon backfill completed. Processed {processed_months} months, skipped {skipped_months} existing months.")

    except Exception as e:
        error_msg = f"Error in backfill_trigger: {str(e)}"
        logger.error(error_msg)

@app.function_name(name="CostExportBackfill")
@app.route(route="cost-export-backfill", auth_level=func.AuthLevel.FUNCTION)
def cost_export_backfill(req: func.HttpRequest) -> func.HttpResponse:
    """HTTP trigger function for cost export backfill from given start date in ISO format (YYYY-MM-DD).

    The Cost Management API supports up to 7 years of data, so the start_date will be no older than 7 years:
      https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-improved-exports.

    Query parameters:
    - start_date: Required parameter; is the ISO date (YYYY-MM-DD) to start backfill from, e.g. 2024-01-01
    - force_overwrite: Set to 'true' to overwrite existing data (default: false)
    - backfill_skip_existing: Set to 'false' to process all months regardless of existing data (default: true)
    """
    utc_timestamp = datetime.now(timezone.utc).isoformat()
    logger.info(f'Cost export backfill triggered at: {utc_timestamp}')

    try:
        # Parse query parameters
        force_overwrite = req.params.get('force_overwrite', 'false').lower() == 'true'
        skip_existing = req.params.get('skip_existing', 'true').lower() == 'true'
        start_date_param = req.params.get('start_date')
        logger.info(f"Backfill parameters: force_overwrite={force_overwrite}, skip_existing={skip_existing}, start_date={start_date_param}")

        start_date = datetime.strptime(start_date_param, '%Y-%m-%d')
        cost_export_backfill_impl(start_date=start_date, force_overwrite=force_overwrite, skip_existing=skip_existing)

        return func.HttpResponse(
            f"Cost Export backfill completed successfully.",
            status_code=200
        )

    except Exception as e:
        error_msg = f"Error in cost_export_backfill: {str(e)}"
        logger.error(error_msg)
        return func.HttpResponse(
            error_msg,
            status_code=500
        )
