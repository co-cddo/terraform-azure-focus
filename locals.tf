locals {
  cost_mgmt_suffix = length(var.cost_mgmt_suffix) > 0 ? "-${var.cost_mgmt_suffix}" : ""

  # The data source's id is the full role definition resource path
  # (/providers/Microsoft.Authorization/roleDefinitions/<guid>); the ABAC GuidEquals operator in
  # rbac.tf needs the bare GUID, so take the last path segment.
  storage_blob_data_contributor_role_id = reverse(split("/", data.azurerm_role_definition.storage_blob_data_contributor.id))[0]

  effective_log_analytics_workspace_id = var.log_analytics_workspace_id != null ? var.log_analytics_workspace_id : azurerm_log_analytics_workspace.this[0].id

  # The az CLI in local-exec authenticates separately from the azurerm provider, so its active
  # subscription can differ from the module's target (e.g. with aliased providers). Pin every az
  # invocation to the resource group's subscription rather than relying on the CLI default.
  cost_export_subscription_id = split("/", azurerm_resource_group.cost_export.id)[2]

  publish_code_command_common = "az functionapp deployment source config-zip --src ${data.archive_file.function.output_path} --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name} --subscription ${local.cost_export_subscription_id}"
  publish_code_command        = var.deploy_from_external_network ? "Start-Sleep -Seconds 150 && ${local.publish_code_command_common}" : local.publish_code_command_common
  identifier_uri              = "api://${data.azurerm_client_config.current.tenant_id}/GDS-AWS-Cost-Forwarding${local.cost_mgmt_suffix}"

  # When no existing app registration client ID is supplied, the module creates the AWS-federation
  # Entra app, service principal, and app role itself (these require directory-write privileges).
  # Supplying existing_entra_application_client_id points the module at a pre-created app instead,
  # for separation of duties between Entra ID and Azure RBAC admins.
  create_entra_app    = var.existing_entra_application_client_id == null
  entra_app_client_id = local.create_entra_app ? azuread_application.aws_app[0].client_id : var.existing_entra_application_client_id

  # manage_entra_app_role_assignment only has meaning when bringing your own app registration:
  # if the module creates the app (and therefore already holds directory-write privileges), it
  # always creates the binding too, so delegating just that step to the user makes no sense. Force
  # it true in that case rather than letting a nonsensical create-app-but-skip-binding combo exist.
  manage_entra_app_role_assignment = local.create_entra_app ? true : var.manage_entra_app_role_assignment

  # SP object ID and app role ID for the app role assignment. Resolved from the module-created
  # resources, or (when bringing your own app and the module manages the binding) from the
  # data.azuread_service_principal lookup in rbac.tf. Only referenced when the binding is created.
  entra_sp_object_id = local.create_entra_app ? azuread_service_principal.aws_app[0].object_id : (
    local.manage_entra_app_role_assignment ? data.azuread_service_principal.existing_aws_app[0].object_id : null
  )

  entra_app_role_id = local.create_entra_app ? random_uuid.app_uuid[0].id : (
    local.manage_entra_app_role_assignment ? data.azuread_service_principal.existing_aws_app[0].app_role_ids["AssumeRoleWithWebIdentity"] : null
  )

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

  pe_overrides = var.custom_resource_names.private_endpoints != null ? var.custom_resource_names.private_endpoints : {
    storage_blob    = null
    storage_queue   = null
    deployment_blob = null
    function_app    = null
  }
  psc_overrides = var.custom_resource_names.private_service_connections != null ? var.custom_resource_names.private_service_connections : {
    storage_blob    = null
    storage_queue   = null
    deployment_blob = null
    function_app    = null
  }

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
