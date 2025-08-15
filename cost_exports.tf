resource "azapi_resource" "daily_cost_export" {
  for_each = local.billing_accounts_map

  type      = "Microsoft.CostManagement/exports@2023-07-01-preview"
  name      = "focus-daily-cost-export-${each.key}"
  parent_id = each.value.scope
  location  = var.location
  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      exportDescription = "Focus Daily Cost Export for ${each.value.scope}"
      definition = {
        type = "FocusCost"
        dataSet = {
          configuration = {
            dataVersion = var.focus_dataset_version
          }
          granularity = "Daily"
        }
        timeframe = "MonthToDate"
      }
      schedule = {
        status     = "Active"
        recurrence = "Daily"
        recurrencePeriod = {
          from = time_static.recurrence.id
          to   = timeadd(time_static.recurrence.id, "${24 * 365 * 5}h")
        }
      }
      format = "Parquet"
      deliveryInfo = {
        destination = {
          type       = "AzureBlob"
          resourceId = azurerm_storage_account.cost_export.id
          container : azapi_resource.cost_export.name
          rootFolderPath : local.focus_directory_name
        }
      }
      partitionData         = true
      dataOverwriteBehavior = "OverwritePreviousReport"
      compressionMode       = "None"
    }
  }
}

# Create one-time backfill exports for historical data
resource "azapi_resource" "backfill_cost_exports" {
  for_each = {
    for combination in flatten([
      for account_idx, account in local.billing_accounts_map : [
        for month in local.backfill_months : {
          key   = "${account_idx}-${month}"
          scope = account.scope
          month = month
        }
      ]
    ]) : combination.key => combination
  }

  type      = "Microsoft.CostManagement/exports@2023-07-01-preview"
  name      = "focus-backfill-${each.value.key}"
  parent_id = each.value.scope
  location  = var.location
  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      exportDescription = "Focus Backfill Cost Export for ${each.value.month} on ${each.value.scope}"
      definition = {
        type = "FocusCost"
        dataSet = {
          configuration = {
            dataVersion = var.focus_dataset_version
          }
          granularity = "Daily"
        }
        timeframe = "Custom"
        timePeriod = {
          from = "${each.value.month}-01T00:00:00Z"
          to   = "${local.month_end_dates[each.value.month]}T23:59:59Z"
        }
      }
      schedule = {
        status = "Inactive"
      }
      format = "Parquet"
      deliveryInfo = {
        destination = {
          type       = "AzureBlob"
          resourceId = azurerm_storage_account.cost_export.id
          container : azapi_resource.cost_export.name
          rootFolderPath : local.focus_directory_name
        }
      }
      partitionData         = true
      dataOverwriteBehavior = "CreateNewReport"
      compressionMode       = "None"
    }
  }
}
