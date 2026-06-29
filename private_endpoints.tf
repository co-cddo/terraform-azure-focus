resource "azurerm_private_endpoint" "storage" {
  name                = local.names.pe_storage_blob
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = local.names.psc_storage_blob
    private_connection_resource_id = azurerm_storage_account.cost_export.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

resource "azurerm_private_endpoint" "storage_queue" {
  name                = local.names.pe_storage_queue
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = local.names.psc_storage_queue
    private_connection_resource_id = azurerm_storage_account.cost_export.id
    subresource_names              = ["queue"]
    is_manual_connection           = false
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

resource "azurerm_private_endpoint" "deployment" {
  name                = local.names.pe_deployment_blob
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = local.names.psc_deployment_blob
    private_connection_resource_id = azurerm_storage_account.deployment.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

resource "azurerm_private_endpoint" "function_app" {
  name                = local.names.pe_function_app
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = local.names.psc_function_app
    private_connection_resource_id = azurerm_function_app_flex_consumption.cost_export.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}
