resource "azurerm_service_plan" "cost_export" {
  # checkov:skip=CKV_AZURE_225:Zone redundancy not required at present
  # checkov:skip=CKV_AZURE_212:Failover not required at present
  name                = local.names.service_plan
  resource_group_name = azurerm_resource_group.cost_export.name
  location            = azurerm_resource_group.cost_export.location
  os_type             = "Linux"
  sku_name            = "FC1"
  tags                = var.tags
}

# User-assigned identity for the function app. Used in preference to a system-assigned
# identity so the principal/object ID is stable across function-app replacement: the
# application RBAC grants in rbac.tf (and any constrained delegation that pins this
# principal) survive a recreate of the function app, which a system-assigned identity
# would not - Azure mints a new object ID on every recreate.
resource "azurerm_user_assigned_identity" "cost_export" {
  name                = local.names.user_assigned_identity
  resource_group_name = azurerm_resource_group.cost_export.name
  location            = azurerm_resource_group.cost_export.location
  tags                = var.tags
}

resource "azurerm_function_app_flex_consumption" "cost_export" {
  name                = local.names.function_app
  resource_group_name = azurerm_resource_group.cost_export.name
  location            = azurerm_resource_group.cost_export.location
  tags                = var.tags

  storage_container_type = "blobContainer"
  # TODO: Switch to managed identity once this is fixed:
  # https://medium.com/p/99ff43c1557f
  # https://github.com/hashicorp/terraform-provider-azurerm/issues/29993?source=post_page-----99ff43c1557f---------------------------------------
  #storage_authentication_type = "SystemAssignedIdentity"
  storage_authentication_type   = "StorageAccountConnectionString"
  storage_access_key            = azurerm_storage_account.deployment.primary_access_key
  storage_container_endpoint    = "https://${azurerm_storage_account.deployment.name}.blob.core.windows.net/${azapi_resource.deployment.name}"
  service_plan_id               = azurerm_service_plan.cost_export.id
  runtime_name                  = "python"
  runtime_version               = "3.13"
  maximum_instance_count        = 50
  instance_memory_in_mb         = 4096
  https_only                    = true
  virtual_network_subnet_id     = var.function_app_subnet_id
  public_network_access_enabled = var.deploy_from_external_network

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cost_export.id]
  }

  site_config {
    application_insights_connection_string = azurerm_application_insights.this.connection_string
    application_insights_key               = azurerm_application_insights.this.instrumentation_key

    # TODO: default action needs to be set to deny but it's problematic in Terraform: https://github.com/hashicorp/terraform-provider-azurerm/issues/22593
    # dynamic "ip_restriction" {
    #   for_each = var.deploy_from_external_network ? [1] : []
    #   content {
    #     ip_address = "${trimspace(data.http.current_ip[0].response_body)}/32"
    #     name       = "AllowCurrentIP"
    #     priority   = 100
    #     action     = "Allow"
    #   }
    # }

    # # TODO: default action needs to be set to deny but it's problematic in Terraform: https://github.com/hashicorp/terraform-provider-azurerm/issues/22593
    # dynamic "scm_ip_restriction" {
    #   for_each = var.deploy_from_external_network ? [1] : []
    #   content {
    #     ip_address = "${trimspace(data.http.current_ip[0].response_body)}/32"
    #     name       = "AllowCurrentIP"
    #     priority   = 100
    #     action     = "Allow"
    #   }
    # }
  }

  app_settings = {
    "STORAGE_ACCOUNT_BLOB_ENDPOINT"             = azurerm_storage_account.cost_export.primary_blob_endpoint
    "CONTAINER_NAME"                            = azapi_resource.cost_export.name
    "AzureWebJobsFeatureFlags"                  = "EnableWorkerIndexing"
    "StorageAccountManagedIdentity__serviceUri" = "https://${azurerm_storage_account.cost_export.name}.queue.core.windows.net/"
    # The queue-trigger identity-based connection must name the user-assigned identity explicitly:
    # unlike a system-assigned identity, the host cannot infer which identity to use otherwise.
    "StorageAccountManagedIdentity__credential" = "managedidentity"
    "StorageAccountManagedIdentity__clientId"   = azurerm_user_assigned_identity.cost_export.client_id
    # Consumed by the function app code (common.py) so ManagedIdentityCredential targets this identity.
    "MANAGED_IDENTITY_CLIENT_ID" = azurerm_user_assigned_identity.cost_export.client_id
    "ENTRA_APP_CLIENT_ID"        = local.entra_app_client_id
    "ENTRA_APP_URN"              = local.identifier_uri
    "AWS_ROLE_ARN"               = local.aws_role_arn
    "AWS_REGION"                 = var.aws_region
    "S3_FOCUS_PATH"              = local.aws_target_file_path
    "S3_UTILIZATION_PATH"        = local.aws_target_file_path
    "S3_RECOMMENDATIONS_PATH"    = local.aws_target_file_path
    "S3_CARBON_PATH"             = local.aws_target_file_path
    "CARBON_DIRECTORY_NAME"      = local.carbon_directory_name
    "CARBON_API_TENANT_ID"       = data.azurerm_client_config.current.tenant_id
    # We use the tenant root management group scope for carbon emissions and recommendations only - we have to use the billing account scope(s) for FOCUS cost exports
    "BILLING_SCOPE" = "/providers/Microsoft.Management/managementGroups/${data.azurerm_client_config.current.tenant_id}"
    # Mapping of billing account index to billing account ID for S3 path organization
    "BILLING_ACCOUNT_MAPPING" = jsonencode({ for idx, account in local.billing_accounts_map : idx => account.id })
    "BILLING_AZURE_LOCATION"  = var.location

    "BACKFILL_START_DATE" = var.backfill_start_date

    "STORAGE_RESOURCE_ID" = azurerm_storage_account.cost_export.id
    "STORAGE_CONTAINER"   = azapi_resource.cost_export.name
    "ROOT_FOLDER_PATH"    = local.focus_directory_name
    "LOGGING_LEVEL"       = var.logging_level
    "COST_MGMT_SUFFIX"    = local.cost_mgmt_suffix
  }
}

