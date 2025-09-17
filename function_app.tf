resource "azurerm_service_plan" "cost_export" {
  name                = "asp-cost-export"
  resource_group_name = azurerm_resource_group.cost_export.name
  location            = azurerm_resource_group.cost_export.location
  os_type             = "Linux"
  sku_name            = "FC1"
}

resource "azurerm_function_app_flex_consumption" "cost_export" {
  name                = "func-cost-export-${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.cost_export.name
  location            = azurerm_resource_group.cost_export.location

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
  runtime_version               = "3.12"
  maximum_instance_count        = 50
  instance_memory_in_mb         = 2048
  https_only                    = true
  virtual_network_subnet_id     = var.function_app_subnet_id
  public_network_access_enabled = var.deploy_from_external_network

  identity {
    type = "SystemAssigned"
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
    "STORAGE_CONNECTION_STRING"                 = azurerm_storage_account.cost_export.primary_connection_string
    "CONTAINER_NAME"                            = azapi_resource.cost_export.name
    "AzureWebJobsStorage"                       = azurerm_storage_account.deployment.primary_connection_string
    "AzureWebJobsFeatureFlags"                  = "EnableWorkerIndexing"
    "StorageAccountManagedIdentity__serviceUri" = "https://${azurerm_storage_account.cost_export.name}.queue.core.windows.net/"
    "ENTRA_APP_CLIENT_ID"                       = azuread_application.aws_app.client_id
    "ENTRA_APP_URN"                             = local.identifier_uri
    "AWS_ROLE_ARN"                              = local.aws_role_arn
    "AWS_REGION"                                = var.aws_region
    "S3_FOCUS_PATH"                             = local.aws_target_file_path
    "S3_UTILIZATION_PATH"                       = local.aws_target_file_path
    "S3_RECOMMENDATIONS_PATH"                   = local.aws_target_file_path
    "S3_CARBON_PATH"                            = local.aws_target_file_path
    "CARBON_DIRECTORY_NAME"                     = local.carbon_directory_name
    "CARBON_API_TENANT_ID"                      = data.azurerm_client_config.current.tenant_id
    # We use the tenant root management group scope for carbon emissions and recommendations only - we have to use the billing account scope(s) for FOCUS cost exports
    "BILLING_SCOPE" = "/providers/Microsoft.Management/managementGroups/${data.azurerm_client_config.current.tenant_id}"
    # Mapping of billing account index to billing account ID for S3 path organization
    "BILLING_ACCOUNT_MAPPING" = jsonencode({ for idx, account in local.billing_accounts_map : idx => account.id })
  }
}

resource "azurerm_application_insights" "this" {
  name                                  = "ai-func-cost-export-${random_string.unique.result}"
  location                              = azurerm_resource_group.cost_export.location
  resource_group_name                   = azurerm_resource_group.cost_export.name
  application_type                      = "web"
  daily_data_cap_in_gb                  = 5
  daily_data_cap_notifications_disabled = false
  disable_ip_masking                    = false
  force_customer_storage_for_profiler   = false
  internet_ingestion_enabled            = true
  internet_query_enabled                = true
  local_authentication_disabled         = false
  retention_in_days                     = 90
  sampling_percentage                   = 100
  tags                                  = {}
}

resource "null_resource" "publish_function_code" {
  provisioner "local-exec" {
    command = local.publish_code_command
  }

  triggers = {
    src_md5              = data.archive_file.function.output_md5
    publish_code_command = local.publish_code_command
  }

  depends_on = [azurerm_function_app_flex_consumption.cost_export, azurerm_role_assignment.grant_sp_deploy_sa_contributor, azurerm_private_endpoint.deployment, azurerm_private_endpoint.function_app]
}

resource "null_resource" "set_function_app_public_network_access_disabled" {
  count = var.deploy_from_external_network ? 1 : 0

  provisioner "local-exec" {
    command = "az functionapp update --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name} --set publicNetworkAccess=Disabled"
  }

  triggers = {
    always_run = timestamp()
  }

  depends_on = [null_resource.publish_function_code]
}