import logging
import os
logger = logging.getLogger("cost_export")
logger.setLevel(os.environ.get('LOGGING_LEVEL', 'INFO'))

from datetime import datetime, timezone
import pyarrow.fs as fs
from common import (
   Config,
)
from api.s3Api import getS3FileSystem

CARBON_EXPORT_BACKFILL_RUN_LOCK_NAME = "carbon-backfill-run.lock"

def carbon_export_backfill_lock_exists() -> bool:
  try:
    logger.debug(f"carbon_export_backfill_lock_exists: s3_focus_path({Config.s3_focus_path}), carbon_directory_name ({Config.carbon_directory_name}), CARBON_EXPORT_BACKFILL_RUN_LOCK_NAME({CARBON_EXPORT_BACKFILL_RUN_LOCK_NAME})")

    s3 = getS3FileSystem()
    s3_path = f"{Config.s3_focus_path.rstrip('/')}/{Config.carbon_directory_name}-{CARBON_EXPORT_BACKFILL_RUN_LOCK_NAME}"
    logger.debug(f"Carbon Export lock check: {s3_path}")
    
    file_info = s3.get_file_info(s3_path)
    exists = file_info.type != fs.FileType.NotFound
    
    if not exists:
      logger.info(f"Carbon Export lock does not exists: {s3_path}")
    
    return exists
        
  except Exception as e:
    # throws exception with ACCESS_DENIED if object does not exist
    #  and this despite the documentation!!! https://arrow.apache.org/docs/python/generated/pyarrow.fs.S3FileSystem.html#pyarrow.fs.S3FileSystem.get_file_info
    exceptionStr = str(e)
    if "ACCESS_DENIED" in exceptionStr:
      logger.info(f"Carbon Export lock does not exists: {s3_path}")
      return False

    logger.warning(f"Failed to check for Carbon Export lock file: {exceptionStr}. Assuming it exists...")

    # If we can't check, assume it exists to not unnecessary run through backfill
    return True

def carbon_export_backfill_lock_create() -> None:
  try:
    logger.debug(f"carbon_export_backfill_lock_create: s3_focus_path({Config.s3_focus_path}), carbon_directory_name ({Config.carbon_directory_name}), CARBON_EXPORT_BACKFILL_RUN_LOCK_NAME({CARBON_EXPORT_BACKFILL_RUN_LOCK_NAME})")

    s3 = getS3FileSystem()
    s3_path = f"{Config.s3_focus_path.rstrip('/')}/{Config.carbon_directory_name}-{CARBON_EXPORT_BACKFILL_RUN_LOCK_NAME}"
    logger.debug(f"cost_export_backfill_schedule_lock_create path: {s3_path}")

    today = datetime.now(timezone.utc)
    todayStr = datetime.strftime(today, "%Y-%m-%d %H:%M:%S")

    with s3.open_output_stream(s3_path) as f:
      f.write(str(todayStr).encode('utf-8'))
      f.close()

    logger.info("cost export backfill schedule lock created")
    
  except Exception as e:
    logger.error(f"Failed to create cost export backfill run lock: {str(e)}")
    raise e

def carbon_export_exists(month: int, year:int) -> bool:
  ###
  # s3://uk-gov-appvia-cost-inbound/7a770e35-b455-4df2-a276-b07408438d9a/gds-carbon-v1/billing_period=20240201/carbon-emissions-2024-02.json
  ###
  try:
    logger.debug(f"carbon_export_exists: s3_focus_path({Config.s3_focus_path}), carbon_directory_name ({Config.carbon_directory_name}), CARBON_EXPORT_BACKFILL_RUN_LOCK_NAME({CARBON_EXPORT_BACKFILL_RUN_LOCK_NAME}), month({month}), year({year})")

    s3 = getS3FileSystem()

    # the cost export can be one or more objects in a given month/year path

    s3_path = f"{Config.s3_focus_path.rstrip('/')}/{Config.carbon_directory_name}/billing_period={year:04d}{month:02d}01/carbon-emissions-{year:04d}{month:02d}.json"
    logger.info(f"Carbon Export data check: {s3_path}")
    
    file_info = s3.get_file_info(s3_path)
    exists = file_info.type != fs.FileType.NotFound

    if not exists:
      logger.info(f"Carbon Export data does not exists: {s3_path}")

    return exists

  except Exception as e:
    logger.error(e)
    # throws exception with ACCESS_DENIED if object path does not exist
    #  and this despite the documentation!!! https://arrow.apache.org/docs/python/generated/pyarrow.fs.S3FileSystem.html#pyarrow.fs.S3FileSystem.get_file_info
    exceptionStr = str(e)
    if "ACCESS_DENIED" in exceptionStr:
      logger.info(f"Carbon Export data does not exists: {s3_path}")
      return False
  
    logger.warning(f"Failed to check for carbon export data exists: {str(e)}\n\\nAssuming it exists...")
    # If we can't check, assume it does not exist to force generating it
    return False

  try:
    s3 = getS3FileSystem()
    s3_path = f"{Config.s3_focus_path.rstrip('/')}/{Config.carbon_directory_name}/billing_period={year:04d}{month:02d}01/{account_id}.lock"
    logger.debug(f"cost_export_exists_lock_create path: {s3_path}")

    today = datetime.now(timezone.utc)
    todayStr = datetime.strftime(today, "%Y-%m-%d %H:%M:%S")

    with s3.open_output_stream(s3_path) as f:
      f.write(str(todayStr).encode('utf-8'))
      f.close()

    logger.info(f"cost export backfill data lock created for {month}/{year} on account '{account_id}'")
    
  except Exception as e:
    logger.error(f"Failed to create cost export backfill data lock: {str(e)}")
    raise e