"""Unit tests for the cost export backfill orchestration in costExport.py.

Focus: the backfill run lock and schedule lock are single, global objects, but they must only be
created once *every* billing account is done (run lock) or scheduled (schedule lock). Creating
either from inside the per-account helpers lets one finished account lock out others that still
have months outstanding - the multi billing account regression these tests guard against.

Run with:  python -m unittest discover -s src/cost_export/test
"""

import os
import sys
import types
import unittest
from unittest import mock
from datetime import datetime

# costExport uses flat imports (`from common import Config`, `from api.* import ...`), so the
# package directory has to be importable directly.
COST_EXPORT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if COST_EXPORT_DIR not in sys.path:
    sys.path.insert(0, COST_EXPORT_DIR)


def _install_stub_modules():
    """Replace costExport's import-time dependencies with lightweight stubs.

    common.Config reads required env vars at import time and api.* pull in boto3/azure/pyarrow;
    none of that is needed to test the orchestration logic. Individual functions are controlled
    per-test via mock.patch.object(costExport, ...).
    """
    common = types.ModuleType("common")

    class Config:
        billing_account_mapping = {}

    common.Config = Config
    common.is_uuid = lambda value: False
    sys.modules["common"] = common

    api = types.ModuleType("api")
    api.__path__ = []  # mark as a package so `api.s3Api` submodule imports resolve
    sys.modules["api"] = api

    s3_api = types.ModuleType("api.s3Api")
    s3_api.getS3FileSystem = mock.MagicMock(name="getS3FileSystem")
    sys.modules["api.s3Api"] = s3_api

    cost_mgmt_api = types.ModuleType("api.costMgmtApi")
    cost_mgmt_api.cost_mgmt_export_exists = mock.MagicMock(name="cost_mgmt_export_exists")
    cost_mgmt_api.cost_mgmt_export_create = mock.MagicMock(name="cost_mgmt_export_create")
    cost_mgmt_api.cost_mgmt_export_run = mock.MagicMock(name="cost_mgmt_export_run")
    sys.modules["api.costMgmtApi"] = cost_mgmt_api

    cost_mgmt_s3_api = types.ModuleType("api.costMgmtS3Api")
    for _name in (
        "cost_export_backfill_schedule_lock_exists",
        "cost_export_backfill_run_lock_exists",
        "cost_export_backfill_schedule_lock_create",
        "cost_export_backfill_run_lock_create",
        "cost_export_exists",
    ):
        setattr(cost_mgmt_s3_api, _name, mock.MagicMock(name=_name))
    sys.modules["api.costMgmtS3Api"] = cost_mgmt_s3_api


_install_stub_modules()

import costExport  # noqa: E402  (import after stubs are installed)


# Fixed "current month" so the backfill window is deterministic regardless of the real clock.
FIXED_UNTIL_MONTH_YEAR = (6, 2025)  # (month, year) as returned by get_backfill_until_month_year


