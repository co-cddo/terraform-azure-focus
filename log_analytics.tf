resource "azurerm_log_analytics_workspace" "this" {
  count               = var.log_analytics_workspace_id == null ? 1 : 0
  name                = local.names.log_analytics_workspace
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}
