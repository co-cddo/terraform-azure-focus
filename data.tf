data "azurerm_client_config" "current" {}

data "azuread_service_principal" "plan" {
  count     = var.current_principal_type == "ServicePrincipal" ? 1 : 0
  object_id = data.azurerm_client_config.current.object_id
}

data "azuread_service_principal" "apply" {
  count        = var.current_principal_type == "ServicePrincipal" ? 1 : 0
  display_name = replace(data.azuread_service_principal.plan[0].display_name, "plan", "apply")
}

data "azurerm_resource_group" "existing" {
  count = var.existing_resource_group_name != null ? 1 : 0
  name  = var.existing_resource_group_name
}

data "azurerm_virtual_network" "existing" {
  name                = var.virtual_network_name
  resource_group_name = var.virtual_network_resource_group_name
}

data "archive_file" "function" {
  type        = "zip"
  source_dir  = "${path.module}/src/cost_export"
  output_path = "${path.module}/cost_export.zip"

  excludes = [
    "__pycache__",
    "*.pyc",
    "*.pyo",
    ".pytest_cache",
    ".DS_Store",
    "*.log"
  ]
}

data "azurerm_role_definition" "storage_blob_data_contributor" {
  name = "Storage Blob Data Contributor"
}

data "azapi_resource_list" "billing_role_definitions" {
  for_each = var.manage_role_assignments && var.enable_focus_exports && !var.is_enterprise_customer ? toset(var.billing_account_ids) : toset([])

  type      = "Microsoft.Billing/billingAccounts/billingRoleDefinitions@2024-04-01"
  parent_id = "/providers/Microsoft.Billing/billingAccounts/${each.value}"

  response_export_values = ["value"]
}

# Feeds check "billing_reader_assignments" in rbac.tf. depends_on defers the read to apply time
# on runs where add_role_assignment (re)fires, so the check sees the assignments as they are
# after the grant rather than warning on the pre-grant snapshot.
data "azapi_resource_list" "billing_role_assignments" {
  for_each = var.manage_role_assignments && var.enable_focus_exports && !var.is_enterprise_customer ? toset(var.billing_account_ids) : toset([])

  type      = "Microsoft.Billing/billingAccounts/billingRoleAssignments@2024-04-01"
  parent_id = "/providers/Microsoft.Billing/billingAccounts/${each.value}"

  response_export_values = ["value"]

  depends_on = [azapi_resource_action.add_role_assignment]
}

data "modtm_module_source" "this" {
  module_path = path.module
}

# When bringing your own app registration and letting the module manage the app role assignment,
# resolve the supplied app's service principal object ID and app role ID by directory READ (not
# write). Not created in strict-separation mode (manage_entra_app_role_assignment = false), so no
# directory access is needed there at all.
data "azuread_service_principal" "existing_aws_app" {
  count     = (!local.create_entra_app && local.manage_entra_app_role_assignment) ? 1 : 0
  client_id = var.existing_entra_application_client_id
}
