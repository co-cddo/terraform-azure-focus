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
_COST_EXPORT_DIR_ALREADY_ON_PATH = COST_EXPORT_DIR in sys.path
if not _COST_EXPORT_DIR_ALREADY_ON_PATH:
    sys.path.insert(0, COST_EXPORT_DIR)


# Modules replaced with stubs below. costExport is imported under those stubs, so it is
# snapshotted/restored too; otherwise a later test module in the same process would import
# the stub-contaminated costExport instead of the real one.
_STUBBED_MODULES = (
    "common",
    "api",
    "api.s3Api",
    "api.costMgmtApi",
    "api.costMgmtS3Api",
    "costExport",
)

# sys.modules snapshot for the names above, taken before any stub is installed, so
# tearDownModule can put the process back exactly as it found it.
_ORIGINAL_MODULES = {}


def _install_stub_modules():
    """Replace costExport's import-time dependencies with lightweight stubs.

    common.Config reads required env vars at import time and api.* pull in boto3/azure/pyarrow;
    none of that is needed to test the orchestration logic. Individual functions are controlled
    per-test via mock.patch.object(costExport, ...).
    """
    for _module_name in _STUBBED_MODULES:
        _ORIGINAL_MODULES[_module_name] = sys.modules.get(_module_name)

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

    # Drop any cached costExport so the `import costExport` below re-imports it under the stubs
    # just installed. If an earlier test module in this process already imported the real
    # costExport, the cached copy (bound to the heavy real dependencies) would otherwise be
    # reused. The original was snapshotted above, so tearDownModule still restores it.
    sys.modules.pop("costExport", None)


def _restore_modules():
    """Undo the stub installation (and the stub-bound costExport import) so the stubs do not
    leak into other test modules that share this Python process."""
    for _module_name, _module in _ORIGINAL_MODULES.items():
        if _module is None:
            sys.modules.pop(_module_name, None)
        else:
            sys.modules[_module_name] = _module


_install_stub_modules()

import costExport  # noqa: E402  (import after stubs are installed)


def tearDownModule():
    _restore_modules()
    # Undo the sys.path.insert done at import time so we don't change import resolution for
    # other test modules; only remove it if we were the ones who added it.
    if not _COST_EXPORT_DIR_ALREADY_ON_PATH:
        try:
            sys.path.remove(COST_EXPORT_DIR)
        except ValueError:
            pass


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
            "create_tasks": mock.patch.object(costExport, "create_cost_export_backfill_tasks", return_value=True),
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

    def test_no_locks_created_when_no_billing_accounts_configured(self):
        """A misconfigured (empty) BILLING_ACCOUNT_MAPPING must not stamp either global lock;
        otherwise backfill is permanently short-circuited once accounts are configured."""
        costExport.Config.billing_account_mapping = {}
        self.mocks["schedule_lock_exists"].return_value = False
        self.mocks["run_lock_exists"].return_value = False

        costExport.cost_export_backfill_impl(start_date=self.start_date)

        self.mocks["create_tasks"].assert_not_called()
        self.mocks["schedule_lock_create"].assert_not_called()
        self.mocks["run_lock_create"].assert_not_called()

    def test_schedule_lock_not_created_if_an_account_fails_to_schedule(self):
        """If scheduling raises partway, the global schedule lock must not be stamped, so the whole
        schedule is retried next run (task creation is idempotent)."""
        self.mocks["schedule_lock_exists"].return_value = False
        self.mocks["run_lock_exists"].return_value = True

        self.mocks["create_tasks"].side_effect = [None, RuntimeError("boom")]

        with self.assertRaises(RuntimeError):
            costExport.cost_export_backfill_impl(start_date=self.start_date)

        self.mocks["schedule_lock_create"].assert_not_called()

    def test_schedule_lock_not_created_if_a_task_could_not_be_created(self):
        """cost_mgmt_export_create reports failure by returning False rather than raising, so a
        billing account whose every create was refused (typically an EA account missing its manual
        role assignment) would otherwise stamp the lock over an empty schedule and stall the
        deployment permanently: nothing recreates the tasks once the lock is in place."""
        self.mocks["schedule_lock_exists"].return_value = False
        self.mocks["run_lock_exists"].return_value = True

        self.mocks["create_tasks"].side_effect = [True, False]

        costExport.cost_export_backfill_impl(start_date=self.start_date)

        self.assertEqual(self.mocks["create_tasks"].call_count, 2)
        self.mocks["schedule_lock_create"].assert_not_called()

    def test_run_phase_skipped_when_schedule_lock_missing(self):
        """When scheduling fails and the schedule lock is not stamped, the run phase must not
        execute. Without this guard, months with no data AND no export task return 0 jobs (nothing
        to run), which falsely stamps the run lock as though backfill is complete."""
        self.mocks["schedule_lock_exists"].return_value = False
        self.mocks["run_lock_exists"].return_value = False

        self.mocks["create_tasks"].side_effect = [True, False]  # second account fails

        costExport.cost_export_backfill_impl(start_date=self.start_date)

        self.mocks["run_lock_create"].assert_not_called()
        self.mocks["export_run"].assert_not_called()


