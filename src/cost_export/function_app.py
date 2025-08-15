import azure.functions as func
import logging
from shared_code import Config, getS3FileSystem, is_uuid, extract_subscription_ids_from_billing_scope, extract_billing_account_from_blob_path
import pyarrow.parquet as pq
import io
import json
import requests
from azure.storage.blob import BlobServiceClient
from azure.identity import ManagedIdentityCredential
from datetime import datetime, timezone, timedelta

app = func.FunctionApp()

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
                    filename_parts.append(billing_account_folder)
                
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
        # Get previous month date range
        # API available range: 2024-06-01 to 2025-06-01
        today = datetime.now(timezone.utc)
        last_month = today.replace(day=1) - timedelta(days=1)
        
        # Ensure we're within the API's available date range (2024-06-01 to 2025-06-01)
        api_end_date = datetime(2025, 6, 1, tzinfo=timezone.utc)
        api_start_date = datetime(2024, 6, 1, tzinfo=timezone.utc)
        
        if last_month > api_end_date.replace(day=1) - timedelta(days=1):
            # If requesting beyond API range, use the last available month (May 2025)
            last_month = datetime(2025, 5, 31, tzinfo=timezone.utc)
        elif last_month < api_start_date:
            # If before API range, use the first available month (June 2024)
            last_month = datetime(2024, 6, 30, tzinfo=timezone.utc)
            
        start_date = last_month.strftime("%Y-%m-01")
        end_date = last_month.strftime("%Y-%m-%d")
        
        logging.info(f'Exporting carbon data for period: {start_date} to {end_date} (within API range 2024-06-01 to 2025-06-01)')
        
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
        logging.info(f"First 10 subscription IDs: {subscription_ids[:10]}")
        if len(subscription_ids) > 10:
            logging.info(f"... and {len(subscription_ids) - 10} more subscriptions")
        
        # Call Carbon Optimization API for MonthlySummaryReport
        api_url = "https://management.azure.com/providers/Microsoft.Carbon/carbonEmissionReports"
        api_version = "2025-04-01"
        
        request_data = {
            "reportType": "MonthlySummaryReport",
            "subscriptionList": subscription_ids,
            "carbonScopeList": ["Scope1", "Scope3"],
            "dateRange": {
                "start": start_date,
                "end": start_date
            }
        }
        
        # Log the full request payload (excluding sensitive headers)
        logging.info(f"Carbon API request URL: {api_url}?api-version={api_version}")
        logging.info(f"Carbon API request payload: {json.dumps(request_data, indent=2)}")
        
        response = requests.post(
            f"{api_url}?api-version={api_version}",
            headers=headers,
            json=request_data,
            timeout=300
        )
        
        if response.status_code == 200:
            emissions_data = response.json()
            
            # Log response details for confirmation
            logging.info(f"Carbon API response received successfully")
            logging.info(f"Response data structure: {json.dumps(emissions_data, indent=2)[:1000]}...")  # First 1000 chars
            
            if 'value' in emissions_data and len(emissions_data['value']) > 0:
                first_record = emissions_data['value'][0]
                logging.info(f"First record - Date: {first_record.get('date')}, Emissions: {first_record.get('latestMonthEmissions')}, Data Type: {first_record.get('dataType')}")
                logging.info(f"Total records in response: {len(emissions_data['value'])}")
            else:
                logging.warning("No data found in Carbon API response")
            
            # Save to storage and upload to S3
            file_name = f"carbon-emissions-{last_month.strftime('%Y-%m')}.json"
            save_carbon_data_to_s3(emissions_data, file_name)
            
            logging.info(f"Successfully exported carbon emissions data for {start_date} to {end_date}")
            
        else:
            logging.error(f"Carbon API request failed with status {response.status_code}: {response.text}")
            logging.error(f"Request headers (auth redacted): Content-Type: {headers.get('Content-Type')}")
            logging.error(f"Request was for {len(subscription_ids)} subscriptions")
            
    except Exception as e:
        logging.error(f"Error in carbon emissions exporter: {str(e)}")
        raise

@app.function_name(name="CarbonEmissionsBackfill")
@app.route(route="carbon-backfill", auth_level=func.AuthLevel.FUNCTION)
def carbon_emissions_backfill(req: func.HttpRequest) -> func.HttpResponse:
    """HTTP trigger function for carbon emissions backfill from 2022-01-01"""
    utc_timestamp = datetime.now(timezone.utc).isoformat()
    
    logging.info(f'Carbon emissions backfill triggered at: {utc_timestamp}')
    
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
        
        # API available range: 2024-06-01 to 2025-06-01, but we'll process from 2022-01
        # Generate months from 2022-01 to 2024-05 (before API range)
        start_year, start_month = 2022, 1
        api_start_year, api_start_month = 2024, 6
        
        current_year, current_month = start_year, start_month
        processed_months = 0
        
        while (current_year, current_month) < (api_start_year, api_start_month):
            month_date = datetime(current_year, current_month, 1, tzinfo=timezone.utc)
            month_str = month_date.strftime("%Y-%m-01")
            
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
            
            file_name = f"carbon-emissions-{month_date.strftime('%Y-%m')}.json"
            save_carbon_data_to_s3(empty_emissions_data, file_name)
            processed_months += 1
            
            # Move to next month
            if current_month == 12:
                current_year += 1
                current_month = 1
            else:
                current_month += 1
        
        # Now process months within API range (2024-06 to 2025-05)
        current_year, current_month = api_start_year, api_start_month
        api_end_year, api_end_month = 2025, 6  # API goes up to 2025-06-01
        
        while (current_year, current_month) < (api_end_year, api_end_month):
            month_date = datetime(current_year, current_month, 1, tzinfo=timezone.utc)
            month_str = month_date.strftime("%Y-%m-01")
            
            logging.info(f"Processing month: {month_str} (within API range)")
            
            # Call Carbon Optimization API
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
            
            response = requests.post(
                f"{api_url}?api-version={api_version}",
                headers=headers,
                json=request_data,
                timeout=300
            )
            
            if response.status_code == 200:
                emissions_data = response.json()
                file_name = f"carbon-emissions-{month_date.strftime('%Y-%m')}.json"
                save_carbon_data_to_s3(emissions_data, file_name)
                processed_months += 1
                logging.info(f"Successfully processed {month_str}")
            else:
                logging.error(f"API request failed for {month_str}: {response.status_code} - {response.text}")
            
            # Move to next month
            if current_month == 12:
                current_year += 1
                current_month = 1
            else:
                current_month += 1
        
        logging.info(f"Carbon backfill completed. Processed {processed_months} months total.")
        
        return func.HttpResponse(
            f"Carbon backfill completed successfully. Processed {processed_months} months.",
            status_code=200
        )
        
    except Exception as e:
        error_msg = f"Error in carbon emissions backfill: {str(e)}"
        logging.error(error_msg)
        return func.HttpResponse(
            error_msg,
            status_code=500
        )

def save_recommendations_to_s3(data, file_name):
    """Save Azure Advisor recommendations data to S3"""
    try:
        # Convert to JSON string
        json_data = json.dumps(data, indent=2).encode('utf-8')
        
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

def save_carbon_data_to_s3(data, file_name):
    """Save carbon emissions data to S3"""
    try:
        # Convert to JSON string
        json_data = json.dumps(data, indent=2).encode('utf-8')
        
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
            
        logging.info(f"Successfully uploaded carbon data to S3: {s3_path}")
        
    except Exception as e:
        logging.error(f"Error saving carbon data to S3: {str(e)}")
        raise