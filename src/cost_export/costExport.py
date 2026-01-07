import logging
from typing import Tuple
from datetime import datetime, timezone, timedelta

from common import Config, getS3FileSystem
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

def create_cost_export_backfill_tasks(start_date: str, account_id: str, account_idx: int) -> None:
  logger.info(f"create_cost_export_backfill_tasks ({account_idx}) for billing account: {account_id}")

  # iterate over month/year from backfill start date
  current_year, current_month = start_date.year, start_date.month

  # until last month (current month export is a daily continuous aggregate of the current month)
  until_month, until_year = get_backfill_until_month_year()
  logger.info(f"From {current_month}/{current_year} to {until_month}/{until_year}...")
  
  while (current_year, current_month) <= (until_year, until_month):
    logger.debug(f"....{account_idx}: {current_month}/{current_year}")

    # check if the cost export task already exists; only create if not exists
    if not cost_mgmt_export_exists(account_idx=account_idx, account_id=account_id, month=current_month, year=current_year):
      cost_mgmt_export_create(account_idx=account_idx, account_id=account_id, month=current_month, year=current_year)
    else:
      logger.debug("....{account_idx}: {current_month}/{current_year} export task already exists")

    current_month, current_year = increment_month_year(current_month, current_year)

def run_cost_export_backfill(start_date: str, account_id: str, account_idx: int) -> None:
  MAX_NUMBER_OF_EXPORT_JOBS_RUNNING: int = 10

  logger.debug(f"run_cost_export_backfill ({account_idx}) from {start_date} for account: {account_id}")

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
    if not cost_export_exists():
      if cost_mgmt_export_exists(account_idx=account_idx, account_id=account_id, month=current_month, year=current_year):
        cost_mgmt_export_run(account_idx=account_idx, account_id=account_id, month=current_month, year=current_year)
        number_of_jobs_running += 1;
      else:
        logger.warning("....{account_idx}: {current_month}/{current_year} export task does not yet exist; release the backfill schedule lock")
    else:
        logger.info(f"....{account_idx}: {current_month}/{current_year} export already exists, skipping...")

    current_month, current_year = decrement_month_year(current_month, current_year)


def cost_export_backfill_impl(start_date: str, force_overwrite: bool = False, skip_existing: bool = True) -> None:
  logging.debug(f"cost_export_backfill: from {start_date}, overwrite({force_overwrite}), skip({skip_existing})")  

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
      run_cost_export_backfill(start_date=start_date, account_idx=int(idx), account_id=account_id)

  else:
    logger.info("Cost export backfill run lock exists. Skipping backfill run.")

