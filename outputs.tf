output "aws_app_client_id" {
  description = "The aws app client id"
  value       = azuread_application.aws_app.client_id
}

output "focus_export_name" {
  description = "The name of the FOCUS cost export"
  value       = azapi_resource.daily_cost_export.name
}

output "focus_container_name" {
  description = "The storage container name for FOCUS cost data"
  value       = azapi_resource.cost_export.name
}

output "utilization_export_name" {
  description = "The name of the cost utilization export"
  value       = azapi_resource.utilization_export.name
}

output "utilization_container_name" {
  description = "The storage container name for utilization data"
  value       = azapi_resource.utilization_container.name
}

output "carbon_export_name" {
  description = "The name of the carbon optimization export"
  value       = azapi_resource.carbon_export.name
}

output "carbon_container_name" {
  description = "The storage container name for carbon data"
  value       = azapi_resource.carbon_container.name
}
