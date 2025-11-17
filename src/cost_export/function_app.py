import azure.functions as func
import logging
from common import Config, getS3FileSystem, is_uuid, extract_subscription_ids_from_billing_scope, extract_billing_account_from_blob_path
import pyarrow.parquet as pq
import pyarrow.fs as fs
import io
import json
import requests
from azure.storage.blob import BlobServiceClient
from azure.identity import ManagedIdentityCredential
from datetime import datetime, timezone, timedelta

app = func.FunctionApp()

def get_carbon_api_date_range():
    """
    Calculate the available date range for the Carbon Optimization API.
    
    Based on Microsoft documentation:
    - Data for the previous month is available by day 19 of the current month
    - API provides access to up to 12 months of emissions data (rolling window)
    - Data is updated monthly with 12-month retention
    
    Returns:
        tuple: (start_date, end_date) as datetime objects representing the available range
    """
    today = datetime.now(timezone.utc)
    
    # Data for previous month is available by day 19
    # If today is before the 19th, last available data is from 2 months ago
    # If today is on/after the 19th, last available data is from last month
    if today.day >= 19:
        # Latest data available is from last month
        latest_available_month = today.replace(day=1) - timedelta(days=1)  # Last day of previous month
    else:
        # Latest data available is from 2 months ago
        last_month = today.replace(day=1) - timedelta(days=1)  # Last day of previous month
        latest_available_month = last_month.replace(day=1) - timedelta(days=1)  # Last day of month before that
    
    # API provides 12 months of data, so earliest available is 12 months before latest
    earliest_available_month = latest_available_month.replace(day=1)  # First day of latest month
    for _ in range(11):  # Go back 11 more months (total 12 months)
        if earliest_available_month.month == 1:
            earliest_available_month = earliest_available_month.replace(year=earliest_available_month.year - 1, month=12)
        else:
            earliest_available_month = earliest_available_month.replace(month=earliest_available_month.month - 1)
    
    # Convert to first day of earliest month and last day of latest month
    start_date = earliest_available_month
    end_date = latest_available_month
    
    return start_date, end_date

def is_month_within_api_range(target_month):
    """
    Check if a given month is within the Carbon API's available date range.
    
    Args:
        target_month (datetime): The month to check
        
    Returns:
        bool: True if the month is within the available range
    """
    start_date, end_date = get_carbon_api_date_range()
    
    # Convert target_month to first day of month for comparison
    target_first_day = target_month.replace(day=1)
    start_first_day = start_date.replace(day=1)
    end_first_day = end_date.replace(day=1)
    
    return start_first_day <= target_first_day <= end_first_day

def make_carbon_api_request(headers, subscription_ids, month_str, timeout=300):
    """
    Make a Carbon Optimization API request with proper error handling.
    
    Args:
        headers (dict): Request headers including authorization
        subscription_ids (list): List of subscription IDs
        month_str (str): Month string in YYYY-MM-DD format
        timeout (int): Request timeout in seconds
        
    Returns:
        tuple: (success: bool, data: dict or None, error_message: str or None)
    """
    api_url = "https://management.azure.com/providers/Microsoft.Carbon/carbonEmissionReports"
    api_version = "2025-04-01"
    
    request_data = {
        "reportType": "MonthlySummaryReport",
        "subscriptionList": subscription_ids,
        "carbonScopeList": ["Scope1", "Scope3"],
        "dateRange": {
            "start": month_str,
            "end": month_str
        }
    }
    
    try:
        response = requests.post(
            f"{api_url}?api-version={api_version}",
            headers=headers,
            json=request_data,
            timeout=timeout
        )
        
        if response.status_code == 200:
            return True, response.json(), None
        else:
            error_msg = f"API request failed with status {response.status_code}: {response.text}"
            # Check if it's a date range error
            if response.status_code == 400 and "InvalidRequestPropertyValue" in response.text:
                if "should be in available range" in response.text:
                    error_msg += " - Date is outside the available range for Carbon Optimization API"
            elif response.status_code == 400 and "InvalidNumberOfSubscriptions" in response.text:
                error_msg += " - Too many subscriptions in request (max 100 allowed)"
            return False, None, error_msg
            
    except requests.exceptions.Timeout:
        return False, None, f"API request timed out after {timeout} seconds"
    except requests.exceptions.RequestException as e:
        return False, None, f"API request failed: {str(e)}"
    except Exception as e:
        return False, None, f"Unexpected error in API request: {str(e)}"