class CostExportBackfillRunLockTest(unittest.TestCase):
    def setUp(self):
        # Two billing accounts in the order Terraform emits them: idx 0 is the older account
        # (processed first), idx 1 the newly switched one that still has months to backfill.
        costExport.Config.billing_account_mapping = {"0": "old-account", "1": "new-account"}

        # Patch the shared collaborators used across the tested call paths.
        patchers = {
            "until": mock.patch.object(
                costExport, "get_backfill_until_month_year", return_value=FIXED_UNTIL_MONTH_YEAR
            ),
            "schedule_lock_exists": mock.patch.object(costExport, "cost_export_backfill_schedule_lock_exists"),
            "run_lock_exists": mock.patch.object(costExport, "cost_export_backfill_run_lock_exists"),
            "schedule_lock_create": mock.patch.object(costExport, "cost_export_backfill_schedule_lock_create"),
            "run_lock_create": mock.patch.object(costExport, "cost_export_backfill_run_lock_create"),
            "export_task_exists": mock.patch.object(costExport, "cost_mgmt_export_exists", return_value=True),
            "export_run": mock.patch.object(costExport, "cost_mgmt_export_run", return_value=True),
            "data_exists": mock.patch.object(costExport, "cost_export_exists"),
            "create_tasks": mock.patch.object(costExport, "create_cost_export_backfill_tasks"),
        }
        self.mocks = {name: patcher.start() for name, patcher in patchers.items()}
        for patcher in patchers.values():
            self.addCleanup(patcher.stop)

        # Backfill window Jan 2024 -> Jun 2025 = 18 months; wider than the 6 job/run cap so a
        # not-yet-complete account is genuinely mid-flight.
        self.start_date = datetime(2024, 1, 1)

    def test_run_lock_not_created_while_one_account_still_pending(self):
        """Regression: old account is fully backfilled, new account is not.

        With the per-account lock bug, the completed old account created the global run lock and
        blocked the new account every night. The lock must not be created while any account still
        has jobs to run.
        """
        self.mocks["schedule_lock_exists"].return_value = True  # skip scheduling
        self.mocks["run_lock_exists"].return_value = False

        def data_exists(account_id, month, year):
            return account_id == "old-account"  # old complete, new has no data yet

        self.mocks["data_exists"].side_effect = data_exists

        costExport.cost_export_backfill_impl(start_date=self.start_date)

        self.mocks["run_lock_create"].assert_not_called()
        # The new account should have kicked off a batch of exports (capped at 6 per run).
        self.assertEqual(self.mocks["export_run"].call_count, 6)

    def test_run_lock_created_only_when_all_accounts_complete(self):
        """When every account already has all its data, the global run lock is created exactly once."""
        self.mocks["schedule_lock_exists"].return_value = True
        self.mocks["run_lock_exists"].return_value = False
        self.mocks["data_exists"].return_value = True  # both accounts fully backfilled

        costExport.cost_export_backfill_impl(start_date=self.start_date)

        self.mocks["run_lock_create"].assert_called_once()
        self.mocks["export_run"].assert_not_called()

    def test_existing_run_lock_short_circuits_the_run(self):
        self.mocks["schedule_lock_exists"].return_value = True
        self.mocks["run_lock_exists"].return_value = True

        costExport.cost_export_backfill_impl(start_date=self.start_date)

        self.mocks["export_run"].assert_not_called()
        self.mocks["run_lock_create"].assert_not_called()

    def test_schedule_lock_created_once_after_all_accounts_scheduled(self):
        self.mocks["schedule_lock_exists"].return_value = False
        self.mocks["run_lock_exists"].return_value = True  # skip the run phase

        costExport.cost_export_backfill_impl(start_date=self.start_date)

        # Scheduled for both accounts, but the single global schedule lock is created only once.
        self.assertEqual(self.mocks["create_tasks"].call_count, 2)
        self.mocks["schedule_lock_create"].assert_called_once()

    def test_schedule_lock_not_created_if_an_account_fails_to_schedule(self):
        """If scheduling raises partway, the global schedule lock must not be stamped, so the whole
        schedule is retried next run (task creation is idempotent)."""
        self.mocks["schedule_lock_exists"].return_value = False
        self.mocks["run_lock_exists"].return_value = True

        self.mocks["create_tasks"].side_effect = [None, RuntimeError("boom")]

        with self.assertRaises(RuntimeError):
            costExport.cost_export_backfill_impl(start_date=self.start_date)

        self.mocks["schedule_lock_create"].assert_not_called()


class RunCostExportBackfillReturnValueTest(unittest.TestCase):
    """run_cost_export_backfill must report its job count instead of creating the global lock."""

    def setUp(self):
        self.until_patcher = mock.patch.object(
            costExport, "get_backfill_until_month_year", return_value=FIXED_UNTIL_MONTH_YEAR
        )
        self.until_patcher.start()
        self.addCleanup(self.until_patcher.stop)
        self.run_lock_create = mock.patch.object(costExport, "cost_export_backfill_run_lock_create").start()
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(costExport, "cost_mgmt_export_exists", return_value=True).start()
        mock.patch.object(costExport, "cost_mgmt_export_run", return_value=True).start()
        self.data_exists = mock.patch.object(costExport, "cost_export_exists").start()
        self.start_date = datetime(2024, 1, 1)

    def test_returns_zero_and_never_locks_when_all_data_present(self):
        self.data_exists.return_value = True
        result = costExport.run_cost_export_backfill(
            start_date=self.start_date, account_id="acct", account_idx=0
        )
        self.assertEqual(result, 0)
        self.run_lock_create.assert_not_called()

    def test_returns_capped_job_count_when_data_missing(self):
        self.data_exists.return_value = False
        result = costExport.run_cost_export_backfill(
            start_date=self.start_date, account_id="acct", account_idx=0
        )
        self.assertEqual(result, 6)  # MAX_NUMBER_OF_EXPORT_JOBS_RUNNING
        self.run_lock_create.assert_not_called()


if __name__ == "__main__":
    unittest.main()
