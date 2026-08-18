resource "azurerm_private_endpoint" "storage" {
  count = var.enable_focus_exports ? 1 : 0

  name                = local.names.pe_storage_blob
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = local.names.psc_storage_blob
    private_connection_resource_id = azurerm_storage_account.cost_export[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = local.manage_private_endpoint_dns ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = [lookup(local.effective_private_dns_zone_ids, "blob", "")]
    }
  }
}

resource "azurerm_private_endpoint" "storage_queue" {
  count = var.enable_focus_exports ? 1 : 0

  name                = local.names.pe_storage_queue
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = local.names.psc_storage_queue
    private_connection_resource_id = azurerm_storage_account.cost_export[0].id
    subresource_names              = ["queue"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = local.manage_private_endpoint_dns ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = [lookup(local.effective_private_dns_zone_ids, "queue", "")]
    }
  }
}

resource "azurerm_private_endpoint" "deployment" {
  name                = local.names.pe_deployment_blob
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = local.names.psc_deployment_blob
    private_connection_resource_id = azurerm_storage_account.deployment.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = local.manage_private_endpoint_dns ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = [lookup(local.effective_private_dns_zone_ids, "blob", "")]
    }
  }
}

resource "azurerm_private_endpoint" "function_app" {
  name                = local.names.pe_function_app
  location            = local.resource_group_location
  resource_group_name = local.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = local.names.psc_function_app
    private_connection_resource_id = azurerm_function_app_flex_consumption.cost_export.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = local.manage_private_endpoint_dns ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = [lookup(local.effective_private_dns_zone_ids, "sites", "")]
    }
  }
}
