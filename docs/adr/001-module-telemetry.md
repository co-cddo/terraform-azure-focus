# ADR-001: Module Telemetry via S3 Manifest

**Date:** 2026-09-10
**Status:** Proposed

## Context

The CCD team have no centralised way of knowing which version of the module is running in each customer environment, or what feature toggles are active. This makes it difficult to audit the configurations, plan upgrades, or diagnose environment-specific issues.

## Decision

Introduce a lightweight telemetry mechanism that writes a JSON manifest to the existing S3 storage path on a daily schedule.

### Design

1. **Source of truth for module identity** - The `Azure/modtm` Terraform provider extracts `module_source` and `module_version` from the module's registry metadata at plan time. These values are passed to the Function App as environment variables (`MODULE_SOURCE`, `MODULE_VERSION`).

2. **Manifest content** - A `manifest.json` file containing:
   - `module_source` - Git or registry URL of the module.
   - `module_version` - Semantic version tag.
   - `configuration` - Current feature toggle states (`enable_focus_exports`, `enable_advisor_exports`, `enable_carbon_exports`) and `backfill_start_date`.

3. **Delivery mechanism** - A new `Utility` Azure Function with a daily timer trigger (04:00 UTC) writes the manifest to `{s3_focus_path}/manifest.json` using the existing S3 (via PyArrow) file system helper. The function reuses the same S3 credentials and path already configured for cost export data.

4. **Terraform outputs** - `module_source` and `module_version` are also exposed as Terraform outputs for use by calling modules or CI pipelines.

## Consequences

**Positive**

- Centralised, machine-readable record of deployed module version and configuration per environment.
- No new infrastructure, credentials, or storage paths required - piggybacks on the existing S3 export pipeline.
- Daily cadence keeps the manifest current without adding meaningful cost or API load.

**Negative**

- The manifest is only as fresh as the last successful timer run (up to 24 hours stale).
- Adds a dependency on the `Azure/modtm` provider.
- If S3 writes fail, manifest staleness is silent unless log monitoring is in place.
