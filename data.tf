data "azurerm_client_config" "current" {}

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
  for_each = var.manage_role_assignments && !var.is_enterprise_customer ? toset(var.billing_account_ids) : toset([])

  type      = "Microsoft.Billing/billingAccounts/billingRoleDefinitions@2024-04-01"
  parent_id = "/providers/Microsoft.Billing/billingAccounts/${each.value}"

  response_export_values = ["value"]
}

# Feeds check "billing_reader_assignments" in rbac.tf. depends_on defers the read to apply time
# on runs where add_role_assignment (re)fires, so the check sees the assignments as they are
# after the grant rather than warning on the pre-grant snapshot.
data "azapi_resource_list" "billing_role_assignments" {
  for_each = var.manage_role_assignments && !var.is_enterprise_customer ? toset(var.billing_account_ids) : toset([])

  type      = "Microsoft.Billing/billingAccounts/billingRoleAssignments@2024-04-01"
  parent_id = "/providers/Microsoft.Billing/billingAccounts/${each.value}"

  response_export_values = ["value"]

  depends_on = [azapi_resource_action.add_role_assignment]
}
