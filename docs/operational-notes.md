# Operational notes

Behaviour of the deployed module that is not obvious from the code, gathered while
investigating customer onboarding problems. Written as reference for whoever picks up
the backfill or management-group work next.

## Backfill takes about two calendar weeks, not days

Three things combine to set the pace:

- `run_cost_export_backfill` caps itself at `MAX_NUMBER_OF_EXPORT_JOBS_RUNNING` (6). The
  counter is per call, and the caller invokes it once per billing account, so it is 6
  months per billing account per trigger. Accounts progress in parallel, so adding
  billing accounts does not extend the timeline.
- `BackfillTrigger` is `0 0 6 * * 1-5`: 06:00 UTC, **weekdays only**. Five runs a week.
- `run_on_startup=False`, so a redeploy does not kick one off. The first run is the next
  weekday at 06:00.

With the default `backfill_start_date` of `2022-01-01` that is 54 months, 9 to 10 runs,
so **11 to 13 calendar days**. At the 7-year cap it is 84 months, 14 runs, 18 to 20 days.

Forward progress depends on the previous batch's data having reached S3, because the
skip test is `cost_export_exists` against S3 rather than the export's own status. A
stalled `CostExportProcessor` means a run makes zero progress and silently repeats the
same six months.

## Every month's export is created up front

`create_cost_export_backfill_tasks` has no per-run cap, unlike the run phase. It walks
the whole range and creates every month's export definition in the first invocation,
then the run phase consumes them 6 at a time. So peak export count is reached on day
one, not gradually: over fifty definitions per billing account at the default start
date. Nothing deletes them, so they persist for the life of the deployment.

If there is a per-scope Cost Management export quota below the month count, the create
loop would fail partway on *every* run, the schedule lock would never be stamped, and
backfill would retry forever without progressing. This has not been confirmed against a
real quota limit.

## The backfill locks live in S3, not Azure

`cost-backfill-schedule.lock` and `cost-backfill-run.lock` sit at
`{bucket}/{tenant-id}/{root-folder}-cost-backfill-*.lock`. Consequences:

- Purging the whole S3 bucket clears them, so backfill restarts on the next weekday.
- A **partial** purge that removes `billing_period=` data but leaves the lock objects
  means backfill never re-runs. The HTTP `cost-export-backfill` endpoint does not
  rescue you either: it goes through the same `cost_export_backfill_impl` and hits the
  same run lock. Deleting the lock objects is the only switch.
- They are keyed by tenant, not by deployment, so two deployments in one tenant share
  them.

## Export creation fails silently without billing permission

This is the shape of the most common onboarding failure, typically an EA billing
account whose manual `EnrollmentReader` assignment was never made:

1. `cost_mgmt_export_create` gets a 403, logs an error, returns `False`.
2. `create_cost_export_backfill_tasks` discards that return value and completes without
   raising.
3. `cost_export_backfill_impl` therefore stamps the **schedule lock** anyway.
4. The schedule phase is skipped from then on, and the run phase finds no export task
   for any month.

The deployment is left permanently stalled with no data, no export tasks and no route
back short of manually deleting the lock object from S3. The only external signal is
that no backfill exports appear in the portal, which is why asking a customer to check
for them is a useful onboarding test.

Two things would improve this, neither of which is currently implemented:

- Have the run phase recreate a missing export task instead of only logging a warning.
  That makes the failure self-healing: it retries every weekday and recovers on its own
  once the role assignment is made.
- Query Application Insights for `cost_mgmt_export_create` failing with status 403. That
  is precise and works at any time, whereas the portal check is a proxy and only
  unambiguous while backfill is still in progress.

## Export naming

Daily exports are `<prefix><cost_mgmt_suffix>-<billing-account-index>` and backfill
exports are `focus-backfill<cost_mgmt_suffix>-<index>-<YYYY>-<MM>`.

The index is **not** needed for uniqueness: each export lives at its own billing account
scope, so names cannot collide across accounts. It does two other jobs. It partitions
the storage container, because Cost Management uses the export name as a path segment
and every billing account delivers to the same container and root folder. It is also
the third-tier fallback for attributing a blob to a billing account, behind the in-data
`BillingAccountId` column and the `billingAccounts/{id}` path segment.

`extract_billing_account_from_blob_path` reads a fixed offset from the *start* of the
name, so **any deployment setting `cost_mgmt_suffix` shifts the index out of position
and the parse silently returns `None`**. Reading backwards from the end fixes it and
tolerates prefix and suffix changes.

## Two deployments in one tenant collide

`cost_mgmt_suffix` exists to separate multiple instances, but it is opt-in and defaults
to empty. Two instances that both leave it unset produce the *same* daily export name at
the *same* billing account scope, which is the same ARM resource: each apply overwrites
the other's `deliveryInfo`, pointing the shared export at its own storage account, and a
destroy of either deletes an export the other still needs. Backfill export names collide
the same way, and the S3 backfill locks are shared regardless, since they are keyed by
tenant.

## Terraform refactoring gotchas

Found while migrating `null_resource` to `terraform_data`:

- `moved` blocks cannot change resource type. The migration path is a `removed` block
  with `lifecycle { destroy = false }`, which forgets the old address without running
  its destroy-time provisioners. Without `destroy = false`, migrating
  `backfill_exports_cleanup_warning` fires its warning at every existing deployment.
- Terraform still installs a provider that only state references. Dropping
  `hashicorp/null` from `required_providers` in the same change works: it resolves and
  installs it for the one transition, then drops it from the lock file afterwards.
- tflint has `terraform_unused_required_providers` enabled by default, so a provider
  retained in `required_providers` "just in case" fails lint.
- The repo's plan-only tests must keep both `check` blocks inert, or the run fails with
  "check block assertion known after apply". `billing_reader_assignments` is pruned by
  `is_enterprise_customer = true`, which is preferable to `manage_role_assignments =
  false` if a check is ever added that fires in the externally-managed case.
