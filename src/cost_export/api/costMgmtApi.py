import logging
logger = logging.getLogger("cost_export")

import requests
from azure.identity import ManagedIdentityCredential


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


def cost_mgmt_export_exists(account_idx: int, account_id: str, month: int, year: int, timeout=60) -> bool:
###
# GET https://management.azure.com/providers/Microsoft.Billing/billingAccounts/bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31/providers/Microsoft.CostManagement/exports/focus-backfill-0-2025-10?api-version=2025-03-01
###
  export_task_name = get_export_task_name(account_idx, month, year)
  logger.debug(f"cost_mgmt_export_exists: {export_task_name}")

  url = get_mgmt_export_task_url(account_idx, account_id, month, year)
  logger.info(f"cost_mgmt_export_exists: GET {url}")

  try:
    # Get access token using managed identity
    credential = ManagedIdentityCredential()
    token = credential.get_token("https://management.azure.com/.default")
    
    # Prepare the API request
    headers = {
      "Authorization": f"Bearer {token.token}",
      "Content-Type": "application/json"
    }
    response = requests.get(
        url,
        headers=headers,
        timeout=timeout
    )
    
    if response.status_code == 200:
      logger.info(f"WA DEBUG - the response: {str(response)}")
      return True

    else:
      error_msg = f"API request failed with status {response.status_code}: {response.text}"
      # Check if it's a date range error
      if response.status_code == 400 and "InvalidRequestPropertyValue" in response.text:
          if "should be in available range" in response.text:
              error_msg += " - Date is outside the available range for Carbon Optimization API"
      elif response.status_code == 400 and "InvalidNumberOfSubscriptions" in response.text:
          error_msg += " - Too many subscriptions in request (max 100 allowed)"
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

def cost_mgmt_export_create(account_idx: int, account_id: str, month: int, year: int) -> None:
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
#           "configuration": {
#             "dataVersion": "1.0r2"
#           },
#           "granularity": "Daily"
#         },
#         "timeframe": "Custom",
#         "timePeriod": {
#           "from": "2025-10-01T00:00:00Z",
#           "to": "2025-10-31T23:59:59Z"
#         }
#       },
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
###  export_task_name = get_export_task_name(account_idx, month, year)
  logger.debug(f"cost_mgmt_export_create: export_task_name ({export_task_name})")

  url = get_mgmt_export_task_url(account_idx, account_id, month, year)
  logger.info(f"cost_mgmt_export_exists: PUT {url}")

def cost_mgmt_export_run(account_idx: int, account_id: str, month: int, year: int) -> bool:
###
# POST https://management.azure.com/providers/Microsoft.Billing/billingAccounts/bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31/providers/Microsoft.CostManagement/exports/focus-backfill-0-2025-10?api-version=2025-03-01
# >>>> no body required
###
  export_task_name = get_export_task_name(account_idx, month, year)
  logger.debug(f"cost_mgmt_export_run: {export_task_name}")

  url = get_mgmt_export_task_url(account_idx, account_id, month, year)
  logger.info(f"cost_mgmt_export_exists: POST {url}")

  return True
