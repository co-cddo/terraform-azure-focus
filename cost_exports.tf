resource "azapi_resource" "daily_cost_export" {
  type      = "Microsoft.CostManagement/exports@2023-07-01-preview"
  name      = "focus-daily-cost-export"
  parent_id = var.report_scope
  location  = var.location
  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      exportDescription = "Focus Daily Cost Export"
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
  for_each = { for month in local.backfill_months : month => month }

  type      = "Microsoft.CostManagement/exports@2023-07-01-preview"
  name      = "focus-backfill-${each.value}"
  parent_id = var.report_scope
  location  = var.location
  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      exportDescription = "Focus Backfill Cost Export for ${each.value}"
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
          from = "${each.value}-01T00:00:00Z"
          to   = "${local.month_end_dates[each.value]}T23:59:59Z"
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

resource "azapi_resource" "utilization_export" {
  type      = "Microsoft.CostManagement/exports@2023-07-01-preview"
  name      = "utilization-export"
  parent_id = var.report_scope
  location  = var.location
  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      exportDescription = "Resource Utilization Export"
      definition = {
        type = "Usage"
        dataSet = {
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
      format = "Csv"
      deliveryInfo = {
        destination = {
          type           = "AzureBlob"
          resourceId     = azurerm_storage_account.cost_export.id
          container      = azapi_resource.utilization_container.name
          rootFolderPath = local.utilization_directory_name
        }
      }
      partitionData         = true
      dataOverwriteBehavior = "OverwritePreviousReport"
      compressionMode       = "gzip"
    }
  }
}