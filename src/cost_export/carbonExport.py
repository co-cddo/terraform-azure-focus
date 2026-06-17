import json
from typing import Dict
import requests
import logging
import os
from datetime import datetime, timezone, timedelta
from common import Config
from api.tokens import TokenManager
import pyarrow.fs as fs
from api.s3Api import getS3FileSystem
from api.carbonS3Api import (
    carbon_export_backfill_lock_exists,
    carbon_export_backfill_lock_create,
)
from billing import (
    extract_subscription_ids_from_billing_scope,
)

logger = logging.getLogger("cost_export")
logger.setLevel(os.environ.get('LOGGING_LEVEL', 'INFO'))

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
    logger.info(f"Carbon API request for {total_subscriptions} subscriptions (batching with max {max_batch_size} per request)")

    # If within limit, use single request
    if total_subscriptions <= max_batch_size:
        return make_carbon_api_request(headers, subscription_ids, month_str, timeout)

    # Batch the subscriptions
    batches = []
    for i in range(0, total_subscriptions, max_batch_size):
        batch = subscription_ids[i:i + max_batch_size]
        batches.append(batch)

    logger.info(f"Splitting into {len(batches)} batches: {[len(batch) for batch in batches]} subscriptions each")

    # Collect results from all batches
    merged_subscription_access_decisions = []
    merged_value_data = []
    successful_batches = 0
    failed_batches = []

    for batch_num, batch_subscription_ids in enumerate(batches, 1):
        logger.info(f"Processing batch {batch_num}/{len(batches)} with {len(batch_subscription_ids)} subscriptions")

        success, batch_data, error_message = make_carbon_api_request(
            headers, batch_subscription_ids, month_str, timeout
        )

        if success and batch_data:
            # Merge subscription access decisions
            if "subscriptionAccessDecisionList" in batch_data:
                merged_subscription_access_decisions.extend(batch_data["subscriptionAccessDecisionList"])

            # Merge value data
            if "value" in batch_data and len(batch_data["value"]) > 0:
                merged_value_data.extend(batch_data["value"])

            successful_batches += 1
            logger.info(f"Batch {batch_num} completed successfully")
        else:
            failed_batches.append({"batch": batch_num, "error": error_message, "subscription_count": len(batch_subscription_ids)})
            logger.error(f"Batch {batch_num} failed: {error_message}")

    # Log summary
    logger.info(f"Batched request summary: {successful_batches}/{len(batches)} batches successful")
    if failed_batches:
        failed_summary = []
        for fb in failed_batches[:3]:  # Show first 3 failures
            error_preview = fb['error'][:100] + "..." if len(fb['error']) > 100 else fb['error']
            failed_summary.append(f"Batch {fb['batch']} ({fb['subscription_count']} subs): {error_preview}")
        logger.warning(f"Failed batches: {len(failed_batches)} - {failed_summary}")

    # aggregate the set of batch results
    countOfBatchDataItems = len(merged_value_data)
    if countOfBatchDataItems > 0:
        accummulatedBatch = merged_value_data[0]
        for myBatchItem in merged_value_data[1:]:
            accummulatedBatch["latestMonthEmissions"] += myBatchItem["latestMonthEmissions"]
            accummulatedBatch["previousMonthEmissions"] += myBatchItem["previousMonthEmissions"]
            accummulatedBatch["monthlyEmissionsChangeValue"] += myBatchItem["monthlyEmissionsChangeValue"]
            accummulatedBatch["carbonIntensity"] += myBatchItem["carbonIntensity"]
        accummulatedBatch["monthOverMonthEmissionsChangeRatio"] = (accummulatedBatch["latestMonthEmissions"] - accummulatedBatch["previousMonthEmissions"]) / accummulatedBatch["previousMonthEmissions"]
        accummulatedBatch["carbonIntensity"] = accummulatedBatch["carbonIntensity"] / countOfBatchDataItems


        # Create merged response
        merged_response = {
            "subscriptionAccessDecisionList": merged_subscription_access_decisions,
            "value": [
                accummulatedBatch
            ]
        }
    else:
        merged_response = {
            "subscriptionAccessDecisionList": merged_subscription_access_decisions,
            "value": [
            ]
        }
    # Add metadata about batching
    merged_response["_batchingMetadata"] = {
        "total_batches": len(batches),
        "successful_batches": successful_batches,
        "failed_batches": len(failed_batches),
        "total_subscriptions": total_subscriptions,
        "batch_size_used": max_batch_size
    }

    logger.info(f"Merged response: {merged_response}")

    # success is True only if no failed batches - will force an error
    return merged_response["_batchingMetadata"]["failed_batches"] == 0, merged_response, None

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
            logger.info(f"Carbon data file already exists: {s3_path}")

        return exists, s3_path

    except Exception as e:
        logger.warning(f"Could not find existing file named '{file_name}': {str(e)} assuming it doesn't exist...")
        # If we can't check, assume it doesn't exist to be safe
        return False, None

