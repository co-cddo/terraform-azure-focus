resource "azuread_application" "aws_app" {
  display_name = "cost-export-${random_string.unique.result}"
  owners       = [data.azurerm_client_config.current.object_id]

  app_role {
    id                   = random_uuid.app_uuid.id
    allowed_member_types = ["User", "Application"]
    description          = "My role description"
    display_name         = "AssumeRole"
    value                = "AssumeRoleWithWebIdentity"
  }

  identifier_uris = [local.identifier_uri]
}

resource "azuread_service_principal" "aws_app" {
  client_id                    = azuread_application.aws_app.client_id
  app_role_assignment_required = false
  owners                       = [data.azurerm_client_config.current.object_id]

  feature_tags {
    enterprise = true
    gallery    = true
  }
}

resource "azuread_app_role_assignment" "aws_app" {
  app_role_id         = random_uuid.app_uuid.id
  principal_object_id = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
  resource_object_id  = azuread_service_principal.aws_app.object_id
  depends_on          = [azurerm_function_app_flex_consumption.cost_export]
}

resource "azurerm_role_assignment" "grant_sp_deploy_sa_contributor" {
  scope                = azurerm_storage_account.deployment.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = var.current_principal_type
}

resource "azurerm_role_assignment" "grant_func_queue_contributor" {
  scope                = azurerm_storage_account.cost_export.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "event_grid_queue_sender" {
  scope                = azurerm_storage_account.cost_export.id
  role_definition_name = "Storage Queue Data Message Sender"
  principal_id         = azurerm_eventgrid_system_topic.storage_events.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "carbon_optimization_reader" {
  # TODO: Verify this scope is ok
  scope                = "/providers/Microsoft.Management/managementGroups/${data.azurerm_client_config.current.tenant_id}"
  role_definition_name = "Carbon Optimization Reader"
  principal_id         = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "management_group_reader" {
  scope                = "/providers/Microsoft.Management/managementGroups/${data.azurerm_client_config.current.tenant_id}"
  role_definition_name = "Management Group Reader"
  principal_id         = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "advisor_reader" {
  scope                = "/providers/Microsoft.Management/managementGroups/${data.azurerm_client_config.current.tenant_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azapi_resource_action" "add_role_assignment" {
  for_each = toset(var.billing_account_ids)

  type                   = "Microsoft.Billing/billingAccounts@2019-10-01-preview"
  resource_id            = "/providers/Microsoft.Billing/billingAccounts/${each.value}"
  action                 = "createBillingRoleAssignment"
  method                 = "POST"
  when                   = "apply"
  response_export_values = ["*"]
  body = {
    properties = {
      principalId = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
      # TODO: Look this up dynamically https://learn.microsoft.com/en-us/rest/api/billing/billing-role-definition/list-by-billing-account?view=rest-billing-2024-04-01&tabs=HTTP
      roleDefinitionId = "/providers/Microsoft.Billing/billingAccounts/${each.value}/billingRoleDefinitions/50000000-aaaa-bbbb-cccc-100000000001"
    }
  }
}

# resource "azapi_resource_action" "remove_role_assignment" {
#   for_each    = toset(var.billing_account_ids)
  
#   type        = "Microsoft.Billing/billingAccounts/billingRoleAssignments@2019-10-01-preview"

#   # why not just use 'resource_id            = "/providers/Microsoft.Billing/billingAccounts/${each.value}"' as above
#   #   fails with:
#   #   │ Error: Invalid function argument
#   # │ 
#   # │   on ../terraform-azure-focus/rbac.tf line 99, in resource "azapi_resource_action" "remove_role_assignment":
#   # │   99:   resource_id = jsondecode(azapi_resource_action.add_role_assignment[each.key].output).id
#   # │     ├────────────────
#   # │     │ while calling jsondecode(str)
#   # │     │ azapi_resource_action.add_role_assignment is object with 1 attribute "bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31"
#   # │     │ each.key is "bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31"
#   # │ 
#   # │ Invalid value for "str" parameter: string required.
#   #
#   # azapi_resource_action.add_role_assignment[each.key].output.id ---->
#   #      "/providers/Microsoft.Billing/billingAccounts/bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31/billingRoleAssignments/50000000-aaaa-bbbb-cccc-100000000001_ccbdf98a-f95d-4c68-8fe3-0539ff4bb82d",

#   resource_id = json_decode(azapi_resource_action.add_role_assignment[each.key].output).id
#   method      = "DELETE"
#   when        = "destroy"
# }

# required permission on function to write to storage because it creates Cost Mgmt Export tasks with a destination to storage (function needs permission to write to that storage endpoint on create)
resource "azurerm_role_assignment" "grant_func_storage_blob_contributor" {
  scope                = azurerm_storage_account.cost_export.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
resource "azurerm_role_assignment" "grant_func_storage_account_contributor" {
  scope                = azurerm_storage_account.cost_export.id
  role_definition_name = "Owner"
  principal_id         = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}