def make_carbon_api_request_batched(headers, subscription_ids, month_str, timeout=300, max_batch_size=100):
    """
    Make Carbon Optimization API requests in batches to handle subscription limits.
    
    The Carbon API has a maximum of 100 subscriptions per request. This function
    automatically batches large subscription lists and merges the results.
    
    Args:
        headers (dict): Request headers including authorization
        subscription_ids (list): List of subscription IDs (can be > 100)
        month_str (str): Month string in YYYY-MM-DD format
        timeout (int): Request timeout in seconds per batch
        max_batch_size (int): Maximum subscriptions per API call (default: 100)
        
    Returns:
        tuple: (success: bool, merged_data: dict or None, error_message: str or None)
    """
    if not subscription_ids:
        return False, None, "No subscription IDs provided"
    
    total_subscriptions = len(subscription_ids)
    logging.info(f"Carbon API request for {total_subscriptions} subscriptions (batching with max {max_batch_size} per request)")
    
    # If within limit, use single request
    if total_subscriptions <= max_batch_size:
        return make_carbon_api_request(headers, subscription_ids, month_str, timeout)
    
    # Batch the subscriptions
    batches = []
    for i in range(0, total_subscriptions, max_batch_size):
        batch = subscription_ids[i:i + max_batch_size]
        batches.append(batch)
    
    logging.info(f"Splitting into {len(batches)} batches: {[len(batch) for batch in batches]} subscriptions each")
    
    # Collect results from all batches
    merged_subscription_access_decisions = []
    merged_value_data = []
    successful_batches = 0
    failed_batches = []
    
    for batch_num, batch_subscription_ids in enumerate(batches, 1):
        logging.info(f"Processing batch {batch_num}/{len(batches)} with {len(batch_subscription_ids)} subscriptions")
        
        success, batch_data, error_message = make_carbon_api_request(
            headers, batch_subscription_ids, month_str, timeout
        )
        
        if success and batch_data:
            # Merge subscription access decisions
            if "subscriptionAccessDecisionList" in batch_data:
                merged_subscription_access_decisions.extend(batch_data["subscriptionAccessDecisionList"])
            
            # Merge value data
            if "value" in batch_data:
                merged_value_data.extend(batch_data["value"])
            
            successful_batches += 1
            logging.info(f"Batch {batch_num} completed successfully")
        else:
            failed_batches.append({"batch": batch_num, "error": error_message, "subscription_count": len(batch_subscription_ids)})
            logging.error(f"Batch {batch_num} failed: {error_message}")
    
    # Check if we have any successful data
    if successful_batches == 0:
        return False, None, f"All {len(batches)} batches failed. First error: {failed_batches[0]['error'] if failed_batches else 'Unknown error'}"
    
    # Log summary
    logging.info(f"Batched request summary: {successful_batches}/{len(batches)} batches successful")
    if failed_batches:
        failed_summary = []
        for fb in failed_batches[:3]:  # Show first 3 failures
            error_preview = fb['error'][:100] + "..." if len(fb['error']) > 100 else fb['error']
            failed_summary.append(f"Batch {fb['batch']} ({fb['subscription_count']} subs): {error_preview}")
        logging.warning(f"Failed batches: {len(failed_batches)} - {failed_summary}")
    
    # Create merged response
    merged_response = {
        "subscriptionAccessDecisionList": merged_subscription_access_decisions,
        "value": merged_value_data
    }
    
    # Add metadata about batching
    merged_response["_batchingMetadata"] = {
        "total_batches": len(batches),
        "successful_batches": successful_batches,
        "failed_batches": len(failed_batches),
        "total_subscriptions": total_subscriptions,
        "batch_size_used": max_batch_size
    }
    
    return True, merged_response, None

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
        
        logging.info(f"Carbon API date range info requested: check_existing={check_existing}")
        
        return func.HttpResponse(
            json.dumps(response_data, indent=2),
            status_code=200,
            headers={"Content-Type": "application/json"}
        )
        
    except Exception as e:
        error_msg = f"Error getting Carbon API date range info: {str(e)}"
        logging.error(error_msg)
        return func.HttpResponse(
            json.dumps({"error": error_msg}),
            status_code=500,
            headers={"Content-Type": "application/json"}
        )

