"""Unit tests for extract_billing_account_from_blob_path in billing.py.

The export name carries the billing account index, and the parser reads it back out when
attributing a blob to a billing account. It must find the index wherever cost_mgmt_suffix leaves
it: the previous implementation read a fixed offset from the start of the name, so any deployment
setting a suffix shifted the index along and the parse silently returned None.

Run with:  python -m unittest discover -s src/cost_export/test
"""

import os
import sys
import unittest
from unittest import mock

COST_EXPORT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if COST_EXPORT_DIR not in sys.path:
    sys.path.insert(0, COST_EXPORT_DIR)

# common.Config reads these at import time.
_REQUIRED_ENV = {
    "ENTRA_APP_CLIENT_ID": "00000000-0000-0000-0000-000000000000",
    "ENTRA_APP_URN": "api://test",
    "AWS_ROLE_ARN": "arn:aws:iam::000000000000:role/test",
    "S3_FOCUS_PATH": "bucket/tenant",
    "AWS_REGION": "eu-west-2",
    "STORAGE_ACCOUNT_BLOB_ENDPOINT": "https://test.blob.core.windows.net/",
    "CONTAINER_NAME": "cost-exports",
    "ROOT_FOLDER_PATH": "gds-focus-v1",
    "S3_UTILIZATION_PATH": "bucket/tenant",
    "S3_RECOMMENDATIONS_PATH": "bucket/tenant",
    "S3_CARBON_PATH": "bucket/tenant",
    "CARBON_DIRECTORY_NAME": "gds-carbon-v1",
    "BACKFILL_START_DATE": "2022-01-01",
    "STORAGE_CONTAINER": "cost-exports",
    "STORAGE_RESOURCE_ID": "/subscriptions/x/resourceGroups/y/providers/Microsoft.Storage/storageAccounts/z",
    "COST_MGMT_SUFFIX": "",
}

# test_cost_export_backfill stubs these at import time and discovery imports it first
# (alphabetical), so drop the stubs to get the real modules, then restore sys.modules as found.
_REPLACED_MODULES = ("common", "api", "api.tokens", "billing")
_MODULES_BEFORE = {name: sys.modules[name] for name in _REPLACED_MODULES if name in sys.modules}
for _name in _REPLACED_MODULES:
    sys.modules.pop(_name, None)

with mock.patch.dict(os.environ, _REQUIRED_ENV, clear=False):
    from billing import extract_billing_account_from_blob_path


def tearDownModule():
    for name in _REPLACED_MODULES:
        sys.modules.pop(name, None)
    sys.modules.update(_MODULES_BEFORE)


class ExtractBillingAccountIndexTests(unittest.TestCase):
    def _path(self, export_name):
        return f"gds-focus-v1/{export_name}/billing_period=20251001/part_0_0001.parquet"

    def test_daily_export(self):
        self.assertEqual(extract_billing_account_from_blob_path(self._path("focus-daily-cost-export-6")), 6)

    def test_daily_export_with_suffix(self):
        self.assertEqual(extract_billing_account_from_blob_path(self._path("focus-daily-cost-export-prod-5")), 5)

    def test_backfill_export(self):
        self.assertEqual(extract_billing_account_from_blob_path(self._path("focus-backfill-1-2025-10")), 1)

    def test_backfill_export_with_suffix(self):
        # The regression: a suffix used to shift the index out of the position being read.
        self.assertEqual(extract_billing_account_from_blob_path(self._path("focus-backfill-prod-4-2025-10")), 4)

    def test_multi_segment_suffix(self):
        self.assertEqual(extract_billing_account_from_blob_path(self._path("focus-backfill-eu-prod-2-2025-10")), 2)

    def test_double_digit_index(self):
        self.assertEqual(extract_billing_account_from_blob_path(self._path("focus-backfill-prod-12-2025-10")), 12)

    def test_unrecognised_path_returns_none(self):
        self.assertIsNone(extract_billing_account_from_blob_path("gds-focus-v1/something-else/part_0.parquet"))


if __name__ == "__main__":
    unittest.main()
