#### https://aws.amazon.com/blogs/security/how-to-access-aws-resources-from-microsoft-entra-id-tenants-using-aws-security-token-service/

locals {
  publish_code_command_common = "az functionapp deployment source config-zip --src ${data.archive_file.function.output_path} --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name}"
  # publish_code_command        = var.deploy_from_external_network ? "sleep 240 && ${local.publish_code_command_common} && az functionapp config access-restriction remove --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name} --rule-name AllowCurrentIP --scm && az functionapp config access-restriction remove --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name} --rule-name AllowCurrentIP && az functionapp update --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name} --set publicNetworkAccess=Disabled" : local.publish_code_command_common
  publish_code_command = var.deploy_from_external_network ? "sleep 240 && ${local.publish_code_command_common} && az functionapp update --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name} --set publicNetworkAccess=Disabled" : local.publish_code_command_common
  identifier_uri       = "api://${data.azurerm_client_config.current.tenant_id}/AWS-Federation-App-${var.name}"
}

# Resource Group
resource "azurerm_resource_group" "cost_export" {
  name     = var.resource_group_name
  location = var.location
}

# Storage Account
resource "azurerm_storage_account" "cost_export" {
  name                     = "stcostexport${random_string.unique.result}"
  resource_group_name      = azurerm_resource_group.cost_export.name
  location                 = azurerm_resource_group.cost_export.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true

  public_network_access_enabled = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

resource "azapi_resource" "cost_export" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01"
  name      = "cost-exports"
  parent_id = "${azurerm_storage_account.cost_export.id}/blobServices/default"
  body = {
    properties = {
      metadata     = {}
      publicAccess = "None"
    }
  }
}

# Private Endpoint for storage account
resource "azurerm_private_endpoint" "storage" {
  name                = "pe-storage-cost-export"
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-storage-cost-export"
    private_connection_resource_id = azurerm_storage_account.cost_export.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

resource "azurerm_storage_account" "deployment" {
  name                     = "stcostexdply${random_string.unique.result}"
  resource_group_name      = azurerm_resource_group.cost_export.name
  location                 = azurerm_resource_group.cost_export.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true

  public_network_access_enabled = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

resource "azapi_resource" "deployment" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01"
  name      = "cost-exports-deployment"
  parent_id = "${azurerm_storage_account.deployment.id}/blobServices/default"
  body = {
    properties = {
      metadata     = {}
      publicAccess = "None"
    }
  }
}

# resource "azurerm_role_assignment" "grant_deploy_sa_contributor" {
#   scope                = azurerm_storage_account.deployment.id
#   role_definition_name = "Storage Blob Data Contributor"
#   principal_id         = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
# }

resource "azurerm_role_assignment" "grant_sp_deploy_sa_contributor" {
  scope                = azurerm_storage_account.deployment.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Private Endpoint for deployment storage account
resource "azurerm_private_endpoint" "deployment" {
  name                = "pe-storage-cost-export-deployment"
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-storage-cost-export-deployment"
    private_connection_resource_id = azurerm_storage_account.deployment.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

# Private Endpoint for function app
resource "azurerm_private_endpoint" "function_app" {
  name                = "pe-func-cost-export"
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-func-cost-export"
    private_connection_resource_id = azurerm_function_app_flex_consumption.cost_export.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

# Random string for unique storage account name
resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}

# Function App Service Plan
resource "azurerm_service_plan" "cost_export" {
  name                = "asp-cost-export"
  resource_group_name = azurerm_resource_group.cost_export.name
  location            = azurerm_resource_group.cost_export.location
  os_type             = "Linux"
  sku_name            = "FC1"
}

data "archive_file" "function" {
  type        = "zip"
  source_dir  = "${path.module}/src/cost_export"
  output_path = "${path.module}/cost_export.zip"
}

# Function App
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
    "STORAGE_CONNECTION_STRING"        = azurerm_storage_account.cost_export.primary_connection_string
    "CONTAINER_NAME"                   = azapi_resource.cost_export.name
    "AzureWebJobsStorage"              = azurerm_storage_account.deployment.primary_connection_string
    "AzureWebJobsInputCostDataStorage" = azurerm_storage_account.cost_export.primary_connection_string
    "AzureWebJobsFeatureFlags"         = "EnableWorkerIndexing"
    "ENTRA_APP_CLIENT_ID"              = azuread_application.aws_app.client_id
    "ENTRA_APP_URN"                    = local.identifier_uri
    "AWS_ROLE_ARN"                     = var.aws_role_arn
    "AWS_REGION"                       = var.aws_region
    "S3_TARGET_PATH"                   = var.aws_target_file_path
  }
}

resource "azurerm_application_insights" "this" {
  name                                  = "ai-func-cost-export-${random_string.unique.result}"
  location                              = "uksouth"
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
    src_md5              = md5(data.archive_file.function.output_md5)
    publish_code_command = local.publish_code_command
  }

  depends_on = [azurerm_function_app_flex_consumption.cost_export, azurerm_role_assignment.grant_sp_deploy_sa_contributor, azurerm_private_endpoint.deployment, azurerm_private_endpoint.function_app]
}