# Log billing account configuration at startup
logging.info("=== Billing Account Configuration ===")
logging.info(f"Billing account mapping: {Config.billing_account_mapping}")
logging.info(f"Number of billing accounts: {len(Config.billing_account_mapping)}")
for idx, account_id in Config.billing_account_mapping.items():
    logging.info(f"Export index {idx} -> Billing Account {account_id}")
logging.info("====================================")

@app.function_name(name="CostExportProcessor")
@app.queue_trigger(arg_name="msg", queue_name="costdata", connection="StorageAccountManagedIdentity")
def cost_export_processor(msg: func.QueueMessage) -> None:
    """Queue trigger function that processes parquet files when messages are received"""
    utc_timestamp = datetime.now(timezone.utc).isoformat()

    logging.info(f'Cost export processor triggered at: {utc_timestamp}')
    logging.info(f'Processing message: {msg.get_body().decode("utf-8")}')
    
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
            logging.error(f"Could not extract blob name from message subject: {blob_url}")
            return
            
        if not blob_name.endswith('.parquet'):
            logging.info(f"Skipping non-parquet file: {blob_name}")
            return
            
        logging.info(f"Processing specific parquet file: {blob_name}")
        
        # Initialize blob service client
        blob_service_client = BlobServiceClient.from_connection_string(Config.storage_connection_string)
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
                    logging.info(f"Found billing account path in data: {full_billing_path}")
                    
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
                        
                        logging.info(f"Extracted billing account ID: {billing_account_id}")
                        if billing_profile_from_data:
                            logging.info(f"Extracted billing profile from data: {billing_profile_from_data}")
                    else:
                        # Fallback: use the full path as billing account ID
                        billing_account_id = full_billing_path
                        logging.warning(f"Could not parse billing account path, using full path: {billing_account_id}")
            
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
                    logging.info(f"Skipping focus-backfill directory: {part}")
                    i += 1
                    continue
                elif len(part) == 12 and part.isdigit():
                    # Validate that this is actually a valid YYYYMMDDHHMM timestamp
                    try:
                        datetime.strptime(part, "%Y%m%d%H%M")
                        logging.info(f"Skipping timestamp directory: {part}")
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
                    logging.info(f"Skipping UUID directory: {part}")
                    i += 1
                    continue
                elif part == "providers":
                    # Skip providers/Microsoft.Billing/billingAccounts structure and extract info
                    if (i + 3 < len(path_parts) and 
                        path_parts[i + 1] == "Microsoft.Billing" and 
                        path_parts[i + 2] == "billingAccounts"):
                        billing_account_path_part = path_parts[i + 3]
                        logging.info(f"Found billing account in path: {billing_account_path_part}")
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
                        logging.info(f"Found billing profile in path: {billing_profile_path_part}")
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
                logging.info(f"Using billing account ID from data: {billing_account_folder}")
            elif billing_account_path_part:
                # Use the billing account ID from the path
                billing_account_folder = billing_account_path_part
                logging.info(f"Using billing account ID from path: {billing_account_folder}")
            else:
                # Fallback: try to extract from blob path structure
                export_index = extract_billing_account_from_blob_path(blob_name)
                if export_index is not None and str(export_index) in Config.billing_account_mapping:
                    billing_account_folder = Config.billing_account_mapping[str(export_index)]
                    logging.info(f"Mapped export index {export_index} to billing account: {billing_account_folder}")
                else:
                    logging.warning(f"Could not determine billing account folder for {blob_name}")
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
                logging.info(f"Flattened filename: {original_filename} -> {flattened_filename}")
                
                # Reconstruct path with flattened filename
                if directory_parts:
                    modified_path = '/'.join(directory_parts) + '/' + flattened_filename
                else:
                    modified_path = flattened_filename
            else:
                modified_path = '/'.join(modified_parts)
                logging.warning(f"Could not extract filename from path parts: {modified_parts}")
            
            # Construct S3 path with flattened structure
            s3_path = f"{Config.s3_focus_path.rstrip('/')}/{modified_path.lstrip('/')}"
            
            pq.write_table(table, where=s3_path, filesystem=s3, compression='snappy')
            logging.info(f"Successfully uploaded {blob_name} to S3 at path: {s3_path} (billing account: {billing_account_folder})")

            # Delete source file after successful upload
            blob_client.delete_blob()
            logging.info(f"Successfully deleted source file: {blob_name}")
            
        except Exception as e:
            logging.error(f"Failed to process {blob_name}: {str(e)}")
            raise
            
    except Exception as e:
        logging.error(f"Error in daily cost export processor: {str(e)}")
        raise

