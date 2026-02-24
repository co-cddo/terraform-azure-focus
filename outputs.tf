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

output "current_principal_type" {
  description = "Principal type of the current Azure client (ServicePrincipal or User)"
  value       = var.current_principal_type
}

output "publish_code_command" {
  description = "Publish code command for debugging"
  value       = local.publish_code_command
}

output "cost_export_app_principal_id" {
  description = "The principal id of the cost export app - use this to assign Enrollment Reader role"
  value       = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
}

output "tenant_id" {
  description = "The tenant id - use this to assign the Enrollment Reader role"
  value       = data.azurerm_client_config.current.tenant_id
}

output "EA_billing_role_definition_ids" {
  description = "The set of roleDefinitionId - use each of these as input to the Enrollment Reader JSON body - must match the billing id in the URL"
  value       = [for v in var.billing_account_ids: "/providers/Microsoft.Billing/billingAccounts/${v}/billingRoleDefinitions/24f8edb6-1668-4659-b5e2-40bb5f3a7d7e"]
}