def carbon_export_api_latest_fetch_date() -> datetime:
    DAY_OF_MONTH_EXPORT_DATA_IS_RELEASED=19
    today = datetime.now(timezone.utc)

    # carbon data for the previous month is released from the 19th of the next month
    #  this timer simply needs to attempt downloading the current month's data from the 19th
    #  and only if the current month's data does not exist.
    # Examples:
    #  1. today is 8th Dec 2025 - latest carbon export data available is 2025-10 (so start date is 2025-10-01) in API call and target S3 object is "carbon-emissions-2025-10.json"
    #  2. today is 18th Dec 2025 - latest carbon export data available is 2025-10 (so start date is 2025-10-01) in API call and target S3 object is "carbon-emissions-2025-10.json"
    #  3. today is 19th Dec 2025 - latest carbon export data available is 2025-11 (so start date is 2025-11-01) in API call and target S3 object is "carbon-emissions-2025-11.json"

    # timedelta doesn't have a month offset (so annoying) - because of the variation of days in a month - is not using it
    # if today is the carbon release day or more, then attempt to fetch last months carbon data
    # if today is less than carbon release day, then attempt to fetch the month before last's carbon data

    # but we can apply some business logic based on day export is available
    # if today's day is less than DAY_OF_MONTH_EXPORT_DATA_IS_RELEASED, then the "start date & end date" for
    #  API call use the first day of the two months previous to this month
    # else
    #  API call uses the first day of the last month previous to this month
    current_day = today.day
    NUMBER_OF_MONTH_OFFSET = 1
    if current_day < DAY_OF_MONTH_EXPORT_DATA_IS_RELEASED:
        NUMBER_OF_MONTH_OFFSET = 2

    current_month = today.month
    # months starts at one, so subtract 1 before mod and add 1 back after mod
    fetch_month = ((current_month - 1 - NUMBER_OF_MONTH_OFFSET) % 12) + 1
    fetch_year = today.year if fetch_month < current_month else today.year -1

    carbon_api_fetch_date = today.replace(year=fetch_year, month=fetch_month, day=1)
    print('API fetch date is: ', carbon_api_fetch_date.strftime('%Y-%m-%d'))

    logger.info(f'Exporting carbon data month: {carbon_api_fetch_date.strftime("%Y-%m")}')

    return carbon_api_fetch_date

def empty_emissions_data(month: str):
    return {
        "value": [{
            "dataType": "MonthlySummaryData",
            "date": month,
            "carbonIntensity": 0.0,
            "latestMonthEmissions": 0.0,
            "previousMonthEmissions": 0.0,
            "monthOverMonthEmissionsChangeRatio": 0.0,
            "monthlyEmissionsChangeValue": 0.0,
            "note": "Data not available via API for this period"
        }]
    }

def save_carbon_data_to_s3(data, file_name, force_overwrite=False):
    """Save carbon emissions data to S3 with idempotency check"""
    try:
        # Check if file already exists (unless forcing overwrite)
        if not force_overwrite:
            exists, s3_path = check_carbon_data_exists(file_name)
            if exists:
                logger.info(f"Skipping upload - carbon data already exists: {s3_path}")
                return True  # Return success since data already exists

        # Remove batching metadata before saving (internal use only)
        data_to_save = data.copy()
        if "_batchingMetadata" in data_to_save:
            batching_info = data_to_save.pop("_batchingMetadata")
            logger.info(f"Removed batching metadata before saving: {batching_info}")

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
        logger.info(f"Successfully {action.lower()} carbon data to S3: {s3_path}")
        return True

    except Exception as e:
        logger.error(f"Error saving carbon data to S3: {str(e)}", exc_info=True)
        raise