@app.function_name(name="AdvisorRecommendationsExporter")
@app.timer_trigger(schedule="0 0 2 * * *", arg_name="timer", run_on_startup=False)
def advisor_recommendations_exporter(timer: func.TimerRequest) -> None:
    """Timer trigger function that exports Azure Advisor cost recommendations daily at 2 AM"""
    utc_timestamp = datetime.now(timezone.utc).isoformat()
    
    logging.info(f'Azure Advisor recommendations exporter triggered at: {utc_timestamp}')
    
    if timer.past_due:
        logging.info('The timer is past due!')

    try:
        # Get access token using managed identity
        credential = ManagedIdentityCredential()
        token = credential.get_token("https://management.azure.com/.default")
        
        headers = {
            "Authorization": f"Bearer {token.token}",
            "Content-Type": "application/json"
        }
        
        # Extract subscription IDs from billing scope
        subscription_ids = extract_subscription_ids_from_billing_scope(Config.billing_scope)
        
        logging.info(f"Fetching cost recommendations for {len(subscription_ids)} subscriptions")
        
        all_recommendations = []
        
        # Fetch cost recommendations for each subscription
        for subscription_id in subscription_ids:
            try:
                logging.info(f"Fetching cost recommendations for subscription: {subscription_id}")
                
                # Azure Advisor Recommendations API endpoint
                api_url = f"https://management.azure.com/subscriptions/{subscription_id}/providers/Microsoft.Advisor/recommendations"
                api_version = "2025-01-01"
                
                # Filter for cost category recommendations only
                params = {
                    "api-version": api_version,
                    "$filter": "Category eq 'Cost'"
                }
                
                logging.info(f"Calling API: {api_url} with params: {params}")
                
                response = requests.get(
                    api_url,
                    headers=headers,
                    params=params,
                    timeout=300
                )
                
                logging.info(f"API Response Status: {response.status_code}")
                
                if response.status_code == 200:
                    recommendations_data = response.json()
                    recommendations = recommendations_data.get("value", [])
                    
                    logging.info(f"Raw API response for subscription {subscription_id}: {recommendations_data}")
                    
                    # Add subscription ID to each recommendation for tracking
                    for rec in recommendations:
                        rec["subscriptionId"] = subscription_id
                    
                    all_recommendations.extend(recommendations)
                    logging.info(f"Retrieved {len(recommendations)} cost recommendations for subscription {subscription_id}")
                    
                else:
                    logging.error(f"Failed to fetch recommendations for subscription {subscription_id}: {response.status_code}")
                    logging.error(f"Response text: {response.text}")
                    logging.error(f"Response headers: {dict(response.headers)}")
                    
            except Exception as e:
                logging.error(f"Error fetching recommendations for subscription {subscription_id}: {str(e)}")
                continue
        
        if all_recommendations:
            # Save recommendations to S3
            current_date = datetime.now(timezone.utc)
            file_name = f"advisor-cost-recommendations-{current_date.strftime('%Y-%m-%d')}.json"
            save_recommendations_to_s3({"value": all_recommendations}, file_name)
            
            logging.info(f"Successfully exported {len(all_recommendations)} cost recommendations from {len(subscription_ids)} subscriptions")
        else:
            logging.warning("No cost recommendations found across all subscriptions")
            
    except Exception as e:
        logging.error(f"Error in Azure Advisor recommendations exporter: {str(e)}")
        raise

