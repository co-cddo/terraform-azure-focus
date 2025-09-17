output "aws_app_client_id" {
  description = "The aws app client id"
  value       = azuread_application.aws_app.client_id
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

output "billing_account_ids" {
  description = "Billing account IDs configured for cost reporting"
  value       = var.billing_account_ids
}

output "report_scopes" {
  description = "Report scopes created for each billing account"
  value       = local.report_scopes
}

output "billing_accounts_map" {
  description = "Map of billing account indices to IDs and scopes"
  value       = local.billing_accounts_map
}
