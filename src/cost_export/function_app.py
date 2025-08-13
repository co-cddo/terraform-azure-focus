import logging
import os
import azure.functions as func
import pyarrow.parquet as pq
import pandas as pd
import io
import boto3
import requests
import json
from azure.identity import ManagedIdentityCredential
from pyarrow.fs import S3FileSystem
from azure.storage.blob import BlobServiceClient
from datetime import datetime, timezone, timedelta

# Environment variables - examples of expected values:
client_id = os.environ.get("ENTRA_APP_CLIENT_ID")  # Example: "00000000-0000-0000-0000-000000000000"
urn = os.environ.get("ENTRA_APP_URN")  # Example: "api://AWS-Federation-App"
arn = os.environ.get("AWS_ROLE_ARN")  # Example: "arn:aws:iam::000000000000:role/aad_s3"
s3_focus_path = os.environ.get("S3_FOCUS_PATH")  # Example: "s3://s3bucketname/test/"
aws_region = os.environ.get("AWS_REGION")  # Example: "eu-west-2"
storage_connection_string = os.environ.get("STORAGE_CONNECTION_STRING")
container_name = os.environ.get("CONTAINER_NAME")
utilization_container_name = os.environ.get("UTILIZATION_CONTAINER_NAME")
s3_utilization_path = os.environ.get("S3_UTILIZATION_PATH")
s3_carbon_path = os.environ.get("S3_CARBON_PATH")
carbon_directory_name = os.environ.get("CARBON_DIRECTORY_NAME")

# Carbon Optimization API settings
carbon_tenant_id = os.environ.get("CARBON_API_TENANT_ID")
billing_scope = os.environ.get("BILLING_SCOPE")
 
app = func.FunctionApp()
 
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
        blob_url = message_body.get("subject", "")
        
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
        blob_service_client = BlobServiceClient.from_connection_string(storage_connection_string)
        container_client = blob_service_client.get_container_client(container_name)
        
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
            # Example: /7a770e35-b455-4df2-a276-b07408438d9a/gds-focus-v1/focus-backfill-2025-06/billing_period=20250601/202508131031/part_0_0001.parquet
            # Becomes: /7a770e35-b455-4df2-a276-b07408438d9a/gds-focus-v1/billing_period=20250601/part_0_0001.parquet
            path_parts = blob_name.split('/')
            modified_parts = []
            
            for part in path_parts:
                if part == "focus-daily-cost-export":
                    # Skip this part entirely
                    continue
                elif part.startswith("focus-backfill-"):
                    # Skip focus-backfill-YYYY-MM directories
                    logging.info(f"Skipping focus-backfill directory: {part}")
                    continue
                elif len(part) == 12 and part.isdigit():
                    # Skip timestamp directories (format: YYYYMMDDHHMM)
                    logging.info(f"Skipping timestamp directory: {part}")
                    continue
                elif "-" in part and len(part) == 17 and part[:8].isdigit() and part[9:17].isdigit():
                    # Transform date range (e.g., "20250801-20250831" -> "billing_period=20250801")
                    billing_period = part.split("-")[0]
                    modified_parts.append(f"billing_period={billing_period}")
                elif len(part) == 36 and part.count('-') == 4 and all(c.isalnum() or c == '-' for c in part):
                    # Skip GUID directories (format: 8-4-4-4-12 characters)
                    logging.info(f"Skipping GUID directory: {part}")
                    continue
                else:
                    modified_parts.append(part)
            
            modified_path = '/'.join(modified_parts)
            s3_path = f"{s3_focus_path.rstrip('/')}/{modified_path}"
            pq.write_table(table, where=s3_path, filesystem=s3, compression='snappy')
            logging.info(f"Successfully uploaded {blob_name} to S3 at path: {s3_path}")

            # Delete source file after successful upload
            blob_client.delete_blob()
            logging.info(f"Successfully deleted source file: {blob_name}")
            
        except Exception as e:
            logging.error(f"Failed to process {blob_name}: {str(e)}")
            raise
            
    except Exception as e:
        logging.error(f"Error in daily cost export processor: {str(e)}")
        raise

def getS3FileSystem():
    default_credential = ManagedIdentityCredential()
    token = default_credential.get_token(urn)

    role = boto3.client('sts').assume_role_with_web_identity(
        RoleArn=arn,
        RoleSessionName='session1',
        WebIdentityToken=token.token
        )
        
    credentials = role['Credentials']
    aws_access_key_id = credentials['AccessKeyId']
    aws_secret_access_key = credentials['SecretAccessKey']
    aws_session_token = credentials['SessionToken']
        
    return S3FileSystem(
        access_key=aws_access_key_id,
        secret_key=aws_secret_access_key,
        session_token=aws_session_token,
        region=aws_region
    )

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
        subscription_ids = extract_subscription_ids_from_billing_scope(billing_scope)
        
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