# resource "null_resource" "cleanup_external_access" {
#   count = var.deploy_from_external_network ? 1 : 0

#   provisioner "local-exec" {
#     command = <<-EOT
#       az functionapp config access-restriction remove --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name} --rule-name AllowCurrentIP --scm
#       az functionapp config access-restriction remove --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name} --rule-name AllowCurrentIP
#       az functionapp update --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name} --set publicNetworkAccess=Disabled
#     EOT
#   }

#   triggers = {
#     function_app_id = azurerm_function_app_flex_consumption.cost_export.id
#   }

#   depends_on = [null_resource.publish_function_code]
# }

resource "time_static" "recurrence" {}

# Cost Export Configuration
resource "azapi_resource" "daily_cost_export" {
  type      = "Microsoft.CostManagement/exports@2023-07-01-preview"
  name      = "focus-daily-cost-export"
  parent_id = var.report_scope
  location  = var.location
  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      exportDescription = "Focus Daily Cost Export"
      definition = {
        type = "FocusCost"
        dataSet = {
          configuration = {
            dataVersion = "1.0"
          }
          granularity = "Daily"
        }
        timeframe = "MonthToDate"
      }
      schedule = {
        status     = "Active"
        recurrence = "Daily"
        recurrencePeriod = {
          from = time_static.recurrence.id
          to   = timeadd(time_static.recurrence.id, "${24 * 365 * 5}h")
        }
      }
      format = "Parquet"
      deliveryInfo = {
        destination = {
          type       = "AzureBlob"
          resourceId = azurerm_storage_account.cost_export.id
          container : azapi_resource.cost_export.name
          rootFolderPath : "exports"
        }
      }
      partitionData         = true
      dataOverwriteBehavior = "OverwritePreviousReport"
      compressionMode       = "None"
    }
  }
}

# Get current client config
data "azurerm_client_config" "current" {}
# Virtual network data source
data "azurerm_virtual_network" "existing" {
  name                = var.virtual_network_name
  resource_group_name = var.virtual_network_resource_group_name
}

# Get current public IP for external deployment
# data "http" "current_ip" {
#   count = var.deploy_from_external_network ? 1 : 0
#   url   = "https://api.ipify.org?format=text"
# }

# Private DNS Zones for storage services
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.cost_export.name
}

resource "azurerm_private_dns_zone" "file" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.cost_export.name
}

resource "azurerm_private_dns_zone" "table" {
  name                = "privatelink.table.core.windows.net"
  resource_group_name = azurerm_resource_group.cost_export.name
}

resource "azurerm_private_dns_zone" "sites" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.cost_export.name
}

# Private DNS Zone virtual network links
resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "blob-dns-link"
  resource_group_name   = azurerm_resource_group.cost_export.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "file" {
  name                  = "file-dns-link"
  resource_group_name   = azurerm_resource_group.cost_export.name
  private_dns_zone_name = azurerm_private_dns_zone.file.name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "table" {
  name                  = "table-dns-link"
  resource_group_name   = azurerm_resource_group.cost_export.name
  private_dns_zone_name = azurerm_private_dns_zone.table.name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "sites" {
  name                  = "sites-dns-link"
  resource_group_name   = azurerm_resource_group.cost_export.name
  private_dns_zone_name = azurerm_private_dns_zone.sites.name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
}

# Private DNS A records linking private endpoints to DNS zones
resource "azurerm_private_dns_a_record" "storage" {
  name                = azurerm_storage_account.cost_export.name
  zone_name           = azurerm_private_dns_zone.blob.name
  resource_group_name = azurerm_resource_group.cost_export.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage.private_service_connection[0].private_ip_address]
}

resource "azurerm_private_dns_a_record" "deployment" {
  name                = azurerm_storage_account.deployment.name
  zone_name           = azurerm_private_dns_zone.blob.name
  resource_group_name = azurerm_resource_group.cost_export.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.deployment.private_service_connection[0].private_ip_address]
}

resource "azurerm_private_dns_a_record" "function_app" {
  name                = azurerm_function_app_flex_consumption.cost_export.name
  zone_name           = azurerm_private_dns_zone.sites.name
  resource_group_name = azurerm_resource_group.cost_export.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.function_app.private_service_connection[0].private_ip_address]
}

resource "random_uuid" "app_uuid" {}

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
