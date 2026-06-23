output "aws_app_client_id" {
  description = "The aws app client id"
  value       = local.entra_app_client_id
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
  value       = azurerm_user_assigned_identity.cost_export.principal_id
}

output "tenant_id" {
  description = "The tenant id - use this to assign the Enrollment Reader role"
  value       = data.azurerm_client_config.current.tenant_id
}

output "ea_billing_role_definition_ids" {
  description = "The set of roleDefinitionId - use each of these as input to the Enrollment Reader JSON body - must match the billing id in the URL"
  value       = [for v in var.billing_account_ids : "/providers/Microsoft.Billing/billingAccounts/${v}/billingRoleDefinitions/24f8edb6-1668-4659-b5e2-40bb5f3a7d7e"]
}

# Enterprise Agreement billing role assignments cannot be created by Terraform or the deploying
# service principal - they require Enterprise Administrator privileges (see the commented-out
# azapi block in rbac.tf). This output is empty for MCA customers (where "Billing account reader"
# is assigned automatically) and, for EA customers, prints the manual action plus the IDs needed
# to perform it - so it stands out in terraform apply / CI output.
output "enterprise_billing_manual_action_required" {
  description = "Enterprise Agreement customers only: the EnrollmentReader billing role must be assigned to the function app's managed identity MANUALLY. Empty for Microsoft Customer Agreement customers."
  value = var.is_enterprise_customer ? join("\n", concat(
    [
      "ACTION REQUIRED (Enterprise Agreement customer): assign the 'EnrollmentReader' billing role to the cost-export function app's managed identity MANUALLY.",
      "Terraform and the deploying service principal cannot do this - it requires Enterprise Administrator privileges.",
      "  Function app managed identity (principal/object) ID: ${azurerm_user_assigned_identity.cost_export.principal_id}",
      "  Tenant ID: ${data.azurerm_client_config.current.tenant_id}",
      "  Role definition ID(s) (one per billing account):",
    ],
    [for v in var.billing_account_ids : "    /providers/Microsoft.Billing/billingAccounts/${v}/billingRoleDefinitions/24f8edb6-1668-4659-b5e2-40bb5f3a7d7e"],
    ["See https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/assign-roles-azure-service-principals"],
  )) : ""
}

# When manage_entra_app_role_assignment = false (strict separation of duties), the module does not
# create the binding between the function app's managed identity and the AWS-federation app role -
# the deploying principal is assumed to have no directory-write privileges. This output prints the
# details the Entra team needs to create that app role assignment out-of-band. Empty otherwise.
output "entra_app_role_assignment_manual_action_required" {
  description = "Strict separation of duties only (manage_entra_app_role_assignment = false): the 'AssumeRoleWithWebIdentity' app role must be assigned to the function app's managed identity MANUALLY by your Entra team. Empty when the module manages the binding."
  value = var.manage_entra_app_role_assignment ? "" : join("\n", [
    "ACTION REQUIRED (separation of duties): assign the 'AssumeRoleWithWebIdentity' app role of the AWS-federation Entra app to the cost-export function app's managed identity MANUALLY.",
    "The deploying principal has no directory-write privileges (manage_entra_app_role_assignment = false), so Terraform cannot create this binding.",
    "  App registration client ID: ${local.entra_app_client_id}",
    "  App role value: AssumeRoleWithWebIdentity",
    "  Function app managed identity (principal/object) ID to assign it to: ${azurerm_user_assigned_identity.cost_export.principal_id}",
    "See https://aws.amazon.com/blogs/security/how-to-access-aws-resources-from-microsoft-entra-id-tenants-using-aws-security-token-service/",
  ])
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

output "log_analytics_workspace_id" {
  description = "The resource ID of the Log Analytics workspace used for diagnostic settings"
  value       = local.effective_log_analytics_workspace_id
}
