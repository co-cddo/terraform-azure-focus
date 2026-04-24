resource "azurerm_private_dns_zone" "blob" {
  count               = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.cost_export.name
  tags                = var.tags
}

# Kept for backward compatibility with existing deployments that already manage these zones via this module.
resource "azurerm_private_dns_zone" "file" {
  count               = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.cost_export.name
  tags                = var.tags
}

# Kept for backward compatibility with existing deployments that already manage these zones via this module.
resource "azurerm_private_dns_zone" "table" {
  count               = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                = "privatelink.table.core.windows.net"
  resource_group_name = azurerm_resource_group.cost_export.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "queue" {
  count               = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = azurerm_resource_group.cost_export.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "sites" {
  count               = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.cost_export.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count                 = local.manage_private_endpoint_dns ? 1 : 0
  name                  = "blob-dns-link"
  resource_group_name   = local.effective_private_dns_zone_resource_group_names.blob
  private_dns_zone_name = local.effective_private_dns_zone_names.blob
  virtual_network_id    = data.azurerm_virtual_network.existing.id
  tags                  = var.tags
}

# Kept for backward compatibility with existing deployments that already manage these links via this module.
resource "azurerm_private_dns_zone_virtual_network_link" "file" {
  count                 = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                  = "file-dns-link"
  resource_group_name   = azurerm_resource_group.cost_export.name
  private_dns_zone_name = azurerm_private_dns_zone.file[0].name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
  tags                  = var.tags
}

# Kept for backward compatibility with existing deployments that already manage these links via this module.
resource "azurerm_private_dns_zone_virtual_network_link" "table" {
  count                 = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                  = "table-dns-link"
  resource_group_name   = azurerm_resource_group.cost_export.name
  private_dns_zone_name = azurerm_private_dns_zone.table[0].name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "queue" {
  count                 = local.manage_private_endpoint_dns ? 1 : 0
  name                  = "queue-dns-link"
  resource_group_name   = local.effective_private_dns_zone_resource_group_names.queue
  private_dns_zone_name = local.effective_private_dns_zone_names.queue
  virtual_network_id    = data.azurerm_virtual_network.existing.id
  tags                  = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sites" {
  count                 = local.manage_private_endpoint_dns ? 1 : 0
  name                  = "sites-dns-link"
  resource_group_name   = local.effective_private_dns_zone_resource_group_names.sites
  private_dns_zone_name = local.effective_private_dns_zone_names.sites
  virtual_network_id    = data.azurerm_virtual_network.existing.id
  tags                  = var.tags
}

resource "azurerm_private_dns_a_record" "storage" {
  count               = local.manage_private_endpoint_dns ? 1 : 0
  name                = azurerm_storage_account.cost_export.name
  zone_name           = local.effective_private_dns_zone_names.blob
  resource_group_name = local.effective_private_dns_zone_resource_group_names.blob
  ttl                 = var.private_dns_a_record_ttl
  records             = [azurerm_private_endpoint.storage.private_service_connection[0].private_ip_address]
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "storage_queue" {
  count               = local.manage_private_endpoint_dns ? 1 : 0
  name                = azurerm_storage_account.cost_export.name
  zone_name           = local.effective_private_dns_zone_names.queue
  resource_group_name = local.effective_private_dns_zone_resource_group_names.queue
  ttl                 = var.private_dns_a_record_ttl
  records             = [azurerm_private_endpoint.storage_queue.private_service_connection[0].private_ip_address]
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "deployment" {
  count               = local.manage_private_endpoint_dns ? 1 : 0
  name                = azurerm_storage_account.deployment.name
  zone_name           = local.effective_private_dns_zone_names.blob
  resource_group_name = local.effective_private_dns_zone_resource_group_names.blob
  ttl                 = var.private_dns_a_record_ttl
  records             = [azurerm_private_endpoint.deployment.private_service_connection[0].private_ip_address]
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "function_app" {
  count               = local.manage_private_endpoint_dns ? 1 : 0
  name                = azurerm_function_app_flex_consumption.cost_export.name
  zone_name           = local.effective_private_dns_zone_names.sites
  resource_group_name = local.effective_private_dns_zone_resource_group_names.sites
  ttl                 = var.private_dns_a_record_ttl
  records             = [azurerm_private_endpoint.function_app.private_service_connection[0].private_ip_address]
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "function_app_kudu" {
  count               = local.manage_private_endpoint_dns ? 1 : 0
  name                = "${azurerm_function_app_flex_consumption.cost_export.name}.scm"
  zone_name           = local.effective_private_dns_zone_names.sites
  resource_group_name = local.effective_private_dns_zone_resource_group_names.sites
  ttl                 = var.private_dns_a_record_ttl
  records             = [azurerm_private_endpoint.function_app.private_service_connection[0].private_ip_address]
  tags                = var.tags
}
