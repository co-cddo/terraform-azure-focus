import logging
import os
logger = logging.getLogger("cost_export")
logger.setLevel(os.environ.get('LOGGING_LEVEL', 'INFO'))

import requests
from datetime import datetime, timedelta

from common import Config
from api.tokens import TokenManager

COST_MGMT_EXPORT_BACKFILL_JOB_PREFIX: str = "focus-backfill"

def get_export_task_name(account_idx: int, month: int, year: int) -> str:
  try:
    export_task_name = "%s-%d-%04d-%02d" % (COST_MGMT_EXPORT_BACKFILL_JOB_PREFIX, account_idx, year, month)
    return export_task_name
  except Exception as e:
    logger.error(f"get_export_task_name: error: {e}")
    return None

def get_mgmt_base_url(account_id: str) -> str:
  return "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/%s/providers/Microsoft.CostManagement/exports" % (account_id)

def get_mgmt_export_task_url(account_idx: int, account_id: str, month: int, year: int) -> str:
  return "%s/%s?api-version=2025-03-01" % (get_mgmt_base_url(account_id), get_export_task_name(account_idx, month, year))

# slighly different URL to run a task (requires "/run" on the URL endpoint)
def get_mgmt_export_run_task_url(account_idx: int, account_id: str, month: int, year: int) -> str:
  return "%s/%s/run?api-version=2025-03-01" % (get_mgmt_base_url(account_id), get_export_task_name(account_idx, month, year))

def cost_mgmt_export_exists(account_idx: int, account_id: str, month: int, year: int, timeout=30) -> bool:
###
# GET https://management.azure.com/providers/Microsoft.Billing/billingAccounts/bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31/providers/Microsoft.CostManagement/exports/focus-backfill-0-2025-10?api-version=2025-03-01
###
  export_task_name = get_export_task_name(account_idx, month, year)
  logger.debug(f"cost_mgmt_export_exists: {export_task_name}")

  url = get_mgmt_export_task_url(account_idx, account_id, month, year)
  logger.debug(f"cost_mgmt_export_exists: GET {url}")

  try:
    token = TokenManager().azure_token
    logger.debug(f"cost_mgmt_export_exists: token: {token}")
    
    # Prepare the API request
    headers = {
      "Authorization": f"Bearer {token}",
    }
    response = requests.get(
        url,
        headers=headers,
        timeout=timeout
    )
    
    ### NOT FOUND
    if response.status_code == 404:
      return False

    # FOUND    
    elif response.status_code == 200:
      return True

    else:
      error_msg = f"cost_mgmt_export_exists (account idx[{account_idx}], account[{account_id}], month[{month}], year[{year}]) API request failed with status {response.status_code}: {response.text}"
      logger.error(error_msg)
      return False
            
  except requests.exceptions.Timeout:
    logger.error(f"cost_mgmt_export_exists timeout: {str(e)}")
    return False
  except requests.exceptions.RequestException as e:
    logger.error(f"cost_mgmt_export_exists request: {str(e)}")
    return False
  except Exception as e:
    logger.error(f"cost_mgmt_export_exists unexpected: {str(e)}")
    return False

def get_last_day_month_date(month: int, year: int) -> int:
  # import calendar
  # last_day = calendar.monthrange(year, month)[1]
  # return "%04d-%02d-%02d" % (year, month, last_day)

  # first increment the month by one
  month += 1
  if (month > 12):
    month = 1
    year += 1

  # using the datetime for the 1st of the next month, subtract one second
  end_of_month = datetime(year, month, 1) - timedelta(seconds=1)

  return end_of_month.day

