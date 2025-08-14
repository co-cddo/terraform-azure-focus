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

output "recommendations_export_name" {
  description = "The name of the Azure Advisor recommendations export (timer-triggered function)"
  value       = "AdvisorRecommendationsExporter"
}

output "carbon_export_name" {
  description = "The name of the carbon optimization export (timer-triggered function)"
  value       = "CarbonEmissionsExporter"
}

output "carbon_container_name" {
  description = "The storage container name for carbon data (not used - carbon data goes directly to S3)"
  value       = null
}

output "backfill_export_names" {
  description = "The names of the backfill FOCUS cost exports for historical data"
  value       = { for k, v in azapi_resource.backfill_cost_exports : k => v.name }
}