def extract_subscription_ids_from_billing_scope(scope):
    """Extract all subscription IDs that belong to the billing scope"""
    try:
        # Get access token using managed identity
        credential = ManagedIdentityCredential()
        token = credential.get_token("https://management.azure.com/.default")
        
        headers = {
            "Authorization": f"Bearer {token.token}",
            "Content-Type": "application/json"
        }
        
        subscription_ids = []
        
        # Parse the billing scope type and extract subscription IDs accordingly
        if "/providers/Microsoft.Billing/billingAccounts/" in scope:
            # Billing Account scope - get all subscriptions under this billing account
            subscription_ids = get_subscriptions_from_billing_account(scope, headers)
            
        elif "/providers/Microsoft.Management/managementGroups/" in scope:
            # Management Group scope - get all subscriptions under this management group
            subscription_ids = get_subscriptions_from_management_group(scope, headers)
            
        elif "/subscriptions/" in scope and scope.count("/") == 2:
            # Single subscription scope - extract the subscription ID directly
            subscription_id = scope.split("/")[2]
            subscription_ids = [subscription_id]
            logging.info(f"Single subscription scope detected: {subscription_id}")
        elif "subscriptions/" in scope and scope.count("/") == 1:
            # Single subscription scope without leading slash - extract the subscription ID directly
            subscription_id = scope.split("/")[1]
            subscription_ids = [subscription_id]
            logging.info(f"Single subscription scope detected (no leading slash): {subscription_id}")
            
        else:
            logging.error(f"Unsupported billing scope format: {scope}")
            return []
        
        logging.info(f"Found {len(subscription_ids)} subscriptions in billing scope")
        return subscription_ids
        
    except Exception as e:
        logging.error(f"Error extracting subscription IDs: {str(e)}")
        return []

def get_subscriptions_from_billing_account(scope, headers):
    """Get all subscription IDs from a billing account scope"""
    try:
        # Extract billing account ID from scope
        # Format: /providers/Microsoft.Billing/billingAccounts/{billingAccountId}
        billing_account_id = scope.split("/")[-1]
        
        # Query billing subscriptions API
        api_url = f"https://management.azure.com/providers/Microsoft.Billing/billingAccounts/{billing_account_id}/billingSubscriptions"
        api_version = "2020-05-01"
        
        response = requests.get(
            f"{api_url}?api-version={api_version}",
            headers=headers,
            timeout=60
        )
        
        if response.status_code == 200:
            data = response.json()
            subscription_ids = []
            
            for subscription in data.get("value", []):
                # Extract subscription ID from the subscription properties
                sub_id = subscription.get("properties", {}).get("subscriptionId")
                if sub_id:
                    subscription_ids.append(sub_id)
                    
            logging.info(f"Retrieved {len(subscription_ids)} subscriptions from billing account {billing_account_id}")
            return subscription_ids
            
        else:
            logging.error(f"Failed to get subscriptions from billing account: {response.status_code} - {response.text}")
            return []
            
    except Exception as e:
        logging.error(f"Error getting subscriptions from billing account: {str(e)}")
        return []

def get_subscriptions_from_management_group(scope, headers):
    """Get all subscription IDs from a management group scope using Resource Graph API"""
    try:
        # Extract management group ID from scope
        # Format: /providers/Microsoft.Management/managementGroups/{managementGroupId}
        mg_id = scope.split("/")[-1]
        
        # Use Resource Graph API to get subscriptions under management group
        subscription_ids = get_subscriptions_via_resource_graph(mg_id, headers)
        
        logging.info(f"Retrieved {len(subscription_ids)} subscriptions from management group {mg_id}")
        return subscription_ids
            
    except Exception as e:
        logging.error(f"Error getting subscriptions from management group: {str(e)}")
        return []