def carbon_emissions_backfill_imp(start_date: datetime, skip_existing: bool = True, force_overwrite: bool = False, write_empty_object: bool = True) -> Dict[int, int]:
    try:
        # Azure only allows up to 12 months of carbon data (thirteen months minus now)
        now = datetime.now()
        if (now - start_date).days > 400:  # 366 (leap year) days plus 31 (largest month) plus a few
            logger.info(f"Carbon Export Start date {start_date} is more than 1 year old. Setting start date to just over 1 year.")
            start_date = (now - timedelta(days=400)).replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        # first check if carbon export lock object exists
        if carbon_export_backfill_lock_exists():
            logger.info(f"Carbon Export backfill lock object exists. Skipping Carbon Export backfill")
            return (0, 0)

        logger.info(f"carbon_emissions_backfill_imp: start_date({start_date}), skip_existing({skip_existing}), force_overwrite({force_overwrite}), write_empty_object({write_empty_object})")
        current_year, current_month = start_date.year, start_date.month

        # Get access token using managed identity
        token = TokenManager().azure_token

        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }

        # Extract subscription IDs from billing scope
        subscription_ids = extract_subscription_ids_from_billing_scope(Config.billing_scope)

        logger.info(f"Starting carbon backfill for {len(subscription_ids)} subscriptions from {start_date.strftime('%Y-%m-%d')}")

        processed_months = 0
        skipped_months = 0

        # backfill should through until the latest carbon export data is available
        #  which from "carbon_emissions_exporter" is the around the 19th for the last month
        carbon_api_fetch_date = carbon_export_api_latest_fetch_date()
        latest_fetch_month, latest_fetch_year = carbon_api_fetch_date.month, carbon_api_fetch_date.year

        # Process months before API range (create empty records)
        while (current_year, current_month) <= (latest_fetch_year, latest_fetch_month):
            month_date = datetime(current_year, current_month, 1, tzinfo=timezone.utc)
            month_str = month_date.strftime("%Y-%m-01")
            file_name = f"carbon-emissions-{month_date.strftime('%Y-%m')}.json"

            # Check if data already exists
            if skip_existing:
                exists, existing_path = check_carbon_data_exists(file_name)
                if exists:
                    logger.info(f"Skipping {month_str} - data already exists at {existing_path}")
                    skipped_months += 1
                    # Move to next month
                    if current_month == 12:
                        current_year += 1
                        current_month = 1
                    else:
                        current_month += 1
                    continue

            logger.info(f"Processing month: {month_str}")

            # attempt to fetch the Carbon Data from API. if there is no carbon data for that month, the API
            #  will return an empty "value" array
            success, emissions_data, error_message = make_carbon_api_request_batched(
                headers, subscription_ids, month_str
            )

            if success:
                if success and len(emissions_data["value"]) == 0:
                    # Create empty carbon data for months outside API range
                    emissions_data = empty_emissions_data(month_str)

                save_carbon_data_to_s3(emissions_data, file_name, force_overwrite=force_overwrite)
                processed_months += 1
            else:
                logger.error(error_message)
                if write_empty_object:
                    logger.warning(f"Unable to process month: {month_str}. Writing empty results")
                    emissions_data = empty_emissions_data(month_str)
                    save_carbon_data_to_s3(emissions_data, file_name, force_overwrite=force_overwrite)
                    processed_months += 1
                else:
                    logger.error(f"Unable to process month: {month_str}. Not writing empty results")
                    skipped_months += 1

            # Move to next month
            if current_month == 12:
                current_year += 1
                current_month = 1
            else:
                current_month += 1

        # gets this far if having processed all carbon export backfill
        carbon_export_backfill_lock_create()

        return (
            processed_months,
            skipped_months,
        )

    except Exception as e:
        error_msg = f"Error in carbon emissions backfill impl: {str(e)}"
        raise Exception(error_msg)
