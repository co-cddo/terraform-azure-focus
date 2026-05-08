resource "azurerm_private_endpoint" "storage" {
  name                = "pe-storage-cost-export"
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-storage-cost-export"
    private_connection_resource_id = azurerm_storage_account.cost_export.id
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
  name                = "pe-storage-queue-cost-export"
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-storage-queue-cost-export"
    private_connection_resource_id = azurerm_storage_account.cost_export.id
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
  name                = "pe-storage-cost-export-deployment"
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-storage-cost-export-deployment"
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
  name                = "pe-func-cost-export"
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-func-cost-export"
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
