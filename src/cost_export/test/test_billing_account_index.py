"""Unit tests for extract_billing_account_from_blob_path in billing.py.

The export name carries the billing account index, and the parser reads it back out when
attributing a blob to a billing account. It must find the index wherever cost_mgmt_suffix leaves
it: the previous implementation read a fixed offset from the start of the name, so any deployment
setting a suffix shifted the index along and the parse silently returned None.

Run with:  python -m unittest discover -s src/cost_export/test
"""

import sys
import os
import types
import unittest
from unittest import mock

# billing uses flat imports (`from api.tokens import ...`), so the package directory has to be
# importable directly.
COST_EXPORT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if COST_EXPORT_DIR not in sys.path:
    sys.path.insert(0, COST_EXPORT_DIR)

# billing imports requests and api.tokens at module scope, but the parser under test touches
# neither. Stub them so this suite runs against a bare Python: CI installs no runtime
# dependencies, it just runs unittest. test_cost_export_backfill stubs api/* for its own purposes,
# so snapshot whatever is in sys.modules and put it back in tearDownModule.
_REPLACED_MODULES = ("requests", "api", "api.tokens", "billing")
_MODULES_BEFORE = {name: sys.modules[name] for name in _REPLACED_MODULES if name in sys.modules}
for _name in _REPLACED_MODULES:
    sys.modules.pop(_name, None)

sys.modules["requests"] = types.ModuleType("requests")

_api_stub = types.ModuleType("api")
_api_stub.__path__ = []  # mark as a package so `api.tokens` resolves
sys.modules["api"] = _api_stub

_tokens_stub = types.ModuleType("api.tokens")
_tokens_stub.TokenManager = mock.MagicMock(name="TokenManager")
sys.modules["api.tokens"] = _tokens_stub

from billing import extract_billing_account_from_blob_path  # noqa: E402  (import after stubs)


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
