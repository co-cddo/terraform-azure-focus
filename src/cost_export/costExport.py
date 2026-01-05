import logging
from typing import Tuple
from common import Config, getS3FileSystem

def cost_export_backfill_lock_exists() -> bool:
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
  #       logging.info(f"Carbon data file already exists: {s3_path}")
    
  #   return exists
        
  # except Exception as e:
  #     logging.warning(f"Could not find existing file named '{file_name}': {str(e)} assuming it doesn't exist...")
  #     # If we can't check, assume it doesn't exist to be safe
  #     return False
  return False

def create_cost_export_backfill_tasks(start_date: str) -> None:
  logging.info(f"WA DEBUG - create_cost_export_backfill_tasks: from {start_date}")

def run_cost_export_backfill(start_date: str) -> None:
  logging.info(f"WA DEBUG - run_cost_export_backfill: from {start_date}")

def cost_export_backfill(start_date: str, force_overwrite: bool = False, skip_existing: bool = True) -> Tuple[bool, bool]:
  logging.debug(f"cost_export_backfill: from {start_date}, overwrite({force_overwrite}), skip({skip_existing})")

  processed_months = 1
  skipped_months = 1

  # first check if the cost export backill lock exists
  if not cost_export_backfill_lock_exists():
      create_cost_export_backfill_tasks(start_date)
      run_cost_export_backfill(start_date)
  else:
      logging.info("Cost export backfill lock exists. Skipping backfill.")

  return (processed_months, skipped_months)
