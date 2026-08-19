# Prevents destroy and create of app registration for instances of the solution deployed prior to the 'bring your own app registration' feature
moved {
  from = random_uuid.app_uuid
  to   = random_uuid.app_uuid[0]
}
moved {
  from = azuread_application.aws_app
  to   = azuread_application.aws_app[0]
}
moved {
  from = azuread_service_principal.aws_app
  to   = azuread_service_principal.aws_app[0]
}
moved {
  from = azuread_app_role_assignment.aws_app
  to   = azuread_app_role_assignment.aws_app[0]
}

# The AWS-federation Entra app, service principal, and app role are created only when the consumer
# does not bring their own app registration (var.existing_entra_application_client_id). Creating
# these requires directory-write privileges; consumers enforcing separation of duties between Entra
# ID and Azure RBAC admins supply a pre-created app's client ID instead. See README "Privileges".
resource "random_uuid" "app_uuid" {
  count = local.create_entra_app ? 1 : 0
}

resource "azuread_application" "aws_app" {
  count        = local.create_entra_app ? 1 : 0
  display_name = local.names.entra_application
  owners       = [data.azurerm_client_config.current.object_id]

  #### https://aws.amazon.com/blogs/security/how-to-access-aws-resources-from-microsoft-entra-id-tenants-using-aws-security-token-service/
  app_role {
    id                   = random_uuid.app_uuid[0].id
    allowed_member_types = ["User", "Application"]
    description          = "Allows the cost-export managed identity to assume an AWS role via OIDC federation."
    display_name         = "AssumeRole"
    value                = "AssumeRoleWithWebIdentity"
  }

  identifier_uris = [local.identifier_uri]
}

resource "azuread_service_principal" "aws_app" {
  count                        = local.create_entra_app ? 1 : 0
  client_id                    = azuread_application.aws_app[0].client_id
  app_role_assignment_required = false
  owners                       = [data.azurerm_client_config.current.object_id]
}

# When bringing your own app registration and letting the module manage the app role assignment,
# resolve the supplied app's service principal object ID and app role ID by directory READ (not
# write). Not created in strict-separation mode (manage_entra_app_role_assignment = false), so no
# directory access is needed there at all.
data "azuread_service_principal" "existing_aws_app" {
  count     = (!local.create_entra_app && local.manage_entra_app_role_assignment) ? 1 : 0
  client_id = var.existing_entra_application_client_id
}

resource "azuread_app_role_assignment" "aws_app" {
  count               = local.manage_entra_app_role_assignment ? 1 : 0
  app_role_id         = local.entra_app_role_id
  principal_object_id = azurerm_user_assigned_identity.cost_export.principal_id
  resource_object_id  = local.entra_sp_object_id
  depends_on          = [azurerm_function_app_flex_consumption.cost_export]
}


# Apply-time data-plane access for the deployer: the cost_export storage account disables shared
# keys, so the provider reads blob + queue properties over Entra ID during create/refresh and needs
# both data roles. Scoped to the resource group; time_sleep.wait_for_deployer_rbac allows RBAC to
# propagate before the storage account is created. See the "Privileges" section in README.md.
resource "azurerm_role_assignment" "grant_deployer_cost_export_blob" {
  count                = var.manage_role_assignments ? 1 : 0
  scope                = local.resource_group_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = var.current_principal_type
}

resource "azurerm_role_assignment" "grant_deployer_cost_export_queue" {
  count                = var.manage_role_assignments ? 1 : 0
  scope                = local.resource_group_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = var.current_principal_type
}

resource "time_sleep" "wait_for_deployer_rbac" {
  # No module-created grants to propagate when RBAC is managed externally.
  create_duration = var.manage_role_assignments ? "60s" : "0s"

  depends_on = [
    azurerm_role_assignment.grant_deployer_cost_export_blob,
    azurerm_role_assignment.grant_deployer_cost_export_queue,
  ]
}

