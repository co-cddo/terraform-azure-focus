"""Unit tests for the Utility timer trigger function in function_app.py.

Run with:  python -m unittest discover -s src/cost_export/test
"""

import json
import os
import sys
import types
import unittest
from unittest import mock

COST_EXPORT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
_COST_EXPORT_DIR_ALREADY_ON_PATH = COST_EXPORT_DIR in sys.path
if not _COST_EXPORT_DIR_ALREADY_ON_PATH:
    sys.path.insert(0, COST_EXPORT_DIR)


_STUBBED_MODULES = (
    "common",
    "api",
    "api.s3Api",
    "api.tokens",
    "api.costMgmtApi",
    "api.costMgmtS3Api",
    "api.carbonS3Api",
    "carbonExport",
    "costExport",
    "billing",
    "azure",
    "azure.functions",
    "azure.storage",
    "azure.storage.blob",
    "azure.identity",
    "pyarrow",
    "pyarrow.parquet",
    "pyarrow.fs",
    "requests",
)

_ORIGINAL_MODULES = {}

mock_s3_filesystem = mock.MagicMock(name="getS3FileSystem")


class _StubConfig:
    module_source = "git::https://github.com/co-cddo/terraform-azure-focus.git?ref=v4.0.0"
    module_version = "v4.0.0"
    s3_focus_path = "test-bucket/test-tenant-id"
    backfill_start_date = "2022-01-01"
    enable_focus_exports = True
    enable_advisor_exports = False
    enable_carbon_exports = True
    billing_account_mapping = {}
    managed_identity_client_id = None
    billing_scope = None


class _MockFunctionApp:
    """FunctionApp stub whose decorator methods are transparent pass-throughs."""
    def __getattr__(self, name):
        def decorator_factory(*args, **kwargs):
            return lambda fn: fn
        return decorator_factory


def _install_stub_modules():
    for name in _STUBBED_MODULES:
        _ORIGINAL_MODULES[name] = sys.modules.get(name)

    # common
    common = types.ModuleType("common")
    common.Config = _StubConfig
    common.is_uuid = lambda value: False
    sys.modules["common"] = common

    # api package
    api = types.ModuleType("api")
    api.__path__ = []
    sys.modules["api"] = api

    s3_api = types.ModuleType("api.s3Api")
    s3_api.getS3FileSystem = mock_s3_filesystem
    sys.modules["api.s3Api"] = s3_api

    tokens = types.ModuleType("api.tokens")
    tokens.TokenManager = mock.MagicMock(name="TokenManager")
    sys.modules["api.tokens"] = tokens

    for mod_name in ("api.costMgmtApi", "api.costMgmtS3Api", "api.carbonS3Api"):
        sys.modules[mod_name] = types.ModuleType(mod_name)

    # carbonExport / costExport / billing
    carbon = types.ModuleType("carbonExport")
    for fn in (
        "get_carbon_api_date_range",
        "is_month_within_api_range",
        "make_carbon_api_request_batched",
        "carbon_export_api_latest_fetch_date",
        "check_carbon_data_exists",
        "save_carbon_data_to_s3",
        "carbon_emissions_backfill_imp",
    ):
        setattr(carbon, fn, mock.MagicMock(name=fn))
    sys.modules["carbonExport"] = carbon

    cost = types.ModuleType("costExport")
    cost.cost_export_backfill_impl = mock.MagicMock(name="cost_export_backfill_impl")
    sys.modules["costExport"] = cost

    billing_mod = types.ModuleType("billing")
    billing_mod.extract_subscription_ids_from_billing_scope = mock.MagicMock()
    billing_mod.extract_billing_account_from_blob_path = mock.MagicMock()
    sys.modules["billing"] = billing_mod

    # azure.*
    azure_mod = types.ModuleType("azure")
    azure_mod.__path__ = []
    sys.modules["azure"] = azure_mod

    func_mod = types.ModuleType("azure.functions")
    func_mod.FunctionApp = _MockFunctionApp
    func_mod.TimerRequest = mock.MagicMock(name="TimerRequest")
    func_mod.QueueMessage = mock.MagicMock(name="QueueMessage")
    func_mod.HttpRequest = mock.MagicMock(name="HttpRequest")
    func_mod.HttpResponse = mock.MagicMock(name="HttpResponse")
    func_mod.AuthLevel = mock.MagicMock(name="AuthLevel")
    sys.modules["azure.functions"] = func_mod

    storage_mod = types.ModuleType("azure.storage")
    storage_mod.__path__ = []
    sys.modules["azure.storage"] = storage_mod

    blob_mod = types.ModuleType("azure.storage.blob")
    blob_mod.BlobServiceClient = mock.MagicMock(name="BlobServiceClient")
    sys.modules["azure.storage.blob"] = blob_mod

    identity_mod = types.ModuleType("azure.identity")
    identity_mod.ManagedIdentityCredential = mock.MagicMock(name="ManagedIdentityCredential")
    sys.modules["azure.identity"] = identity_mod

    # pyarrow
    pa = types.ModuleType("pyarrow")
    pa.__path__ = []
    sys.modules["pyarrow"] = pa

    pq = types.ModuleType("pyarrow.parquet")
    sys.modules["pyarrow.parquet"] = pq

    pa_fs = types.ModuleType("pyarrow.fs")
    sys.modules["pyarrow.fs"] = pa_fs

    # requests
    sys.modules["requests"] = types.ModuleType("requests")

    sys.modules.pop("function_app", None)