resource "azurerm_monitor_diagnostic_setting" "function_app" {
  name                       = "diag-function-app"
  target_resource_id         = azurerm_function_app_flex_consumption.cost_export.id
  log_analytics_workspace_id = local.effective_log_analytics_workspace_id

  # FunctionAppLogs are emitted by the Functions host (not the in-process worker), so they
  # persist even when an invocation is hard-killed (timeout / OOM / instance recycle) before
  # the worker can flush its Application Insights telemetry.
  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_application_insights" "this" {
  name                = local.names.application_insights
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  application_type    = "web"
  # Point the component at the module's own workspace so telemetry lands there instead of an
  # Azure auto-provisioned "managed" workspace (classic App Insights is retired, so without this
  # Azure creates a separate workspace in an ai_*_managed resource group).
  workspace_id                         = local.effective_log_analytics_workspace_id
  daily_data_cap_in_gb                 = 5
  daily_data_cap_notifications_enabled = true
  ip_masking_enabled                   = true
  force_customer_storage_for_profiler  = false
  internet_ingestion_enabled           = true
  internet_query_enabled               = true
  local_authentication_enabled         = true
  retention_in_days                    = 90
  sampling_percentage                  = 100
  tags                                 = var.tags
}

moved {
  from = null_resource.publish_function_code
  to   = null_resource.publish_function_code[0]
}

resource "null_resource" "publish_function_code" {
  count = var.publish_function_code ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    command     = local.publish_code_command
  }

  triggers = {
    src_md5              = data.archive_file.function.output_md5
    publish_code_command = local.publish_code_command
  }

  depends_on = [azurerm_function_app_flex_consumption.cost_export, azurerm_role_assignment.grant_deployer_cost_export_blob, azurerm_private_endpoint.deployment, azurerm_private_endpoint.function_app]
}

# Backfill runs create one-off Cost Management export jobs ("focus-backfill{suffix}-<account>-<year>-<month>")
# per billing-account scope at runtime. These are NOT managed by Terraform, so destroying this module leaves
# them behind in Azure Cost Management (where they count against the per-scope export quota). This resource
# prints a reminder, during `terraform destroy`, to delete them from the portal.
#
# Destroy-time provisioners may only reference `self`, so the message - including the suffix - is baked into
# `triggers` at create time and read back from state on destroy.
resource "null_resource" "backfill_exports_cleanup_warning" {
  triggers = {
    warning = join("\n", [
      "",
      "WARNING: one-off 'focus-backfill${local.cost_mgmt_suffix}-*' Cost Management export jobs may have been left behind by backfill runs.",
      "They are created at runtime by the function app (not by Terraform) and are not removed by this destroy.",
      "Delete them so they do not count against the per-scope Cost Management export quota.",
      "In the Azure portal, open 'Cost Management + Billing' > 'Exports' for each billing-account scope,",
      "find the exports named 'focus-backfill${local.cost_mgmt_suffix}-*', and delete them.",
      "",
    ])
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    # Print to the warning stream for local runs, and on GitHub Actions also
    # append to the job summary so the reminder surfaces on the run's Summary
    # page rather than being buried in the destroy log (this null_resource is
    # torn down early, so its output scrolls off otherwise).
    #
    # A ::warning:: workflow-command annotation does NOT work here: Terraform
    # prefixes every line of local-exec output with the resource address, so
    # the runner never sees "::warning" at the start of the line. Writing to the
    # $GITHUB_STEP_SUMMARY file is plain file I/O and is unaffected by that.
    command = <<-EOT
      $msg = $env:BACKFILL_CLEANUP_WARNING
      Write-Warning $msg
      if ($env:GITHUB_STEP_SUMMARY) {
        $nl = [Environment]::NewLine
        $fence = '```'
        $summary = "## Backfill export cleanup$nl$nl$fence$nl$msg$nl$fence"
        Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $summary
      }
    EOT
    environment = {
      BACKFILL_CLEANUP_WARNING = self.triggers.warning
    }
  }
}

resource "null_resource" "set_deployment_storage_public_network_access_disabled" {
  count = local.deployment_storage_allow_public_access ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoProfile", "-Command"]
    command     = "az storage account update --name ${azurerm_storage_account.deployment.name} --resource-group ${azurerm_resource_group.cost_export.name} --subscription ${local.cost_export_subscription_id} --public-network-access Disabled"
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [null_resource.publish_function_code]
}

resource "null_resource" "set_function_app_public_network_access_disabled" {
  count = var.deploy_from_external_network ? 1 : 0

  provisioner "local-exec" {
    command = "az functionapp update --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name} --subscription ${local.cost_export_subscription_id} --set publicNetworkAccess=Disabled"
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [null_resource.publish_function_code]
}
