# trivy:ignore:AVD-AZU-0057 Request logging is handled via azurerm_monitor_diagnostic_setting (Log Analytics) below, not the legacy Storage Analytics queue_properties block.
# trivy:ignore:AZU-0058 LRS is sufficient for now
resource "azurerm_storage_account" "cost_export" {
  # checkov:skip=CKV_AZURE_206:LRS is sufficient for now - this is a temporary storage location
  # checkov:skip=CKV_AZURE_33:Table and file storage services are not in use on this account
  # checkov:skip=CKV2_AZURE_38:We don't need soft delete since this account is neither source nor destination for cost data
  # checkov:skip=CKV2_AZURE_1:Platform managed key is sufficient for this storage account
  # checkov:skip=CKV_AZURE_43:Name is resolved via local.names; format is enforced by the custom_resource_names variable validation
  name                     = local.names.storage_account_cost_export
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
  min_tls_version                   = "TLS1_2"
  infrastructure_encryption_enabled = true

  sas_policy {
    expiration_period = "01.00:00:00"
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  # Key auth is disabled above, so the provider's create-time data-plane poll uses Entra ID
  # (storage_use_azuread). Wait for the deployer's data-plane RBAC to propagate before creating
  # the account, otherwise the poll fails with AuthorizationPermissionMismatch (403). See rbac.tf.
  depends_on = [time_sleep.wait_for_deployer_rbac]
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
  # checkov:skip=CKV_AZURE_59:Debugging deployment failure...
  # checkov:skip=CKV2_AZURE_38:We don't need soft delete since this account is neither source nor destination for cost data
  # checkov:skip=CKV_AZURE_33:Table and file storage services are not in use on this account
  # checkov:skip=CKV_AZURE_206:LRS is sufficient for now
  # checkov:skip=CKV2_AZURE_1:Platform managed key is sufficient for this storage account
  # checkov:skip=CKV2_AZURE_40:Shared access keys remain enabled here: the Flex Consumption function app uses this
  # account for its deployment package via storage_access_key, which cannot use managed identity
  # yet due to a provider bug. See function_app.tf TODO:
  # https://github.com/hashicorp/terraform-provider-azurerm/issues/29993
  # checkov:skip=CKV_AZURE_43:Name is resolved via local.names; format is enforced by the custom_resource_names variable validation

  name                     = local.names.storage_account_deployment
  resource_group_name      = azurerm_resource_group.cost_export.name
  location                 = azurerm_resource_group.cost_export.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true
  tags                     = var.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  public_network_access_enabled     = true
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = true
  local_user_enabled                = false
  min_tls_version                   = "TLS1_2"
  infrastructure_encryption_enabled = true

  sas_policy {
    expiration_period = "01.00:00:00"
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

# The Flex Consumption host uses this account's queue service for internal operations (e.g.
# timer singleton leases); surfacing its operations helps troubleshoot host-level trigger
# issues (e.g. why a timer didn't fire). Blob (host singleton leases/locks) is already
# covered by deployment_blob above; table and file services are not in use on this account.
resource "azurerm_monitor_diagnostic_setting" "deployment_queue" {
  name                       = "diag-queue"
  target_resource_id         = "${azurerm_storage_account.deployment.id}/queueServices/default"
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
