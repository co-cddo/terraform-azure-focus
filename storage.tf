# trivy:ignore:AVD-AZU-0057 Request logging is handled via azurerm_monitor_diagnostic_setting (Log Analytics) below, not the legacy Storage Analytics queue_properties block.
# trivy:ignore:AZU-0058 LRS is sufficient for now
resource "azurerm_storage_account" "cost_export" {
  # checkov:skip=CKV_AZURE_206:LRS is sufficient for now - this is a temporary storage location
  # checkov:skip=CKV_AZURE_33:Table and file storage services are not in use on this account
  # checkov:skip=CKV2_AZURE_38:We don't need soft delete since this account is neither source nor destination for cost data
  # checkov:skip=CKV2_AZURE_1:Platform managed key is sufficient for this storage account
  name                     = "stcostexport${random_string.unique.result}"
  resource_group_name      = azurerm_resource_group.cost_export.name
  location                 = azurerm_resource_group.cost_export.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true
  tags                     = var.tags

  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = false
  shared_access_key_enabled         = false
  local_user_enabled                = false
  min_tls_version                   = "TLS1_3"
  infrastructure_encryption_enabled = true

  sas_policy {
    expiration_period = "01.00:00:00"
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

resource "azapi_resource" "cost_export" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01"
  name      = "cost-exports"
  parent_id = "${azurerm_storage_account.cost_export.id}/blobServices/default"
  body = {
    properties = {
      metadata     = {}
      publicAccess = "None"
    }
  }
}

resource "azapi_resource" "cost_data_queue" {
  type      = "Microsoft.Storage/storageAccounts/queueServices/queues@2022-09-01"
  name      = "costdata"
  parent_id = "${azurerm_storage_account.cost_export.id}/queueServices/default"
}

# trivy:ignore:AVD-AZU-0057 Request logging is handled via azurerm_monitor_diagnostic_setting (Log Analytics) below, not the legacy Storage Analytics queue_properties block.
# trivy:ignore:AZU-0058 LRS is sufficient for now
resource "azurerm_storage_account" "deployment" {
  # checkov:skip=CKV2_AZURE_38:We don't need soft delete since this account is neither source nor destination for cost data
  # checkov:skip=CKV_AZURE_33:Table and file storage services are not in use on this account
  # checkov:skip=CKV_AZURE_206:LRS is sufficient for now
  # checkov:skip=CKV2_AZURE_1:Platform managed key is sufficient for this storage account
  # checkov:skip=CKV2_AZURE_40:Shared access keys remain enabled here: the Flex Consumption function app uses this
  # account for its deployment package (storage_access_key) and AzureWebJobsStorage, neither
  # of which can use managed identity yet due to a provider bug. See function_app.tf TODO:
  # https://github.com/hashicorp/terraform-provider-azurerm/issues/29993

  name                     = "stcostexdply${random_string.unique.result}"
  resource_group_name      = azurerm_resource_group.cost_export.name
  location                 = azurerm_resource_group.cost_export.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true
  tags                     = var.tags

  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = false
  shared_access_key_enabled         = true
  local_user_enabled                = false
  min_tls_version                   = "TLS1_3"
  infrastructure_encryption_enabled = true

  sas_policy {
    expiration_period = "01.00:00:00"
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

resource "azapi_resource" "deployment" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01"
  name      = "cost-exports-deployment"
  parent_id = "${azurerm_storage_account.deployment.id}/blobServices/default"
  body = {
    properties = {
      metadata     = {}
      publicAccess = "None"
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "cost_export_blob" {
  name                       = "diag-blob"
  target_resource_id         = "${azurerm_storage_account.cost_export.id}/blobServices/default"
  log_analytics_workspace_id = local.effective_log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_monitor_diagnostic_setting" "cost_export_queue" {
  name                       = "diag-queue"
  target_resource_id         = "${azurerm_storage_account.cost_export.id}/queueServices/default"
  log_analytics_workspace_id = local.effective_log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }
}

resource "azurerm_monitor_diagnostic_setting" "deployment_blob" {
  name                       = "diag-blob"
  target_resource_id         = "${azurerm_storage_account.deployment.id}/blobServices/default"
  log_analytics_workspace_id = local.effective_log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }
}
