resource "azurerm_resource_group" "cost_export" {
  count    = var.existing_resource_group_name != null ? 0 : 1
  name     = local.names.resource_group
  location = var.location
  tags     = var.tags
}