@app.function_name(name="CarbonEmissionsExporter")
@app.timer_trigger(schedule="0 0 20 * *", arg_name="timer", run_on_startup=False)
def carbon_emissions_exporter(timer: func.TimerRequest) -> None:
    """Timer trigger function that exports carbon emissions data monthly on the 20th
    
    Runs on the 20th because Azure Carbon Optimization data for the previous month
    is available by day 19 of the current month (e.g., February data available by March 19).
    """
    utc_timestamp = datetime.now(timezone.utc).isoformat()
    
    logging.info(f'Carbon emissions exporter triggered at: {utc_timestamp}')
    
    if timer.past_due:
        logging.info('The timer is past due!')

    try:
        # Get previous month date range using dynamic API range calculation
        today = datetime.now(timezone.utc)
        last_month = today.replace(day=1) - timedelta(days=1)
        
        # Get current API available date range
        api_start_date, api_end_date = get_carbon_api_date_range()
        
        logging.info(f"Current Carbon API available range: {api_start_date.strftime('%Y-%m-%d')} to {api_end_date.strftime('%Y-%m-%d')}")
        
        # Check if the requested month is within the API range
        if not is_month_within_api_range(last_month):
            if last_month < api_start_date:
                # If before API range, use the earliest available month
                last_month = api_start_date
                logging.info(f"Requested month was before API range, using earliest available: {last_month.strftime('%Y-%m-%d')}")
            elif last_month > api_end_date:
                # If after API range, use the latest available month
                last_month = api_end_date
                logging.info(f"Requested month was after API range, using latest available: {last_month.strftime('%Y-%m-%d')}")
            
        start_date = last_month.strftime("%Y-%m-01")
        end_date = last_month.strftime("%Y-%m-%d")
        
        logging.info(f'Exporting carbon data for period: {start_date} to {end_date}')
        
        # Get access token using managed identity
        credential = ManagedIdentityCredential()
        token = credential.get_token("https://management.azure.com/.default")
        
        # Prepare the API request
        headers = {
            "Authorization": f"Bearer {token.token}",
            "Content-Type": "application/json"
        }
        
        # Extract subscription IDs from billing scope
        subscription_ids = extract_subscription_ids_from_billing_scope(Config.billing_scope)
        
        # Log detailed information about the request
        logging.info(f"Preparing Carbon API request with {len(subscription_ids)} subscriptions")
        if len(subscription_ids) > 100:
            logging.info(f"Subscription count ({len(subscription_ids)}) exceeds API limit of 100 - will use batched requests")
        logging.info(f"First 10 subscription IDs: {subscription_ids[:10]}")
        if len(subscription_ids) > 10:
            logging.info(f"... and {len(subscription_ids) - 10} more subscriptions")
        
        # Log the full request payload (excluding sensitive headers)
        logging.info(f"Carbon API request will include {len(subscription_ids)} subscriptions and date range {start_date} to {end_date}")
        
        # Save to storage and upload to S3
        file_name = f"carbon-emissions-{last_month.strftime('%Y-%m')}.json"
        
        # Check if data already exists
        exists, existing_path = check_carbon_data_exists(file_name)
        if exists:
            logging.info(f"Carbon data for {last_month.strftime('%Y-%m')} already exists at {existing_path}. Skipping API call and upload.")
            return  # Exit early if data already exists
        
        # Call Carbon Optimization API using batched helper function
        success, emissions_data, error_message = make_carbon_api_request_batched(
            headers, subscription_ids, start_date
        )
        
        if success:
            # Log response details for confirmation
            logging.info(f"Carbon API response received successfully")
            
            # Log batching information if available
            if "_batchingMetadata" in emissions_data:
                metadata = emissions_data["_batchingMetadata"]
                logging.info(f"Batching summary: {metadata['successful_batches']}/{metadata['total_batches']} batches successful, {metadata['total_subscriptions']} total subscriptions")
                if metadata['failed_batches'] > 0:
                    logging.warning(f"Note: {metadata['failed_batches']} batches failed - some subscription data may be missing")
            
            logging.info(f"Response data structure: {json.dumps(emissions_data, indent=2)[:1000]}...")  # First 1000 chars
            
            if 'value' in emissions_data and len(emissions_data['value']) > 0:
                first_record = emissions_data['value'][0]
                logging.info(f"First record - Date: {first_record.get('date')}, Emissions: {first_record.get('latestMonthEmissions')}, Data Type: {first_record.get('dataType')}")
                logging.info(f"Total records in response: {len(emissions_data['value'])}")
            else:
                logging.warning("No data found in Carbon API response")
            
            # Save to storage and upload to S3
            save_carbon_data_to_s3(emissions_data, file_name)
            
            logging.info(f"Successfully exported carbon emissions data for {start_date} to {end_date}")
            
        else:
            logging.error(f"Carbon API request failed: {error_message}")
            logging.error(f"Request was for {len(subscription_ids)} subscriptions")
            logging.error(f"Attempted date range: {start_date} to {end_date}")
            logging.error(f"Current API available range: {api_start_date.strftime('%Y-%m-%d')} to {api_end_date.strftime('%Y-%m-%d')}")
            raise Exception(f"Carbon API request failed: {error_message}")
            
    except Exception as e:
        logging.error(f"Error in carbon emissions exporter: {str(e)}")
        raise

