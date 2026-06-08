resource "azurerm_resource_group" "cost_export" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}
