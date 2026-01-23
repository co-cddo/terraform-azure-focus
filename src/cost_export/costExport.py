import logging
import os
from typing import Tuple
from datetime import datetime, timezone, timedelta

from common import Config
from api.s3Api import getS3FileSystem
from api.costMgmtApi import(
  cost_mgmt_export_exists,
  cost_mgmt_export_create,
  cost_mgmt_export_run,
)

from api.costMgmtS3Api import (
  cost_export_backfill_schedule_lock_exists,
  cost_export_backfill_run_lock_exists,
  cost_export_backfill_schedule_lock_create,
  cost_export_backfill_run_lock_create,
  cost_export_exists,
)

logger = logging.getLogger("cost_export")
logger.setLevel(os.environ.get('LOGGING_LEVEL', 'INFO'))

def cost_export_backfill_lock_create() -> None:
  logger.debug("cost_export_backfill_lock_create")

  try:
    # Get S3 filesystem
    s3 = getS3FileSystem()

    # Create lock file
    s3_path = f"{Config.s3_focus_path.rstrip('/')}/{Config.s3_cost_directory_name}/cost_export.lock"
    s3.create_directory(s3_path)
  except Exception as e:
    logger.error(f"Error creating cost export backfill lock: {str(e)}")

def get_backfill_until_month_year() -> Tuple[int, int]:
  today = datetime.today()
  first_of_this_month = today.replace(day=1)
  last_day_of_last_month = first_of_this_month - timedelta(days=1)
  return last_day_of_last_month.month, last_day_of_last_month.year

def increment_month_year(month: int, year: int) -> Tuple[int, int]:
  if month == 12:
    year += 1
    month = 1
  else:
    month += 1

  return month, year

def decrement_month_year(month: int, year: int) -> Tuple[int, int]:
  if month == 1:
    year -= 1
    month = 12
  else:
    month -= 1

  return month, year

def create_cost_export_backfill_tasks(start_date: datetime, account_id: str, account_idx: int) -> None:
  logger.info(f"create_cost_export_backfill_tasks ({account_idx}) for billing account: {account_id}")

  # iterate over month/year from backfill start date
  current_year, current_month = start_date.year, start_date.month

  # until last month (current month export is a daily continuous aggregate of the current month)
  until_month, until_year = get_backfill_until_month_year()
  logger.info(f"From {current_month}/{current_year} to {until_month}/{until_year}...")
  
  while (current_year, current_month) <= (until_year, until_month):
    logger.info(f"....{account_idx}: {current_month}/{current_year}")

    # check if the cost export task already exists; only create if not exists
    if not cost_mgmt_export_exists(account_idx=account_idx, account_id=account_id, month=current_month, year=current_year):
      cost_mgmt_export_create(account_idx=account_idx, account_id=account_id, month=current_month, year=current_year)
    else:
      logger.debug("....{account_idx}: {current_month}/{current_year} export task already exists")

    current_month, current_year = increment_month_year(current_month, current_year)
  
  # if we get this far, then we have created the full schedule of backfill Cost Management export jobs
  cost_export_backfill_schedule_lock_create()

def run_cost_export_backfill(start_date: datetime, account_id: str, account_idx: int, skip_existing:bool = True, force_overwrite:bool = False) -> None:
  MAX_NUMBER_OF_EXPORT_JOBS_RUNNING: int = 6

  logger.debug(f"run_cost_export_backfill ({account_idx}) from {start_date} for account: {account_id}; skip existing ({skip_existing}) with forced overwrite ({force_overwrite})")

  # iterate over month/year in reverse to backfill start date
  current_month, current_year = get_backfill_until_month_year()

  # until last month (current month export is a daily continuous aggregate of the current month)
  until_year, until_month = start_date.year, start_date.month
  logger.info(f"From {current_month}/{current_year} to {until_month}/{until_year}...")
  
  # there could be 100+ export jobs for a 10 year backfill; it is not practical (and subject to quotas)
  #  to initiate backfill on all jobs. So only initiate 10 at a time. The backfill job will
  #  keep running every day until all export jobs have executed.
  # We know an export has executed if there exists at least one of more objects in the target
  #  S3 bucket directory, so check for export data existing before attempting to run the job
  number_of_jobs_running: int = 0
  while ((current_year, current_month) >= (until_year, until_month)) and (number_of_jobs_running < MAX_NUMBER_OF_EXPORT_JOBS_RUNNING):
    logger.debug(f"....{account_idx}: {current_month}/{current_year}")

    # check if the cost export task already exists; only create if not exists
    current_month_year_data_exists = cost_export_exists(account_id=account_id, month=current_month, year=current_year)
    if not (skip_existing and current_month_year_data_exists):
      if not current_month_year_data_exists:
        logger.info(f"....{account_idx}: {current_month}/{current_year} export does NOT yet exist")

      if current_month_year_data_exists and not skip_existing:
        logger.info(f"....{account_idx}: {current_month}/{current_year} export does exist but skip exist is false")

      if cost_mgmt_export_exists(account_idx=account_idx, account_id=account_id, month=current_month, year=current_year):
        if (current_month_year_data_exists and force_overwrite == True) or (not current_month_year_data_exists):
          if current_month_year_data_exists:
            logger.info(f"....{account_idx}: {current_month}/{current_year} export does exist but force overwrite is true")

          cost_mgmt_export_run(account_idx=account_idx, account_id=account_id, month=current_month, year=current_year)
          number_of_jobs_running += 1

        else:
          logger.info(f"....{account_idx}: {current_month}/{current_year} skip existing is false but force overwrite is also false")
      else:
        logger.warning(f"....{account_idx}: {current_month}/{current_year} export task does not yet exist; release the backfill schedule lock")
    else:
      logger.info(f"....{account_idx}: {current_month}/{current_year} export already exists and skipping is enabled...")

    current_month, current_year = decrement_month_year(current_month, current_year)
  
  # if we get this far, and we've added zero job to run, then we can conclude we have ran all jobs
  #  as all data exists
  if number_of_jobs_running == 0:
    cost_export_backfill_run_lock_create()

def cost_export_backfill_impl(start_date: datetime, force_overwrite: bool = False, skip_existing: bool = True) -> None:
  logging.debug(f"cost_export_backfill: from {start_date}, overwrite({force_overwrite}), skip({skip_existing})")

  # Azure only stores up to seven years of cost data; if backfill exceeds this, then
  #  start from seven years go
  now = datetime.now()
  if (now - start_date).days > 2555:  # 7 years * 365 days
      logger.info(f"Cost Export Start date {start_date} is more than 7 years old. Setting start date to 7 years ago.")
      start_date = (now - timedelta(days=2555)).replace(day=1, hour=0, minute=0, second=0, microsecond=0)

  # first check if the cost export backill schedule lock exists
  if not cost_export_backfill_schedule_lock_exists():
    for idx, account_id in Config.billing_account_mapping.items():
      logger.info(f"Schedule for Billing Account ({idx}): {account_id}")

      create_cost_export_backfill_tasks(start_date=start_date, account_idx=int(idx), account_id=account_id)

  else:
    logger.info("Cost export backfill schedule lock exists. Skipping backfill schedule.")

  # now having the schedule available, try running the backfills schedule
  if not cost_export_backfill_run_lock_exists():
    for idx, account_id in Config.billing_account_mapping.items():
      logger.info(f"Run backfill for Billing Account ({idx}): {account_id}")
      run_cost_export_backfill(start_date=start_date, account_idx=int(idx), account_id=account_id, skip_existing=skip_existing, force_overwrite=force_overwrite)

  else:
    logger.info("Cost export backfill run lock exists. Skipping backfill run.")

