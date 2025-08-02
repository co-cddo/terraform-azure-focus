output "existing_resource_group_name" {
  description = "Name of the existing resource group"
  value       = azurerm_resource_group.existing.name
}

output "existing_vnet_name" {
  description = "Name of the existing virtual network"
  value       = azurerm_virtual_network.existing.name
}

output "default_subnet_id" {
  description = "ID of the default subnet"
  value       = azurerm_subnet.default.id
}

output "functionapp_subnet_id" {
  description = "ID of the function app subnet"
  value       = azurerm_subnet.functionapp.id
}

output "cost_forwarding_outputs" {
  description = "Outputs from the cost forwarding module"
  value       = module.cost_forwarding
}