locals {
  cost_mgmt_suffix = length(var.cost_mgmt_suffix) > 0 ? "-${var.cost_mgmt_suffix}" : ""

  # The data source's id is the full role definition resource path
  # (/providers/Microsoft.Authorization/roleDefinitions/<guid>); the ABAC GuidEquals operator in
  # rbac.tf needs the bare GUID, so take the last path segment.
  storage_blob_data_contributor_role_id = reverse(split("/", data.azurerm_role_definition.storage_blob_data_contributor.id))[0]

  effective_log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  publish_code_command_common = "az functionapp deployment source config-zip --src ${data.archive_file.function.output_path} --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name}"
  publish_code_command        = var.deploy_from_external_network ? "Start-Sleep -Seconds 150 && ${local.publish_code_command_common}" : local.publish_code_command_common
  identifier_uri              = "api://${data.azurerm_client_config.current.tenant_id}/GDS-AWS-Cost-Forwarding${local.cost_mgmt_suffix}"
  focus_dataset_major_version = substr(var.focus_dataset_version, 0, 1)
  # FOCUS directory name should only contain major version number for the data set
  focus_directory_name  = "gds-focus-v${local.focus_dataset_major_version}"
  carbon_directory_name = "gds-carbon-v1"
  aws_role_arn          = "arn:aws:iam::${var.aws_account_id}:role/AzureFederated-${data.azurerm_client_config.current.tenant_id}"
  aws_target_file_path  = "${var.aws_s3_bucket_name}/${data.azurerm_client_config.current.tenant_id}"

  # Create billing account mapping from the provided list
  # Construct full resource manager paths from just the billing account IDs
  billing_accounts_map = {
    for idx, account_id in var.billing_account_ids :
    tostring(idx) => {
      id    = account_id
      scope = "/providers/Microsoft.Billing/billingAccounts/${account_id}"
    }
  }

  # Create report scopes for the provided billing accounts
  report_scopes = [
    for account_id in var.billing_account_ids : "/providers/Microsoft.Billing/billingAccounts/${account_id}"
  ]

  # Look up billing role definition IDs by name
  billing_account_reader_role_ids = {
    for k, v in data.azapi_resource_list.billing_role_definitions :
    k => one([for r in v.output.value : r.id if r.properties.roleName == "Billing account reader"])
  }

  pe_overrides  = var.custom_resource_names.private_endpoints != null ? var.custom_resource_names.private_endpoints : {}
  psc_overrides = var.custom_resource_names.private_service_connections != null ? var.custom_resource_names.private_service_connections : {}

  names = {
    storage_account_cost_export = coalesce(var.custom_resource_names.storage_account_cost_export, "stcostexport${random_string.unique.result}")
    storage_account_deployment  = coalesce(var.custom_resource_names.storage_account_deployment, "stcostexdply${random_string.unique.result}")
    service_plan                = coalesce(var.custom_resource_names.service_plan, "asp-cost-export")
    user_assigned_identity      = coalesce(var.custom_resource_names.user_assigned_identity, "id-cost-export-${random_string.unique.result}")
    function_app                = coalesce(var.custom_resource_names.function_app, "func-cost-export-${random_string.unique.result}")
    application_insights        = coalesce(var.custom_resource_names.application_insights, "ai-func-cost-export-${random_string.unique.result}")
    log_analytics_workspace     = coalesce(var.custom_resource_names.log_analytics_workspace, "log-cost-export-${random_string.unique.result}")
    event_grid_system_topic     = coalesce(var.custom_resource_names.event_grid_system_topic, "evgt-storage-${random_string.unique.result}")
    event_grid_subscription     = coalesce(var.custom_resource_names.event_grid_subscription, "evgs-blob-created-${random_string.unique.result}")
    entra_application           = coalesce(var.custom_resource_names.entra_application, "cost-export-${random_string.unique.result}")
    cost_export_prefix          = coalesce(var.custom_resource_names.cost_export_prefix, "focus-daily-cost-export")

    pe_storage_blob    = coalesce(local.pe_overrides.storage_blob, "pe-storage-cost-export")
    pe_storage_queue   = coalesce(local.pe_overrides.storage_queue, "pe-storage-queue-cost-export")
    pe_deployment_blob = coalesce(local.pe_overrides.deployment_blob, "pe-storage-cost-export-deployment")
    pe_function_app    = coalesce(local.pe_overrides.function_app, "pe-func-cost-export")

    psc_storage_blob    = coalesce(local.psc_overrides.storage_blob, "psc-storage-cost-export")
    psc_storage_queue   = coalesce(local.psc_overrides.storage_queue, "psc-storage-queue-cost-export")
    psc_deployment_blob = coalesce(local.psc_overrides.deployment_blob, "psc-storage-cost-export-deployment")
    psc_function_app    = coalesce(local.psc_overrides.function_app, "psc-func-cost-export")
  }
}
