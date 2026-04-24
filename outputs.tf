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

output "ea_billing_role_definition_ids" {
  description = "The set of roleDefinitionId - use each of these as input to the Enrollment Reader JSON body - must match the billing id in the URL"
  value       = [for v in var.billing_account_ids : "/providers/Microsoft.Billing/billingAccounts/${v}/billingRoleDefinitions/24f8edb6-1668-4659-b5e2-40bb5f3a7d7e"]
}

output "random_string_suffix" {
  description = "The random suffix appended to generated resource names"
  value       = random_string.unique.result
}

output "cost_export_storage_account_name" {
  description = "The name of the cost export storage account"
  value       = azurerm_storage_account.cost_export.name
}

output "deployment_storage_account_name" {
  description = "The name of the deployment storage account"
  value       = azurerm_storage_account.deployment.name
}

output "function_app_name" {
  description = "The name of the cost export function app"
  value       = azurerm_function_app_flex_consumption.cost_export.name
}

output "event_grid_system_topic_name" {
  description = "The name of the Event Grid system topic for storage events"
  value       = azurerm_eventgrid_system_topic.storage_events.name
}

output "event_grid_subscription_name" {
  description = "The name of the Event Grid subscription for blob created events"
  value       = azurerm_eventgrid_event_subscription.focus_blob_created.name
}

output "cost_export_storage_account_id" {
  description = "The resource id of the cost export storage account"
  value       = azurerm_storage_account.cost_export.id
}

output "deployment_storage_account_id" {
  description = "The resource id of the deployment storage account"
  value       = azurerm_storage_account.deployment.id
}

output "function_app_id" {
  description = "The resource id of the cost export function app"
  value       = azurerm_function_app_flex_consumption.cost_export.id
}

output "storage_private_endpoint_ip" {
  description = "The private IP address of the cost export storage blob private endpoint"
  value       = azurerm_private_endpoint.storage.private_service_connection[0].private_ip_address
}

output "storage_queue_private_endpoint_ip" {
  description = "The private IP address of the cost export storage queue private endpoint"
  value       = azurerm_private_endpoint.storage_queue.private_service_connection[0].private_ip_address
}

output "deployment_storage_private_endpoint_ip" {
  description = "The private IP address of the deployment storage blob private endpoint"
  value       = azurerm_private_endpoint.deployment.private_service_connection[0].private_ip_address
}

output "function_app_private_endpoint_ip" {
  description = "The private IP address of the function app private endpoint"
  value       = azurerm_private_endpoint.function_app.private_service_connection[0].private_ip_address
}

output "private_dns_zones" {
  description = "Effective private DNS zone configuration used by the module"
  value = {
    for zone, zone_id in local.effective_private_dns_zone_ids :
    zone => {
      id                = zone_id
      name              = local.effective_private_dns_zone_names[zone]
      resource_group    = local.effective_private_dns_zone_resource_group_names[zone]
      managed_by_module = local.manage_private_endpoint_dns && !var.use_existing_private_dns_zones
    }
  }
}