@app.function_name(name="CarbonEmissionsBackfill")
@app.route(route="carbon-backfill", auth_level=func.AuthLevel.FUNCTION)
def carbon_emissions_backfill(req: func.HttpRequest) -> func.HttpResponse:
    """HTTP trigger function for carbon emissions backfill from 2022-01-01
    
    Query parameters:
    - force_overwrite: Set to 'true' to overwrite existing data (default: false)
    - skip_existing: Set to 'false' to process all months regardless of existing data (default: true)
    """
    utc_timestamp = datetime.now(timezone.utc).isoformat()
    
    logging.info(f'Carbon emissions backfill triggered at: {utc_timestamp}')
    
    # Parse query parameters
    force_overwrite = req.params.get('force_overwrite', 'false').lower() == 'true'
    skip_existing = req.params.get('skip_existing', 'true').lower() == 'true'
    
    logging.info(f"Backfill parameters: force_overwrite={force_overwrite}, skip_existing={skip_existing}")
    
    try:
        # Get access token using managed identity
        credential = ManagedIdentityCredential()
        token = credential.get_token("https://management.azure.com/.default")
        
        headers = {
            "Authorization": f"Bearer {token.token}",
            "Content-Type": "application/json"
        }
        
        # Extract subscription IDs from billing scope
        subscription_ids = extract_subscription_ids_from_billing_scope(Config.billing_scope)
        
        logging.info(f"Starting carbon backfill for {len(subscription_ids)} subscriptions")
        
        # Get current API available date range dynamically
        api_start_date, api_end_date = get_carbon_api_date_range()
        
        logging.info(f"Current Carbon API available range: {api_start_date.strftime('%Y-%m-%d')} to {api_end_date.strftime('%Y-%m-%d')}")
        
        # Generate months from 2022-01 to the start of API range
        start_year, start_month = 2022, 1
        api_start_year, api_start_month = api_start_date.year, api_start_date.month
        
        current_year, current_month = start_year, start_month
        processed_months = 0
        skipped_months = 0
        
        # Process months before API range (create empty records)
        while (current_year, current_month) < (api_start_year, api_start_month):
            month_date = datetime(current_year, current_month, 1, tzinfo=timezone.utc)
            month_str = month_date.strftime("%Y-%m-01")
            file_name = f"carbon-emissions-{month_date.strftime('%Y-%m')}.json"
            
            # Check if data already exists
            if skip_existing:
                exists, existing_path = check_carbon_data_exists(file_name)
                if exists:
                    logging.info(f"Skipping {month_str} - data already exists at {existing_path}")
                    skipped_months += 1
                    # Move to next month
                    if current_month == 12:
                        current_year += 1
                        current_month = 1
                    else:
                        current_month += 1
                    continue
            
            logging.info(f"Processing month: {month_str} (outside API range - will create empty record)")
            
            # Create empty carbon data for months outside API range
            empty_emissions_data = {
                "value": [{
                    "dataType": "MonthlySummaryData",
                    "date": month_str,
                    "carbonIntensity": 0.0,
                    "latestMonthEmissions": 0.0,
                    "previousMonthEmissions": 0.0,
                    "monthOverMonthEmissionsChangeRatio": 0.0,
                    "monthlyEmissionsChangeValue": 0.0,
                    "note": "Data not available via API for this period"
                }]
            }
            
            save_carbon_data_to_s3(empty_emissions_data, file_name, force_overwrite=force_overwrite)
            processed_months += 1
            
            # Move to next month
            if current_month == 12:
                current_year += 1
                current_month = 1
            else:
                current_month += 1
        
        # Now process months within API range
        current_year, current_month = api_start_year, api_start_month
        api_end_year, api_end_month = api_end_date.year, api_end_date.month
        
        # Process up to and including the end month of API range
        while (current_year, current_month) <= (api_end_year, api_end_month):
            month_date = datetime(current_year, current_month, 1, tzinfo=timezone.utc)
            month_str = month_date.strftime("%Y-%m-01")
            file_name = f"carbon-emissions-{month_date.strftime('%Y-%m')}.json"
            
            # Check if data already exists
            if skip_existing:
                exists, existing_path = check_carbon_data_exists(file_name)
                if exists:
                    logging.info(f"Skipping {month_str} - data already exists at {existing_path}")
                    skipped_months += 1
                    # Move to next month
                    if current_month == 12:
                        current_year += 1
                        current_month = 1
                    else:
                        current_month += 1
                    continue
            
            logging.info(f"Processing month: {month_str} (within API range)")
            
            # Call Carbon Optimization API using batched helper function
            success, emissions_data, error_message = make_carbon_api_request_batched(
                headers, subscription_ids, month_str
            )
            
            if success:
                save_carbon_data_to_s3(emissions_data, file_name, force_overwrite=force_overwrite)
                processed_months += 1
                logging.info(f"Successfully processed {month_str}")
            else:
                logging.error(f"API request failed for {month_str}: {error_message}")
                # Continue processing other months even if one fails
            
            # Move to next month
            if current_month == 12:
                current_year += 1
                current_month = 1
            else:
                current_month += 1
        
        logging.info(f"Carbon backfill completed. Processed {processed_months} months, skipped {skipped_months} existing months.")
        logging.info(f"API range used: {api_start_date.strftime('%Y-%m-%d')} to {api_end_date.strftime('%Y-%m-%d')}")
        
        return func.HttpResponse(
            f"Carbon backfill completed successfully. Processed {processed_months} months, skipped {skipped_months} existing months. API range: {api_start_date.strftime('%Y-%m-%d')} to {api_end_date.strftime('%Y-%m-%d')}",
            status_code=200
        )
        
    except Exception as e:
        error_msg = f"Error in carbon emissions backfill: {str(e)}"
        logging.error(error_msg)
        return func.HttpResponse(
            error_msg,
            status_code=500
        )

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
        
        logging.info(f"Saving recommendations with billing_period={billing_period} to path: {s3_path}")
        
        # Upload to S3
        with s3.open_output_stream(s3_path) as f:
            f.write(json_data)
            
        logging.info(f"Successfully uploaded recommendations data to S3: {s3_path}")
        
    except Exception as e:
        logging.error(f"Error saving recommendations data to S3: {str(e)}")
        raise

