import logging
import json
logger = logging.getLogger("cost_export")

from datetime import datetime, timezone
import pyarrow.fs as fs
from common import (
   Config,
)
from api.s3Api import getS3FileSystem

COST_EXPORT_BACKFILL_RUN_LOCK_NAME = "cost-backfill-run.lock"
COST_EXPORT_BACKFILL_SCHEDULE_LOCK_NAME = "cost-backfill-schedule.lock"

def cost_export_backfill_schedule_lock_exists() -> bool:
  try:
    s3 = getS3FileSystem()
    s3_path = f"{Config.s3_focus_path.rstrip('/')}/{Config.s3_cost_directory_name}-{COST_EXPORT_BACKFILL_SCHEDULE_LOCK_NAME}"
    logger.debug(f"Cost Export schedule lock check: {s3_path}")
    
    file_info = s3.get_file_info(s3_path)
    exists = file_info.type != fs.FileType.NotFound
    
    if not exists:
      logger.info(f"Cost Export schedule lock does not exists: {s3_path}")
    
    return exists
        
  except Exception as e:
    # throws exception with ACCESS_DENIED if object does not exist
    #  and this despite the documentation!!! https://arrow.apache.org/docs/python/generated/pyarrow.fs.S3FileSystem.html#pyarrow.fs.S3FileSystem.get_file_info
    exceptionStr = str(e)
    if "ACCESS_DENIED" in exceptionStr:
      logger.info(f"Cost Export schedule lock does not exists: {s3_path}")
      return False

    logger.warning(f"Failed to check for cost export schedule lock file: {exceptionStr}. Assuming it exists...")

    # If we can't check, assume it exists to not unnecessary run through backfill
    return True

def cost_export_backfill_run_lock_exists() -> bool:
  try:
    s3 = getS3FileSystem()
    s3_path = f"{Config.s3_focus_path.rstrip('/')}/{Config.s3_cost_directory_name}-{COST_EXPORT_BACKFILL_RUN_LOCK_NAME}"
    logger.debug(f"Cost Export schedule lock check: {s3_path}")
    
    file_info = s3.get_file_info(s3_path)
    exists = file_info.type != fs.FileType.NotFound
    
    if not exists:
      logger.info(f"Cost Export run lock does not exists: {s3_path}")
    
    return exists
        
  except Exception as e:
    # throws exception with ACCESS_DENIED if object does not exist
    #  and this despite the documentation!!! https://arrow.apache.org/docs/python/generated/pyarrow.fs.S3FileSystem.html#pyarrow.fs.S3FileSystem.get_file_info
    exceptionStr = str(e)
    if "ACCESS_DENIED" in exceptionStr:
      logger.info(f"Cost Export run lock does not exists: {s3_path}")
      return False

    logger.warning(f"Failed to check for cost export run lock file: {exceptionStr}. Assuming it exists...")

    # If we can't check, assume it exists to not unnecessary run through backfill
    return True

def cost_export_backfill_schedule_lock_create() -> None:
  try:
    s3 = getS3FileSystem()
    s3_path = f"{Config.s3_focus_path.rstrip('/')}/{Config.s3_cost_directory_name}-{COST_EXPORT_BACKFILL_SCHEDULE_LOCK_NAME}"
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

def cost_export_backfill_run_lock_create() -> None:
  try:
    s3 = getS3FileSystem()
    s3_path = f"{Config.s3_focus_path.rstrip('/')}/{Config.s3_cost_directory_name}-{COST_EXPORT_BACKFILL_RUN_LOCK_NAME}"
    logger.debug(f"cost_export_backfill_run_lock_create path: {s3_path}")

    today = datetime.now(timezone.utc)
    todayStr = datetime.strftime(today, "%Y-%m-%d %H:%M:%S")
    with s3.open_output_stream(s3_path) as f:
      f.write(str(todayStr).encode('utf-8'))
      f.close()

    logger.info("cost export backfill run lock created")
    
  except Exception as e:
    logger.error(f"Failed to create cost export backfill run lock: {str(e)}")
    raise e

