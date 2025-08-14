resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.cost_export.name
}

resource "azurerm_private_dns_zone" "file" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.cost_export.name
}

resource "azurerm_private_dns_zone" "table" {
  name                = "privatelink.table.core.windows.net"
  resource_group_name = azurerm_resource_group.cost_export.name
}

resource "azurerm_private_dns_zone" "queue" {
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = azurerm_resource_group.cost_export.name
}

resource "azurerm_private_dns_zone" "sites" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.cost_export.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "blob-dns-link"
  resource_group_name   = azurerm_resource_group.cost_export.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "file" {
  name                  = "file-dns-link"
  resource_group_name   = azurerm_resource_group.cost_export.name
  private_dns_zone_name = azurerm_private_dns_zone.file.name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "table" {
  name                  = "table-dns-link"
  resource_group_name   = azurerm_resource_group.cost_export.name
  private_dns_zone_name = azurerm_private_dns_zone.table.name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "queue" {
  name                  = "queue-dns-link"
  resource_group_name   = azurerm_resource_group.cost_export.name
  private_dns_zone_name = azurerm_private_dns_zone.queue.name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "sites" {
  name                  = "sites-dns-link"
  resource_group_name   = azurerm_resource_group.cost_export.name
  private_dns_zone_name = azurerm_private_dns_zone.sites.name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
}

resource "azurerm_private_dns_a_record" "storage" {
  name                = azurerm_storage_account.cost_export.name
  zone_name           = azurerm_private_dns_zone.blob.name
  resource_group_name = azurerm_resource_group.cost_export.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage.private_service_connection[0].private_ip_address]
}

resource "azurerm_private_dns_a_record" "storage_queue" {
  name                = azurerm_storage_account.cost_export.name
  zone_name           = azurerm_private_dns_zone.queue.name
  resource_group_name = azurerm_resource_group.cost_export.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage_queue.private_service_connection[0].private_ip_address]
}

resource "azurerm_private_dns_a_record" "deployment" {
  name                = azurerm_storage_account.deployment.name
  zone_name           = azurerm_private_dns_zone.blob.name
  resource_group_name = azurerm_resource_group.cost_export.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.deployment.private_service_connection[0].private_ip_address]
}

resource "azurerm_private_dns_a_record" "function_app" {
  name                = azurerm_function_app_flex_consumption.cost_export.name
  zone_name           = azurerm_private_dns_zone.sites.name
  resource_group_name = azurerm_resource_group.cost_export.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.function_app.private_service_connection[0].private_ip_address]
}