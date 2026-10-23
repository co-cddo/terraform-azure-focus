resource "azurerm_private_dns_zone" "blob" {
  count               = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

# Kept for backward compatibility with existing deployments that already manage these zones via this module.
resource "azurerm_private_dns_zone" "file" {
  count               = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                = "privatelink.file.core.windows.net"
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

# Kept for backward compatibility with existing deployments that already manage these zones via this module.
resource "azurerm_private_dns_zone" "table" {
  count               = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                = "privatelink.table.core.windows.net"
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "queue" {
  count               = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone" "sites" {
  count               = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                = "privatelink.azurewebsites.net"
  resource_group_name = local.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  count               = local.manage_private_endpoint_dns && (!var.use_existing_private_dns_zones || var.link_existing_private_dns_zones_to_vnet) ? 1 : 0
  name                = "blob-dns-link"
  private_dns_zone_id = local.effective_private_dns_zone_ids.blob
  virtual_network_id  = local.virtual_network_id
  tags                = var.tags
}

# Kept for backward compatibility with existing deployments that already manage these links via this module.
resource "azurerm_private_dns_zone_virtual_network_link" "file" {
  count               = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                = "file-dns-link"
  private_dns_zone_id = azurerm_private_dns_zone.file[0].id
  virtual_network_id  = local.virtual_network_id
  tags                = var.tags
}

# Kept for backward compatibility with existing deployments that already manage these links via this module.
resource "azurerm_private_dns_zone_virtual_network_link" "table" {
  count               = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones ? 1 : 0
  name                = "table-dns-link"
  private_dns_zone_id = azurerm_private_dns_zone.table[0].id
  virtual_network_id  = local.virtual_network_id
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "queue" {
  count               = local.manage_private_endpoint_dns && (!var.use_existing_private_dns_zones || var.link_existing_private_dns_zones_to_vnet) ? 1 : 0
  name                = "queue-dns-link"
  private_dns_zone_id = local.effective_private_dns_zone_ids.queue
  virtual_network_id  = local.virtual_network_id
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "sites" {
  count               = local.manage_private_endpoint_dns && (!var.use_existing_private_dns_zones || var.link_existing_private_dns_zones_to_vnet) ? 1 : 0
  name                = "sites-dns-link"
  private_dns_zone_id = local.effective_private_dns_zone_ids.sites
  virtual_network_id  = local.virtual_network_id
  tags                = var.tags
}

# A records were previously managed manually by this module. They are now registered
# automatically by the private_dns_zone_group attached to each private endpoint.
# The removed blocks below instruct Terraform to drop these resources from state
# without issuing a DELETE in Azure, so existing records are preserved in place.
removed {
  from = azurerm_private_dns_a_record.storage
  lifecycle { destroy = false }
}

removed {
  from = azurerm_private_dns_a_record.storage_queue
  lifecycle { destroy = false }
}

removed {
  from = azurerm_private_dns_a_record.deployment
  lifecycle { destroy = false }
}

removed {
  from = azurerm_private_dns_a_record.function_app
  lifecycle { destroy = false }
}

removed {
  from = azurerm_private_dns_a_record.function_app_kudu
  lifecycle { destroy = false }
}