def cost_mgmt_export_create(account_idx: int, account_id: str, month: int, year: int, timeout=120) -> None:
### Example payload to PUT https://management.azure.com/providers/Microsoft.Billing/billingAccounts/bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31/providers/Microsoft.CostManagement/exports/focus-backfill-0-2025-10?api-version=2025-03-01
# {
#   "location": "uksouth",
#   "identity": {
#     "type": "SystemAssigned"
#   },
# 	"properties": {
# 		"exportDescription": "Focus Backfill Cost Export for 2025-10 on warren's scope",
# 		"definition": {
# 			"type": "FocusCost",
#       "dataSet": {
#         "configuration": {
#           "dataVersion": "1.0r2"
#         },
#         "granularity": "Daily"
#       },
# 			"timeframe": "Custom",
# 			"timePeriod": {
# 				"from": "2025-10-01T00:00:00Z",
# 				"to": "2025-10-31T23:59:59Z"
# 			}
# 		},
# 		"schedule": {
# 			"status": "Inactive"
# 		},
# 		"format": "Parquet",
# 		"deliveryInfo": {
# 			"destination": {
# 				"type": "AzureBlob",
# 				"resourceId": "/subscriptions/c365d2c4-3c56-44c1-a979-94478d5acb7c/resourceGroups/rg-cost-export/providers/Microsoft.Storage/storageAccounts/stcostexportp2h9yi0z",
# 				"container" : "cost-exports",
# 				"rootFolderPath" : "gds-focus-v1"
# 			}
# 		},
# 		"partitionData": "true",
# 		"dataOverwriteBehavior": "OverwritePreviousReport",
# 		"compressionMode": "None"
# 	}
# }
  logger.info(f"...creating cost export task for account id ({account_id} on {month:02d}/{year:04d}...")

  export_task_name = get_export_task_name(account_idx, month, year)
  logger.debug(f"cost_mgmt_export_create: export_task_name ({export_task_name})")

  url = get_mgmt_export_task_url(account_idx, account_id, month, year)
  logger.info(f"cost_mgmt_export_exists: PUT {url}")

  payload_resource_id = f"{Config.cost_mgmt_export_destination_id}"
  payload_container = f"{Config.cost_mgmt_export_container}"
  payload_folder_path = f"{Config.s3_cost_directory_name}"
  payload_location = f"{Config.billing_azure_location}"

  month_last_day = get_last_day_month_date(month, year)

  payload = {
    "location": payload_location,
    "identity": {
      "type": "SystemAssigned"
    },
    "properties": {
      "definition": {
        "type": "FocusCost",
        "dataSet": {
          "configuration": {
            "dataVersion": "1.0r2"
          },
          "granularity": "Daily"
        },
        "timeframe": "Custom",
        "timePeriod": {
          "from": f"{year:04d}-{month:02d}-01T00:00:00Z",
          "to": f"{year:04d}-{month:02d}-{month_last_day:02d}T23:59:59Z"
        }
      },
      "schedule": {
        "status": "Inactive"
      },
      "format": "Parquet",
      "deliveryInfo": {
        "destination": {
          "type": "AzureBlob",
          "resourceId": payload_resource_id,
          "container" : payload_container,
          "rootFolderPath" : payload_folder_path
        }
      },
      "partitionData": "true",
      "dataOverwriteBehavior": "OverwritePreviousReport",
      "compressionMode": "None"
    }
  }
  logger.debug(f"....PUT export payload: {payload}")

  try:
    token = TokenManager().azure_token
    logger.debug(f"cost_mgmt_export_exists: token: {token}")
  
    # Prepare the API request
    headers = {
      "Authorization": f"Bearer {token}",
      "Content-Type": "application/json"
    }
    response = requests.put(
        url,
        json=payload,
        headers=headers,
        timeout=timeout
    )

    # Can "PUT" the same export object multiple times - 201 on first create, then 200
    if response.status_code == 201 or response.status_code == 200:
      return True

    else:
      error_msg = f"cost_mgmt_export_create (account idx[{account_idx}], account[{account_id}], month[{month}], year[{year}]) API request failed with status {response.status_code}: {response.text}"
      logger.error(error_msg)
      return False
            
  except requests.exceptions.Timeout:
    logger.error(f"cost_mgmt_export_create timeout: {str(e)}")
    return False
  except requests.exceptions.RequestException as e:
    logger.error(f"cost_mgmt_export_create request: {str(e)}")
    return False
  except Exception as e:
    logger.error(f"cost_mgmt_export_create unexpected: {str(e)}")
    return False

def cost_mgmt_export_run(account_idx: int, account_id: str, month: int, year: int, timeout=30) -> bool:
###
# POST https://management.azure.com/providers/Microsoft.Billing/billingAccounts/bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31/providers/Microsoft.CostManagement/exports/focus-backfill-0-2025-10?api-version=2025-03-01
# >>>> no body required
###
  logger.info(f"...running cost export for account id ({account_id} on {month:02d}/{year:04d}...")

  export_task_name = get_export_task_name(account_idx, month, year)
  logger.debug(f"cost_mgmt_export_run: {export_task_name}")

  url = get_mgmt_export_run_task_url(account_idx, account_id, month, year)
  logger.debug(f"cost_mgmt_export_run: GET {url}")

  try:
    token = TokenManager().azure_token
    
    # Prepare the API request
    headers = {
      "Authorization": f"Bearer {token}",
      "Content-Type": "application/json"
    }
    response = requests.post(
        url,
        headers=headers,
        timeout=timeout
    )
    
    ### NOT FOUND
    if response.status_code == 404:
      return False

    # FOUND    
    elif response.status_code == 200:
      return True

    else:
      error_msg = f"cost_mgmt_export_run (account idx[{account_idx}], account[{account_id}], month[{month}], year[{year}]) API request failed with status {response.status_code}: {response.text}"
      logger.error(error_msg)
      return False
            
  except requests.exceptions.Timeout:
    logger.error(f"cost_mgmt_export_run timeout: {str(e)}")
    return False
  except requests.exceptions.RequestException as e:
    logger.error(f"cost_mgmt_export_run request: {str(e)}")
    return False
  except Exception as e:
    logger.error(f"cost_mgmt_export_run unexpected: {str(e)}")
    return False