def _restore_modules():
    for name, mod in _ORIGINAL_MODULES.items():
        if mod is None:
            sys.modules.pop(name, None)
        else:
            sys.modules[name] = mod


_install_stub_modules()

import function_app  # noqa: E402


def tearDownModule():
    _restore_modules()
    if not _COST_EXPORT_DIR_ALREADY_ON_PATH:
        try:
            sys.path.remove(COST_EXPORT_DIR)
        except ValueError:
            pass


class UtilityManifestTest(unittest.TestCase):
    """Tests for the Utility timer trigger's manifest upsert."""

    def setUp(self):
        mock_s3_filesystem.reset_mock()

    def _make_timer(self, past_due=False):
        timer = mock.MagicMock()
        timer.past_due = past_due
        return timer

    def _setup_s3_mock(self):
        mock_stream = mock.MagicMock()
        mock_s3 = mock.MagicMock()
        mock_s3.open_output_stream.return_value.__enter__ = mock.MagicMock(return_value=mock_stream)
        mock_s3.open_output_stream.return_value.__exit__ = mock.MagicMock(return_value=False)
        mock_s3_filesystem.return_value = mock_s3
        return mock_s3, mock_stream

    def test_writes_manifest_with_expected_content(self):
        mock_s3, mock_stream = self._setup_s3_mock()

        function_app.utility(self._make_timer())

        mock_s3.open_output_stream.assert_called_once_with("test-bucket/test-tenant-id/manifest.json")

        written_bytes = mock_stream.write.call_args[0][0]
        manifest = json.loads(written_bytes.decode("utf-8"))

        self.assertEqual(manifest["module_source"], "git::https://github.com/co-cddo/terraform-azure-focus.git?ref=v4.0.0")
        self.assertEqual(manifest["module_version"], "v4.0.0")
        self.assertEqual(manifest["configuration"]["backfill_start_date"], "2022-01-01")
        self.assertIs(manifest["configuration"]["enable_focus_exports"], True)
        self.assertIs(manifest["configuration"]["enable_advisor_exports"], False)
        self.assertIs(manifest["configuration"]["enable_carbon_exports"], True)

    def test_strips_trailing_slash_from_s3_path(self):
        mock_s3, _ = self._setup_s3_mock()
        original = _StubConfig.s3_focus_path

        try:
            _StubConfig.s3_focus_path = "bucket/tenant/"
            function_app.utility(self._make_timer())
        finally:
            _StubConfig.s3_focus_path = original

        mock_s3.open_output_stream.assert_called_once_with("bucket/tenant/manifest.json")

    def test_s3_failure_raises(self):
        mock_s3 = mock.MagicMock()
        mock_s3.open_output_stream.side_effect = OSError("connection refused")
        mock_s3_filesystem.return_value = mock_s3

        with self.assertRaises(OSError):
            function_app.utility(self._make_timer())


if __name__ == "__main__":
    unittest.main()