class RunCostExportBackfillReturnValueTest(unittest.TestCase):
    """run_cost_export_backfill must report its job count instead of creating the global lock."""

    def setUp(self):
        patchers = {
            "until": mock.patch.object(
                costExport, "get_backfill_until_month_year", return_value=FIXED_UNTIL_MONTH_YEAR
            ),
            "run_lock_create": mock.patch.object(costExport, "cost_export_backfill_run_lock_create"),
            "export_exists": mock.patch.object(costExport, "cost_mgmt_export_exists", return_value=True),
            "export_run": mock.patch.object(costExport, "cost_mgmt_export_run", return_value=True),
            "data_exists": mock.patch.object(costExport, "cost_export_exists"),
        }
        self.mocks = {name: patcher.start() for name, patcher in patchers.items()}
        for patcher in patchers.values():
            self.addCleanup(patcher.stop)

        self.run_lock_create = self.mocks["run_lock_create"]
        self.data_exists = self.mocks["data_exists"]
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


class CreateCostExportBackfillTasksResultTest(unittest.TestCase):
    """create_cost_export_backfill_tasks must report whether every month's task now exists.

    This is the value cost_export_backfill_impl gates the schedule lock on, and the place the
    failure was previously swallowed: cost_mgmt_export_create returns False on a refused create
    rather than raising, and the result was discarded.
    """

    def setUp(self):
        patchers = {
            "until": mock.patch.object(
                costExport, "get_backfill_until_month_year", return_value=FIXED_UNTIL_MONTH_YEAR
            ),
            "task_exists": mock.patch.object(costExport, "cost_mgmt_export_exists"),
            "create": mock.patch.object(costExport, "cost_mgmt_export_create"),
        }
        self.mocks = {name: patcher.start() for name, patcher in patchers.items()}
        for patcher in patchers.values():
            self.addCleanup(patcher.stop)
        self.start_date = datetime(2025, 1, 1)

    def _create(self):
        return costExport.create_cost_export_backfill_tasks(
            start_date=self.start_date, account_id="acct", account_idx=0
        )

    def test_returns_true_when_every_create_succeeds(self):
        self.mocks["create"].return_value = True
        self.assertTrue(self._create())

    def test_returns_false_when_any_create_is_refused(self):
        # Jan to Jun 2025 = 6 months; refuse the third.
        self.mocks["create"].side_effect = [True, True, False, True, True, True]
        self.assertFalse(self._create())

    def test_returns_false_when_every_create_is_refused(self):
        # The EA shape: no permission, so nothing is ever scheduled.
        self.mocks["create"].return_value = False
        self.assertFalse(self._create())

    def test_existing_tasks_are_still_put(self):
        """Months whose task already exists are PUT again rather than skipped.

        A task left behind by a previous deployment still points at that deployment's storage
        account, which no longer exists. Skipping it leaves the destination stale, the export run
        fails, and backfill stalls permanently. The PUT is an upsert, so it repoints the task at
        this deployment's storage account.
        """
        self.mocks["task_exists"].return_value = True
        self.assertTrue(self._create())
        # Jan to Jun 2025 inclusive.
        self.assertEqual(self.mocks["create"].call_count, 6)

    def test_existence_is_not_consulted(self):
        # The GET is gone: the upsert makes it redundant and it was the source of the stale
        # destination bug.
        self.mocks["create"].return_value = True
        self._create()
        self.mocks["task_exists"].assert_not_called()


if __name__ == "__main__":
    unittest.main()
