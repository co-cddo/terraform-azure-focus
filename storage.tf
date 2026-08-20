# trivy:ignore:AVD-AZU-0057 Request logging is handled via azurerm_monitor_diagnostic_setting (Log Analytics) below, not the legacy Storage Analytics queue_properties block.
# trivy:ignore:AZU-0058 LRS is sufficient for now
resource "azurerm_storage_account" "cost_export" {
  count = var.enable_focus_exports ? 1 : 0
  # checkov:skip=CKV_AZURE_206:LRS is sufficient for now - this is a temporary storage location
  # checkov:skip=CKV_AZURE_33:Table and file storage services are not in use on this account
  # checkov:skip=CKV2_AZURE_38:We don't need soft delete since this account is neither source nor destination for cost data
  # checkov:skip=CKV2_AZURE_1:Platform managed key is sufficient for this storage account
  # checkov:skip=CKV_AZURE_43:Name is resolved via local.names; format is enforced by the custom_resource_names variable validation
  # checkov:skip=CKV2_AZURE_33:Private endpoint is configured via azurerm_private_endpoint.storage[0]; Checkov cannot trace the relationship through count-indexed resources
  name                     = local.names.storage_account_cost_export
  resource_group_name      = local.resource_group_name
  location                 = local.resource_group_location
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
  count = var.enable_focus_exports ? 1 : 0

  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01"
  name      = "cost-exports"
  parent_id = "${azurerm_storage_account.cost_export[0].id}/blobServices/default"
  body = {
    properties = {
      metadata     = {}
      publicAccess = "None"
    }
  }
}

resource "azapi_resource" "cost_data_queue" {
  count = var.enable_focus_exports ? 1 : 0

  type      = "Microsoft.Storage/storageAccounts/queueServices/queues@2022-09-01"
  name      = "costdata"
  parent_id = "${azurerm_storage_account.cost_export[0].id}/queueServices/default"
}

# trivy:ignore:AVD-AZU-0057 Request logging is handled via azurerm_monitor_diagnostic_setting (Log Analytics) below, not the legacy Storage Analytics queue_properties block.
# trivy:ignore:AZU-0058 LRS is sufficient for now
resource "azurerm_storage_account" "deployment" {
  # checkov:skip=CKV2_AZURE_38:We don't need soft delete since this account is neither source nor destination for cost data
  # checkov:skip=CKV_AZURE_33:Table and file storage services are not in use on this account
  # checkov:skip=CKV_AZURE_206:LRS is sufficient for now
  # checkov:skip=CKV2_AZURE_1:Platform managed key is sufficient for this storage account
  # checkov:skip=CKV_AZURE_43:Name is resolved via local.names; format is enforced by the custom_resource_names variable validation
  # checkov:skip=CKV_AZURE_59:Public access is conditionally enabled only when BYO DNS zones are not linked to the VNet and function code publishing is required

  name                     = local.names.storage_account_deployment
  resource_group_name      = local.resource_group_name
  location                 = local.resource_group_location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true
  tags                     = var.tags

  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = local.deployment_storage_allow_public_access
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

  lifecycle {
    # public_network_access_enabled here is only the create-time state (open in the BYO-DNS-resolver
    # scenario so the provider's create-time data-plane read can reach the account). Thereafter access
    # is toggled out-of-band around the code publish by the null_resources in function_app.tf - opened
    # before publish, closed after. Ignoring the attribute stops that toggling from showing as
    # perpetual drift (a false -> true diff re-opening access on every plan).
    ignore_changes = [public_network_access_enabled]
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
  count = var.enable_focus_exports ? 1 : 0

  name                       = local.names.diag_cost_export_blob
  target_resource_id         = "${azurerm_storage_account.cost_export[0].id}/blobServices/default"
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
  count = var.enable_focus_exports ? 1 : 0

  name                       = local.names.diag_cost_export_queue
  target_resource_id         = "${azurerm_storage_account.cost_export[0].id}/queueServices/default"
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
  name                       = local.names.diag_deployment_blob
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
  name                       = local.names.diag_deployment_queue
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
