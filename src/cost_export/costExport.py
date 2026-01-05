import logging
from typing import Tuple

def cost_export_backfill_lock_exists() -> bool:
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