def check_carbon_data_exists(file_name):
    """Check if carbon data file already exists in S3"""
    try:
        # Get S3 filesystem
        s3 = getS3FileSystem()
        
        # Create S3 path with billing period structure matching the data month
        # Extract YYYY-MM from filename like "carbon-emissions-2025-05.json"
        filename_parts = file_name.replace('.json', '').split('-')
        year_month = f"{filename_parts[-2]}-{filename_parts[-1]}"  # Get "2025-05"
        data_month = datetime.strptime(year_month, '%Y-%m')
        billing_period = data_month.strftime("%Y%m01")  # First day of data month
        s3_path = f"{Config.s3_carbon_path.rstrip('/')}/{Config.carbon_directory_name}/billing_period={billing_period}/{file_name}"
        
        # Check if file exists
        file_info = s3.get_file_info(s3_path)
        exists = file_info.type != fs.FileType.NotFound
        
        if exists:
            logging.info(f"Carbon data file already exists: {s3_path}")
        
        return exists, s3_path
        
    except Exception as e:
        logging.warning(f"Could not find existing file named '{file_name}': {str(e)} assuming it doesn't exist...")
        # If we can't check, assume it doesn't exist to be safe
        return False, None

def save_carbon_data_to_s3(data, file_name, force_overwrite=False):
    """Save carbon emissions data to S3 with idempotency check"""
    try:
        # Check if file already exists (unless forcing overwrite)
        if not force_overwrite:
            exists, s3_path = check_carbon_data_exists(file_name)
            if exists:
                logging.info(f"Skipping upload - carbon data already exists: {s3_path}")
                return True  # Return success since data already exists
        
        # Remove batching metadata before saving (internal use only)
        data_to_save = data.copy()
        if "_batchingMetadata" in data_to_save:
            batching_info = data_to_save.pop("_batchingMetadata")
            logging.info(f"Removed batching metadata before saving: {batching_info}")
        
        # Convert to JSON string
        json_data = json.dumps(data_to_save, indent=2).encode('utf-8')
        
        # Get S3 filesystem
        s3 = getS3FileSystem()
        
        # Create S3 path with billing period structure matching the data month
        # Use the same month as the data we're exporting, not the current month
        # Extract YYYY-MM from filename like "carbon-emissions-2025-05.json"
        filename_parts = file_name.replace('.json', '').split('-')
        year_month = f"{filename_parts[-2]}-{filename_parts[-1]}"  # Get "2025-05"
        data_month = datetime.strptime(year_month, '%Y-%m')
        billing_period = data_month.strftime("%Y%m01")  # First day of data month
        s3_path = f"{Config.s3_carbon_path.rstrip('/')}/{Config.carbon_directory_name}/billing_period={billing_period}/{file_name}"
        
        # Upload to S3
        with s3.open_output_stream(s3_path) as f:
            f.write(json_data)
            
        action = "Overwritten" if force_overwrite else "Uploaded"
        logging.info(f"Successfully {action.lower()} carbon data to S3: {s3_path}")
        return True
        
    except Exception as e:
        logging.error(f"Error saving carbon data to S3: {str(e)}")
        raise
