import logging
logger = logging.getLogger("cost_export")

COST_EXPORT_BACKFILL_RUN_LOCK_NAME = "cost-backfill-run-lock"
COST_EXPORT_BACKFILL_SCHEDULE_LOCK_NAME = "cost-backfill-schedule-lock"

def cost_export_backfill_schedule_lock_exists() -> bool:
  # try:
  #   # Get S3 filesystem
  #   s3 = getS3FileSystem()

  #   # the cost export can be one of more objects in a given path
  #   # the specific name of the export can not be predicted

  #   # the best way to know if the export exists or not is to check
  #   # for the "path" (directory) not the actual objects.
  #   s3_path = f"{Config.s3_carbon_path.rstrip('/')}/{Config.carbon_directory_name}/billing_period={billing_period}/{file_name}"
    
  #   # Check if file exists
  #   file_info = s3.get_file_info(s3_path)
  #   exists = file_info.type != fs.FileType.NotFound
    
  #   if exists:
  #       logger.info(f"Carbon data file already exists: {s3_path}")
    
  #   return exists
        
  # except Exception as e:
  #     logger.warning(f"Could not find existing file named '{file_name}': {str(e)} assuming it doesn't exist...")
  #     # If we can't check, assume it doesn't exist to be safe
  #     return False
  return False

def cost_export_backfill_run_lock_exists() -> bool:
  # try:
  #   # Get S3 filesystem
  #   s3 = getS3FileSystem()

  #   # the cost export can be one of more objects in a given path
  #   # the specific name of the export can not be predicted

  #   # the best way to know if the export exists or not is to check
  #   # for the "path" (directory) not the actual objects.
  #   s3_path = f"{Config.s3_carbon_path.rstrip('/')}/{Config.carbon_directory_name}/billing_period={billing_period}/{file_name}"
    
  #   # Check if file exists
  #   file_info = s3.get_file_info(s3_path)
  #   exists = file_info.type != fs.FileType.NotFound
    
  #   if exists:
  #       logger.info(f"Carbon data file already exists: {s3_path}")
    
  #   return exists
        
  # except Exception as e:
  #     logger.warning(f"Could not find existing file named '{file_name}': {str(e)} assuming it doesn't exist...")
  #     # If we can't check, assume it doesn't exist to be safe
  #     return False
  return False

def cost_export_backfill_schedule_lock_create() -> None:
  logger.debug("WA DEBUG: cost_export_backfill_schedule_lock_create")

def cost_export_backfill_run_lock_create() -> None:
  logger.debug("WA DEBUG: cost_export_backfill_run_lock_create")

def cost_export_exists() -> bool:
    # try:
  #   # Get S3 filesystem
  #   s3 = getS3FileSystem()

  #   # the cost export can be one of more objects in a given path
  #   # the specific name of the export can not be predicted

  #   # the best way to know if the export exists or not is to check
  #   # for the "path" (directory) not the actual objects.
  #   s3_path = f"{Config.s3_carbon_path.rstrip('/')}/{Config.carbon_directory_name}/billing_period={billing_period}/{file_name}"
    
  #   # Check if file exists
  #   file_info = s3.get_file_info(s3_path)
  #   exists = file_info.type != fs.FileType.NotFound
    
  #   if exists:
  #       logger.info(f"Carbon data file already exists: {s3_path}")
    
  #   return exists
        
  # except Exception as e:
  #     logger.warning(f"Could not find existing file named '{file_name}': {str(e)} assuming it doesn't exist...")
  #     # If we can't check, assume it doesn't exist to be safe
  #     return False
  return True