def cost_export_exists(account_id:str, month: int, year:int) -> bool:
  ###
  # bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d-16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31_OC35-AR3W-BG7-PGB_part_0_0001.parquet
  # bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d-16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31_part_1_0001.parquet
  ###
  try:
    s3 = getS3FileSystem()

    # the cost export can be one or more objects in a given month/year path

    # the object name will always start with the account id (the string), but replacing the ":" with a "-"
    object_account_id = account_id.replace(":", "-")

    # tried using a wildcard on the account id - but fails with "pyarrow.fs"
    # s3_path = f"{Config.s3_focus_path.rstrip('/')}/{Config.s3_cost_directory_name}/billing_period={year:04d}{month:02d}01/{object_account_id}*"

    # so fetching with the dated billing path - to get a list of objects with that path
    # that didn't work either. So creating an explicit "selector", allow not found to return empty list and recursing through folder
    s3_path = f"{Config.s3_focus_path.rstrip('/')}/{Config.s3_cost_directory_name}/billing_period={year:04d}{month:02d}01"
    logger.info(f"Cost Export data check: {s3_path}")
    
    selector = fs.FileSelector(base_dir=s3_path, allow_not_found=True, recursive=True)
    objects = s3.get_file_info(selector)
    logger.warning(f"cost_export_exists: objects: {objects}")

    # expected to return a list of file_info - https://arrow.apache.org/docs/python/generated/pyarrow.fs.S3FileSystem.html#pyarrow.fs.S3FileSystem.get_file_info
    #  can be an empty list
    if len(objects) == 0:
      logger.info(f"Cost Export data does exist - path returned no objects: {s3_path}")
      return False
    else:
      # TODO - modify the logic below to filter by account_id assuming exist starts as False and then set to True
      assume_exists = True
      for thisObject in objects:
        logger.warning(f"WA DEBUG - thisObject: {thisObject}")
        if thisObject.type != fs.FileType.NotFound:
          assume_exists = False
    
      if assume_exists:
        logger.info(f"Cost Export data does exist: {s3_path}")
      else:
        logger.info(f"Cost Export data does not exist: {s3_path}")
    
      return assume_exists

  except Exception as e:
    logger.error(e)
    # throws exception with ACCESS_DENIED if object path does not exist
    #  and this despite the documentation!!! https://arrow.apache.org/docs/python/generated/pyarrow.fs.S3FileSystem.html#pyarrow.fs.S3FileSystem.get_file_info
    exceptionStr = str(e)
    if "ACCESS_DENIED" in exceptionStr:
      logger.info(f"Cost Export data does not exists: {s3_path}")
      return False
  
    logger.warning(f"Failed to check for cost export data exists: {str(e)}\n\\nAssuming it exists...")
    # If we can't check, assume it does not exist to force generating it
    return False
  
def cost_export_exists_as_lock_object(account_id:str, month: int, year:int) -> bool:
  ###
  # The assume role in AWS does not allow ListBucket action on the gds focus paths.
  # Until that can be fixed, adding a horrible lock file approach
  ###
  try:
    s3 = getS3FileSystem()
    s3_path = f"{Config.s3_focus_path.rstrip('/')}/{Config.s3_cost_directory_name}/billing_period={year:04d}{month:02d}01/{account_id}.lock"
    logger.debug(f"Cost Export data lock check: {s3_path}")
    
    file_info = s3.get_file_info(s3_path)
    exists = file_info.type != fs.FileType.NotFound
    
    if not exists:
      logger.info(f"Cost Export data lock does not exists: {s3_path}")
    
    return exists
        
  except Exception as e:
    # throws exception with ACCESS_DENIED if object does not exist
    #  and this despite the documentation!!! https://arrow.apache.org/docs/python/generated/pyarrow.fs.S3FileSystem.html#pyarrow.fs.S3FileSystem.get_file_info
    exceptionStr = str(e)
    if "ACCESS_DENIED" in exceptionStr:
      logger.info(f"Cost Export data lock does not exists: {s3_path}")
      return False

    logger.warning(f"Failed to check for cost export data lock file: {exceptionStr}. Assuming it exists...")

    # If we can't check, assume it exists to not unnecessary run through backfill
    return True

def cost_export_exists_lock_create(account_id:str, month: int, year:int) -> None:
  try:
    s3 = getS3FileSystem()
    s3_path = f"{Config.s3_focus_path.rstrip('/')}/{Config.s3_cost_directory_name}/billing_period={year:04d}{month:02d}01/{account_id}.lock"
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