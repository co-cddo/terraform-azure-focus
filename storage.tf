resource "azurerm_storage_account" "cost_export" {
  name                     = "stcostexport${random_string.unique.result}"
  resource_group_name      = azurerm_resource_group.cost_export.name
  location                 = azurerm_resource_group.cost_export.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true

  public_network_access_enabled = false

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

resource "azurerm_storage_account" "deployment" {
  name                     = "stcostexdply${random_string.unique.result}"
  resource_group_name      = azurerm_resource_group.cost_export.name
  location                 = azurerm_resource_group.cost_export.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true

  public_network_access_enabled = false

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