def get_subscriptions_via_resource_graph(mg_id, headers):
    """Get subscriptions using Azure Resource Graph API"""
    try:
        # Use Resource Graph to query subscriptions under management group
        api_url = "https://management.azure.com/providers/Microsoft.ResourceGraph/resources"
        api_version = "2021-03-01"
        
        # Query to get all subscriptions under the management group
        query_data = {
            "query": f"ResourceContainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId",
            "managementGroups": [mg_id]
        }
        
        response = requests.post(
            f"{api_url}?api-version={api_version}",
            headers=headers,
            json=query_data,
            timeout=60
        )
        
        if response.status_code == 200:
            data = response.json()
            subscription_ids = []
            
            for row in data.get("data", []):
                if "subscriptionId" in row:
                    subscription_ids.append(row["subscriptionId"])
                    
            logging.info(f"Resource Graph API found {len(subscription_ids)} subscriptions under management group {mg_id}")
            return subscription_ids
            
        else:
            logging.error(f"Resource Graph API failed: {response.status_code} - {response.text}")
            return []
            
    except Exception as e:
        logging.error(f"Error using Resource Graph API: {str(e)}")
        return []

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
        s3_path = f"{s3_carbon_path.rstrip('/')}/{carbon_directory_name}/billing_period={billing_period}/{file_name}"
        
        # Upload to S3
        with s3.open_output_stream(s3_path) as f:
            f.write(json_data)
            
        logging.info(f"Successfully uploaded carbon data to S3: {s3_path}")
        
    except Exception as e:
        logging.error(f"Error saving carbon data to S3: {str(e)}")
        raise

@app.function_name(name="UtilizationExportProcessor")
@app.queue_trigger(arg_name="msg", queue_name="utilizationdata", connection="StorageAccountManagedIdentity")
def utilization_export_processor(msg: func.QueueMessage) -> None:
    """Queue trigger function that processes utilization CSV files when messages are received"""
    utc_timestamp = datetime.now(timezone.utc).isoformat()

    logging.info(f'Utilization export processor triggered at: {utc_timestamp}')
    logging.info(f'Processing message: {msg.get_body().decode("utf-8")}')
    
    try:
        # Parse the EventGrid message to get the specific blob
        message_body = json.loads(msg.get_body().decode("utf-8"))
        blob_url = message_body.get("subject", "")
        
        # Extract blob name from the subject (format: /blobServices/default/containers/{container}/blobs/{blobname})
        blob_name = None
        if blob_url.startswith("/blobServices/default/containers/"):
            parts = blob_url.split("/blobs/", 1)
            if len(parts) == 2:
                blob_name = parts[1]
        
        if not blob_name:
            logging.error(f"Could not extract blob name from message subject: {blob_url}")
            return
            
        if not blob_name.endswith('.csv.gz'):
            logging.info(f"Skipping non-CSV.GZ file: {blob_name}")
            return
            
        logging.info(f"Processing specific utilization CSV.GZ file: {blob_name}")
        
        # Initialize blob service client
        blob_service_client = BlobServiceClient.from_connection_string(storage_connection_string)
        container_client = blob_service_client.get_container_client(utilization_container_name)
        
        # Get S3 filesystem
        s3 = getS3FileSystem()
        
        # Process the specific blob from the message
        try:
            # Download blob content
            blob_client = container_client.get_blob_client(blob_name)
            blob_data = blob_client.download_blob().readall()
            
            # Transform S3 path
            # Example blob_name: utilization-data/utilization-export/20250801-20250831/f2d6918d-67e2-4a1e-b5f6-9a69f1a87160/part_0_0001.csv.gz
            # Final S3 path: {aws_target_file_path}/gds-recommendations-v1/billing_period=20250801/part_0_0001.csv.gz
            path_parts = blob_name.split('/')
            modified_parts = []
            
            for part in path_parts:
                if part == "utilization-data" or part == "utilization-export":
                    # Skip these parts entirely
                    continue
                elif "-" in part and len(part) == 17 and part[:8].isdigit() and part[9:17].isdigit():
                    # Transform date range (e.g., "20250801-20250831" -> "billing_period=20250801")
                    billing_period = part.split("-")[0]
                    modified_parts.append(f"billing_period={billing_period}")
                elif len(part) == 36 and part.count('-') == 4 and all(c.isalnum() or c == '-' for c in part):
                    # Skip GUID directories (format: 8-4-4-4-12 characters)
                    logging.info(f"Skipping GUID directory: {part}")
                    continue
                else:
                    modified_parts.append(part)
            
            modified_path = '/'.join(modified_parts)
            s3_path = f"{s3_utilization_path.rstrip('/')}/{modified_path}"
            
            # Upload to S3
            with s3.open_output_stream(s3_path) as f:
                f.write(blob_data)
            logging.info(f"Successfully uploaded {blob_name} to S3 at path: {s3_path}")
            
            # Delete source file after successful upload
            blob_client.delete_blob()
            logging.info(f"Successfully deleted source file: {blob_name}")
            
        except Exception as e:
            logging.error(f"Failed to process {blob_name}: {str(e)}")
            raise
            
    except Exception as e:
        logging.error(f"Error in utilization export processor: {str(e)}")
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
        subscription_ids = extract_subscription_ids_from_billing_scope(billing_scope)
        
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
