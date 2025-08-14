import logging
import azure.functions as func
from cost_export.utils import Config, extract_subscription_ids_from_billing_scope, getS3FileSystem
import requests
import json
from azure.identity import ManagedIdentityCredential
from datetime import datetime, timezone, timedelta

app = func.FunctionApp()

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