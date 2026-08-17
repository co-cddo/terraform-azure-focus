resource "time_static" "recurrence" {
  count = var.enable_focus_exports ? 1 : 0
}
resource "azapi_resource" "daily_cost_export" {
  for_each = local.billing_accounts_map

  type      = "Microsoft.CostManagement/exports@2025-03-01"
  name      = "${local.names.cost_export_prefix}${local.cost_mgmt_suffix}-${each.key}"
  parent_id = each.value.scope
  location  = var.location
  identity {
    type = "SystemAssigned"
  }

  response_export_values = ["identity.principalId"]

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
          from = time_static.recurrence[0].id
          to   = timeadd(time_static.recurrence[0].id, "${24 * 366 * var.cost_export_daily_schedule_to_years}h")
        }
      }
      format = "Parquet"
      deliveryInfo = {
        destination = {
          type       = "AzureBlob"
          resourceId = azurerm_storage_account.cost_export[0].id
          container : azapi_resource.cost_export[0].name
          rootFolderPath : local.focus_directory_name
        }
      }
      partitionData         = true
      dataOverwriteBehavior = "OverwritePreviousReport"
      compressionMode       = "None"
    }
  }
}
