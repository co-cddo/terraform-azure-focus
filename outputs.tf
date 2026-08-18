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

# Surfaces the remediation script when billing role assignments are missing. For EA customers
# this always fires (Terraform cannot create EA billing roles). For MCA customers it fires only
# when the check block in rbac.tf detects a missing assignment.
output "billing_role_assignment_manual_action_required" {
  description = "Populated when the function app's managed identity is missing a billing role assignment. For EA customers this always requires manual action; for MCA customers it appears only when the billing_reader_assignments check detects a gap."
  value = var.is_enterprise_customer ? join("\n", concat(
    [
      "ACTION REQUIRED (Enterprise Agreement customer): assign the 'EnrollmentReader' billing role to the cost-export function app's managed identity MANUALLY.",
      "Terraform and the deploying service principal cannot do this - it requires Enterprise Administrator privileges.",
      "Have an Enterprise Administrator run scripts/NewBillingRoleAssignment.ps1 (bundled with this module), once per billing account; the -IsEnterpriseAgreement switch is required:",
    ],
    [for v in var.billing_account_ids : "  ./scripts/NewBillingRoleAssignment.ps1 -BillingAccountID '${v}' -ServicePrincipalObjectID '${azurerm_user_assigned_identity.cost_export.principal_id}' -RoleDefinitionID '24f8edb6-1668-4659-b5e2-40bb5f3a7d7e' -IsEnterpriseAgreement"],
    ["See https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/assign-roles-azure-service-principals"],
    )) : length(local.billing_accounts_missing_reader) > 0 ? join("\n", concat(
    [
      "ACTION REQUIRED (Microsoft Customer Agreement customer): the function app's managed identity is missing a billing role assignment on the following billing account(s).",
      "This can happen when an assignment is removed out-of-band or when the managed identity is rebuilt and the one-shot grant does not re-fire (see the module README for details).",
      "Run scripts/NewBillingRoleAssignment.ps1 (bundled with this module) for each:",
    ],
    [for v in local.billing_accounts_missing_reader : "  ./scripts/NewBillingRoleAssignment.ps1 -BillingAccountID '${v}' -ServicePrincipalObjectID '${azurerm_user_assigned_identity.cost_export.principal_id}' -RoleDefinitionID '50000000-aaaa-bbbb-cccc-100000000002'"],
  )) : ""
}

# Fires whenever bringing your own app registration (existing_entra_application_client_id is set).
# The idempotent ConfigureExistingAppRegistration.ps1 script ensures the app role, identifier URI,
# and app role assignment are all correctly configured. Empty when the module creates the app itself.
output "entra_app_role_assignment_manual_action_required" {
  description = "Populated when bringing your own app registration (existing_entra_application_client_id). Instructs your Entra team to run ConfigureExistingAppRegistration.ps1 to ensure the app role, identifier URI, and app role assignment are configured. The script is idempotent. Empty when the module creates the app registration itself."
  value = local.create_entra_app ? "" : join("\n", [
    "Requires an Entra admin with Directory.Read.All + AppRoleAssignment.ReadWrite.All + Application.ReadWrite.All.",
    "",
    "Run scripts/ConfigureExistingAppRegistration.ps1 (bundled with this module) — it is idempotent and ensures:",
    "  - The 'AssumeRoleWithWebIdentity' app role exists on the app registration",
    "  - The app role is assigned to the function app's managed identity",
    "  - The identifier URI is set correctly",
    "",
    "  ./scripts/ConfigureExistingAppRegistration.ps1 -ManagedIdentityClientID '${azurerm_user_assigned_identity.cost_export.client_id}' -AppRegistrationClientID '${local.entra_app_client_id}'",
    "",
    "If you set the cost_mgmt_suffix variable in your module configuration, pass it here too:",
    "  -CostManagementSuffix '<your-suffix>'",
  ])
}

output "azapi_resource_action_add_role_assignment_output" {
  description = "The billing account role assignment outputs from azapi_resource_action, keyed by billing account ID"
  value       = { for k, v in azapi_resource_action.add_role_assignment : k => v.output }
}

output "random_string_suffix" {
  description = "The random suffix appended to generated resource names"
  value       = random_string.unique.result
}

output "resource_names" {
  description = "The resolved resource names (defaults or custom_resource_names overrides)"
  value       = local.names
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

output "log_analytics_workspace_id" {
  description = "The resource ID of the Log Analytics workspace used for diagnostic settings"
  value       = local.effective_log_analytics_workspace_id
}
