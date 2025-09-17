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
}

resource "azurerm_role_assignment" "grant_func_queue_contributor" {
  scope                = azurerm_storage_account.cost_export.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
}

resource "azurerm_role_assignment" "event_grid_queue_sender" {
  scope                = azurerm_storage_account.cost_export.id
  role_definition_name = "Storage Queue Data Message Sender"
  principal_id         = azurerm_eventgrid_system_topic.storage_events.identity[0].principal_id
}

resource "azurerm_role_assignment" "carbon_optimization_reader" {
  # TODO: Verify this scope is ok
  scope                = "/providers/Microsoft.Management/managementGroups/${data.azurerm_client_config.current.tenant_id}"
  role_definition_name = "Carbon Optimization Reader"
  principal_id         = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
}

resource "azurerm_role_assignment" "management_group_reader" {
  scope                = "/providers/Microsoft.Management/managementGroups/${data.azurerm_client_config.current.tenant_id}"
  role_definition_name = "Management Group Reader"
  principal_id         = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
}

resource "azurerm_role_assignment" "advisor_reader" {
  scope                = "/providers/Microsoft.Management/managementGroups/${data.azurerm_client_config.current.tenant_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
}