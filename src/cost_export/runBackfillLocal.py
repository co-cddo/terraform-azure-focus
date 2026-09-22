'''
Python dependencies are pre-installed in the dev container's .venv.

To run locally, first activate the virtual environment:
source .venv/bin/activate

Then export the following env vars to shell:
export AZURE_TOKEN=$(az account get-access-token --query accessToken --output tsv)

Get the following from AWS Identity Centre:
export AWS_ACCESS_KEY_ID="...."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

Then run:
```
ENTRA_APP_CLIENT_ID="a103d73e-xxxx-xxxx-xxxx-aabbccddeeff" ENTRA_APP_URN="api://7a770e35-xxxx-xxxx-xxxx-aabbccddeeff/GDS-AWS-Cost-Forwarding" AWS_ROLE_ARN="arn:aws:iam::123456:role/AzureFederated-7a770e35-xxxx-xxxx-xxxx-aabbccddeeff" S3_FOCUS_PATH="uk-gov-appvia-cost-inbound/7a770e35-xxx-xxxx-xxxx-aabbccddeeff" AWS_REGION="eu-west-2" STORAGE_ACCOUNT_BLOB_ENDPOINT="https://stcostexportabc1234.blob.core.windows.net/" CONTAINER_NAME="cost-exports" S3_UTILIZATION_PATH="uk-gov-appvia-cost-inbound/7a770e35-xxx-xxxx-xxxx-aabbccddeeff" S3_RECOMMENDATIONS_PATH="uk-gov-appvia-cost-inbound/7a770e35-xxx-xxxx-xxxx-aabbccddeeff" S3_CARBON_PATH="uk-gov-appvia-cost-inbound/7a770e35-xxx-xxxx-xxxx-aabbccddeeff" CARBON_DIRECTORY_NAME="gds-carbon-v1" CARBON_API_TENANT_ID="7a770e35-xxx-xxxx-xxxx-aabbccddeeff" BILLING_SCOPE="/providers/Microsoft.Management/managementGroups/7a770e35-xxx-xxxx-xxxx-aabbccddeeff" BILLING_ACCOUNT_MAPPING='{"0":"a1b2c3d4-e5f6-7890-a1b2-c3d4e5f6a7b8:f9e8d7c6-b5a4-3210-fedc-ba9876543210_2019-05-31"}' ROOT_FOLDER_PATH="gds-focus-v1"  STORAGE_RESOURCE_ID="/subscriptions/c365d2c4-xxxx-xxxx-xxxx-aabbccddeeff/resourceGroups/rg-cost-export/providers/Microsoft.Storage/storageAccounts/stcostexportabc123" STORAGE_CONTAINER="cost-exports" BILLING_AZURE_LOCATION="uksouth" BACKFILL_START_DATE="2025-10-01"  LOGGING_LEVEL="DEBUG" python3 ./src/cost_export/runBackfillLocal.py
```

You will get the value of all the env vars from the deployed function config in Azure web console.
Be sure to set the backfill "BACKFILL_START_DATE" o something sensible.
LOG_LEVEL env var defaults to "DEBUG" above but can be noisy; set to "INFO" if required.
'''

import logging
import os
logger = logging.getLogger("cost_export")
logger.setLevel(os.environ.get('LOGGING_LEVEL', 'INFO'))

from function_app import (
    backfill_trigger,
)

from api.costMgmtApi import (
    cost_mgmt_export_create,
    cost_mgmt_export_exists,
    cost_mgmt_export_run,
)


from api.costMgmtApi import (
    cost_mgmt_export_create,
    cost_mgmt_export_exists,
    cost_mgmt_export_run,
)

from api.costMgmtS3Api import (
  cost_export_backfill_schedule_lock_exists,
  cost_export_backfill_run_lock_exists,
  cost_export_backfill_schedule_lock_create,
  cost_export_backfill_run_lock_create,
  cost_export_exists,
)

try:
    backfill_trigger(timer=None)

    # export_exists = cost_mgmt_export_exists(account_idx=0, account_id="a1b2c3d4-e5f6-7890-a1b2-c3d4e5f6a7b8:f9e8d7c6-b5a4-3210-fedc-ba9876543210_2019-05-31", month=10, year=2025)
    # logger.warning(f"WA DEBUG - the cost export (10/2025) exists: {export_exists}")
    # export_created = cost_mgmt_export_create(account_idx=0, account_id="a1b2c3d4-e5f6-7890-a1b2-c3d4e5f6a7b8:f9e8d7c6-b5a4-3210-fedc-ba9876543210_2019-05-31", month=2, year=2025)
    # logger.warning(f"WA DEBUG - the cost export (02/2025) create: {export_created}")
    # export_created = cost_mgmt_export_run(account_idx=0, account_id="a1b2c3d4-e5f6-7890-a1b2-c3d4e5f6a7b8:f9e8d7c6-b5a4-3210-fedc-ba9876543210_2019-05-31", month=2, year=2025)
    # logger.warning(f"WA DEBUG - the cost export (02/2025) run: {export_created}")

    # if cost_export_backfill_schedule_lock_exists():
    #     logger.warning("WA DEBUG - the cost export backfill schedule lock exists")
    # else:
    #     logger.warning("WA DEBUG - the cost export backfill schedule lock NOT exists")
except Exception as e:
    logger.error(f"Unexpected error: {str(e)}", exc_info=True)
    raise e