resource "azurerm_role_assignment" "grant_func_queue_contributor" {
  count                = var.manage_role_assignments && var.enable_focus_exports ? 1 : 0
  scope                = azurerm_storage_account.cost_export[0].id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.cost_export.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "grant_func_deployment_blob_contributor" {
  count                = var.manage_role_assignments ? 1 : 0
  scope                = azurerm_storage_account.deployment.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.cost_export.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "grant_func_deployment_queue_contributor" {
  count                = var.manage_role_assignments ? 1 : 0
  scope                = azurerm_storage_account.deployment.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_user_assigned_identity.cost_export.principal_id
  principal_type       = "ServicePrincipal"
}

resource "time_sleep" "wait_for_function_deployment_rbac" {
  create_duration = var.manage_role_assignments ? "60s" : "0s"

  depends_on = [
    azurerm_role_assignment.grant_func_deployment_blob_contributor,
    azurerm_role_assignment.grant_func_deployment_queue_contributor,
  ]
}

resource "azurerm_role_assignment" "event_grid_queue_sender" {
  count                = var.manage_role_assignments && var.enable_focus_exports ? 1 : 0
  scope                = azurerm_storage_account.cost_export[0].id
  role_definition_name = "Storage Queue Data Message Sender"
  principal_id         = azurerm_eventgrid_system_topic.storage_events[0].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "carbon_optimization_reader" {
  count                = var.manage_role_assignments ? 1 : 0
  scope                = local.management_group_scope
  role_definition_name = "Carbon Optimization Reader"
  principal_id         = azurerm_user_assigned_identity.cost_export.principal_id
  principal_type       = "ServicePrincipal"
}

# The AdvisorRecommendationsExporter reads Advisor recommendations tenant-wide. Without a read role
# the recommendations API returns 200 with an empty array (never 403). "Advisor Recommendations
# Contributor" is the least-privilege built-in role granting Microsoft.Advisor/recommendations/read
# - there is no read-only Advisor recommendations built-in. See README "Privileges".
resource "azurerm_role_assignment" "advisor_recommendations_contributor" {
  count                = var.manage_role_assignments ? 1 : 0
  scope                = local.management_group_scope
  role_definition_name = "Advisor Recommendations Contributor"
  principal_id         = azurerm_user_assigned_identity.cost_export.principal_id
  principal_type       = "ServicePrincipal"
}

# this only works for MCA customers
resource "azapi_resource_action" "add_role_assignment" {
  for_each = var.manage_role_assignments && var.enable_focus_exports && !var.is_enterprise_customer ? toset(var.billing_account_ids) : toset([])

  type                   = "Microsoft.Billing/billingAccounts@2019-10-01-preview"
  resource_id            = "/providers/Microsoft.Billing/billingAccounts/${each.value}"
  action                 = "createBillingRoleAssignment"
  method                 = "POST"
  when                   = "apply"
  response_export_values = ["*"]
  body = {
    properties = {
      principalId      = azurerm_user_assigned_identity.cost_export.principal_id
      roleDefinitionId = local.billing_account_reader_role_ids[each.value]
    }
  }
}

# The POST above is a one-shot action: Terraform records that the call happened but manages no
# resource it could later delete, so every rebuild of the identity would strand the old principal's
# assignment on the billing account forever (billing role assignments live in the billing account,
# not Entra ID, and nothing cleans them up when their principal is deleted). This companion action
# supplies the missing delete half of the lifecycle. It fires on destroy, when a billing account
# leaves var.billing_account_ids, and on identity rebuild: a changed principal_id replaces
# add_role_assignment and this action along with it, and destroying the old instance deletes the
# old principal's assignment. The DELETE targets api-version 2024-04-01, where deletion is
# documented as idempotent (204 when the assignment is already gone), so a manually removed
# assignment cannot block destroy.
resource "azapi_resource_action" "remove_role_assignment" {
  for_each = var.manage_role_assignments && var.enable_focus_exports && !var.is_enterprise_customer ? toset(var.billing_account_ids) : toset([])

  type        = "Microsoft.Billing/billingAccounts/billingRoleAssignments@2024-04-01"
  resource_id = azapi_resource_action.add_role_assignment[each.key].output.id
  method      = "DELETE"
  when        = "destroy"
}

# The other half a one-shot action lacks is read: nothing is refreshed at plan time, so Terraform
# cannot tell whether the assignment it once granted still exists. An out-of-band removal, or a
# grant that never fired for a rebuilt principal, stays invisible until the function app starts
# receiving 403s from the Cost Management APIs. This check compares a fresh read of each billing
# account's assignments (data.azapi_resource_list.billing_role_assignments in data.tf) against the
# identity's current principal ID, and emits a warning (it does not fail the run) when the reader
# role is missing.
check "billing_reader_assignments" {
  assert {
    condition = !var.enable_focus_exports || length(local.billing_accounts_missing_reader) == 0

    error_message = "The function app's managed identity is missing a billing role assignment on at least one billing account. This can happen when an assignment is removed out-of-band or when the managed identity is rebuilt and the one-shot grant does not re-fire. See the billing_role_assignment_manual_action_required output for the remediation script and the module README for details."
  }
}

# Function writes export output and creates export tasks that deliver to this storage account.
resource "azurerm_role_assignment" "grant_func_storage_blob_contributor" {
  count                = var.manage_role_assignments && var.enable_focus_exports ? 1 : 0
  scope                = azurerm_storage_account.cost_export[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.cost_export.principal_id
  principal_type       = "ServicePrincipal"
}

# Cost Management requires Owner here: when creating an export to a firewall-protected storage
# account it validates caller access and then assigns "Storage Blob Data Contributor" to the
# export's own identity; narrower roles fail at create with 401. Owner is broad, so the ABAC
# condition below restricts the function to assigning/removing ONLY that role on this account
# (no privilege escalation via roleAssignments/write). Full rationale in README "Privileges".
resource "azurerm_role_assignment" "grant_func_storage_account_owner_constrained" {
  count                = var.manage_role_assignments && var.enable_focus_exports ? 1 : 0
  scope                = azurerm_storage_account.cost_export[0].id
  role_definition_name = "Owner"
  principal_id         = azurerm_user_assigned_identity.cost_export.principal_id
  principal_type       = "ServicePrincipal"

  condition_version = "2.0"
  condition         = <<-EOT
  (
    (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
    )
    OR
    (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.storage_blob_data_contributor_role_id}}
    )
  )
  AND
  (
    (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
    )
    OR
    (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.storage_blob_data_contributor_role_id}}
    )
  )
  EOT
}

# for Enterprise Agreement customers - assign the "Enrollment Reader" role (24f8edb6-1668-4659-b5e2-40bb5f3a7d7e)
# but this requires Enterprise Admin privileges; so needs to be done manually
# resource "azapi_resource_action" "add_role_assignment" {
#   for_each = toset(var.billing_account_ids)

#   type                   = "Microsoft.Billing/billingAccounts@2019-10-01-preview"
#   resource_id            = "/providers/Microsoft.Billing/billingAccounts/${each.value}"
#   action                 = "billingRoleAssignment"
#   method                 = "PUT"
#   when                   = "apply"
#   response_export_values = ["*"]
#   body = {
#     properties = {
#       principalId = azurerm_user_assigned_identity.cost_export.principal_id
#       # "Enrollment Reader" for enterprise account customers - https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/assign-roles-azure-service-principals
#       roleDefinitionId = "/providers/Microsoft.Billing/billingAccounts/${each.value}/billingRoleDefinitions/24f8edb6-1668-4659-b5e2-40bb5f3a7d7e"
#       # principalTenantId = ????
#     }
#   }
# }
