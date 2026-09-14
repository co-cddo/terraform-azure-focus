import json
import logging
import os

from pyarrow.fs import S3FileSystem
from common import (
    Config,
)
from api.tokens import (
    TokenManager,
)
logger = logging.getLogger("cost_export")
logger.setLevel(os.environ.get('LOGGING_LEVEL', 'INFO'))

def getS3FileSystem():
  credentials = TokenManager().aws_identity

  aws_access_key_id = credentials['aws_access_key_id']
  aws_secret_access_key = credentials['aws_secret_access_key']
  aws_session_token = credentials['aws_session_token']

  return S3FileSystem(
      access_key=aws_access_key_id,
      secret_key=aws_secret_access_key,
      session_token=aws_session_token,
      region=Config.aws_region
  )

def upsert_module_manifest() -> None:
    manifest = {
        "module_source": Config.module_source,
        "module_version": Config.module_version,
        "configuration": {
            "backfill_start_date": Config.backfill_start_date,
            "enable_focus_exports": Config.enable_focus_exports,
            "enable_carbon_exports": Config.enable_carbon_exports,
            "enable_advisor_exports": Config.enable_advisor_exports,
        }
    }
    json_data = json.dumps(manifest, indent=2).encode("utf-8")
    s3 = getS3FileSystem()
    s3_path = f"{Config.s3_focus_path.rstrip('/')}/manifest.json"
    with s3.open_output_stream(s3_path) as f:
        f.write(json_data)
    logger.info(f"Module manifest upserted to {s3_path}")
