'''
To run locally, first export the following env vars to shell:
export AZURE_TOKEN=$(az account get-access-token --query accessToken --output tsv)

Get the following from AWS Identity Centre
export AWS_ACCESS_KEY_ID="...."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."

Create a python virtual environment.
Activate it.
Install python packages into virtual environment: `python -m pip install -r ./src/cost_export/requirements.txt`

And to run:
```
ENTRA_APP_CLIENT_ID="a103d73e-xxxx-xxxx-xxxx-aabbccddeeff" ENTRA_APP_URN="api://7a770e35-xxxx-xxxx-xxxx-aabbccddeeff/GDS-AWS-Cost-Forwarding" AWS_ROLE_ARN="arn:aws:iam::123456:role/AzureFederated-7a770e35-xxxx-xxxx-xxxx-aabbccddeeff" S3_FOCUS_PATH="uk-gov-appvia-cost-inbound/7a770e35-xxx-xxxx-xxxx-aabbccddeeff" AWS_REGION="eu-west-2" STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=stcostexportabc1234;AccountKey=IkC+bob4675+3784/base64==;EndpointSuffix=core.windows.net" CONTAINER_NAME="cost-exports" S3_UTILIZATION_PATH="uk-gov-appvia-cost-inbound/7a770e35-xxx-xxxx-xxxx-aabbccddeeff" S3_RECOMMENDATIONS_PATH="uk-gov-appvia-cost-inbound/7a770e35-xxx-xxxx-xxxx-aabbccddeeff" S3_CARBON_PATH="uk-gov-appvia-cost-inbound/7a770e35-xxx-xxxx-xxxx-aabbccddeeff" CARBON_DIRECTORY_NAME="gds-carbon-v1" CARBON_API_TENANT_ID="7a770e35-xxx-xxxx-xxxx-aabbccddeeff" BILLING_SCOPE="/providers/Microsoft.Management/managementGroups/7a770e35-xxx-xxxx-xxxx-aabbccddeeff" BILLING_ACCOUNT_MAPPING='{"0":"bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31"}' ROOT_FOLDER_PATH="gds-focus-v1"  STORAGE_RESOURCE_ID="/subscriptions/c365d2c4-xxxx-xxxx-xxxx-aabbccddeeff/resourceGroups/rg-cost-export/providers/Microsoft.Storage/storageAccounts/stcostexportabc123" STORAGE_CONTAINER="cost-exports" BILLING_AZURE_LOCATION="uksouth" BACKFILL_START_DATE="2025-10-01"   python3 ./src/cost_export/runBackfillLocal.py
```

You will get the value of all the env vars from the deployed function config in Azure web console.
Be sure to set the backfill "BACKFILL_START_DATE" o something sensible.
'''

import logging
logger = logging.getLogger("cost_export")
logger.setLevel(logging.INFO)

import os
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
  cost_export_exists_as_lock_object,
  cost_export_exists_lock_create,
)

try:
    backfill_trigger(timer=None)

    # export_exists = cost_mgmt_export_exists(account_idx=0, account_id="bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31", month=10, year=2025)
    # logger.warning(f"WA DEBUG - the cost export (10/2025) exists: {export_exists}")
    # export_created = cost_mgmt_export_create(account_idx=0, account_id="bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31", month=2, year=2025)
    # logger.warning(f"WA DEBUG - the cost export (02/2025) create: {export_created}")
    # export_created = cost_mgmt_export_run(account_idx=0, account_id="bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31", month=2, year=2025)
    # logger.warning(f"WA DEBUG - the cost export (02/2025) run: {export_created}")

    # if cost_export_backfill_schedule_lock_exists():
    #     logger.warning("WA DEBUG - the cost export backfill schedule lock exists")
    # else:
    #     logger.warning("WA DEBUG - the cost export backfill schedule lock NOT exists")
except Exception as e:
    logger.error(f"Unexpected error: {str(e)}")
    raise e
