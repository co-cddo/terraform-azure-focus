#### https://aws.amazon.com/blogs/security/how-to-access-aws-resources-from-microsoft-entra-id-tenants-using-aws-security-token-service/

locals {
  publish_code_command_common = "az functionapp deployment source config-zip --src ${data.archive_file.function.output_path} --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name}"
  publish_code_command        = var.deploy_from_external_network ? "sleep 240 && ${local.publish_code_command_common} && az functionapp update --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name} --set publicNetworkAccess=Disabled" : local.publish_code_command_common
  identifier_uri              = "api://${data.azurerm_client_config.current.tenant_id}/AWS-Federation-App-${var.name}"
  focus_dataset_major_version = substr(var.focus_dataset_version, 0, 1)
  # FOCUS directory name should only contain major version number for the data set
  focus_directory_name       = "gds-focus-v${local.focus_dataset_major_version}"
  carbon_directory_name      = "gds-carbon-v1"
  utilization_directory_name = "gds-recommendations-v1"
}

resource "azurerm_resource_group" "cost_export" {
  name     = var.resource_group_name
  location = var.location
}

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

resource "azapi_resource" "cost_data_queue" {
  type      = "Microsoft.Storage/storageAccounts/queueServices/queues@2022-09-01"
  name      = "costdata"
  parent_id = "${azurerm_storage_account.cost_export.id}/queueServices/default"
}

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

resource "azurerm_private_endpoint" "storage_queue" {
  name                = "pe-storage-queue-cost-export"
  location            = azurerm_resource_group.cost_export.location
  resource_group_name = azurerm_resource_group.cost_export.name
  subnet_id           = var.subnet_id

  private_service_connection {
    name                           = "psc-storage-queue-cost-export"
    private_connection_resource_id = azurerm_storage_account.cost_export.id
    subresource_names              = ["queue"]
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

resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}

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
    "UTILIZATION_CONTAINER_NAME"                = azapi_resource.utilization_container.name
    "AzureWebJobsStorage"                       = azurerm_storage_account.deployment.primary_connection_string
    "AzureWebJobsFeatureFlags"                  = "EnableWorkerIndexing"
    "StorageAccountManagedIdentity__serviceUri" = "https://${azurerm_storage_account.cost_export.name}.queue.core.windows.net/"
    "ENTRA_APP_CLIENT_ID"                       = azuread_application.aws_app.client_id
    "ENTRA_APP_URN"                             = local.identifier_uri
    "AWS_ROLE_ARN"                              = var.aws_role_arn
    "AWS_REGION"                                = var.aws_region
    "S3_FOCUS_PATH"                             = var.aws_target_file_path
    "S3_UTILIZATION_PATH"                       = var.aws_target_file_path
    "S3_CARBON_PATH"                            = var.aws_target_file_path
    "CARBON_DIRECTORY_NAME"                     = local.carbon_directory_name
    "CARBON_API_TENANT_ID"                      = data.azurerm_client_config.current.tenant_id
    "BILLING_SCOPE"                             = var.report_scope
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

resource "time_static" "recurrence" {}

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
            dataVersion = var.focus_dataset_version
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
          rootFolderPath : local.focus_directory_name
        }
      }
      partitionData         = true
      dataOverwriteBehavior = "OverwritePreviousReport"
      compressionMode       = "None"
    }
  }
}

data "azurerm_client_config" "current" {}

data "azurerm_virtual_network" "existing" {
  name                = var.virtual_network_name
  resource_group_name = var.virtual_network_resource_group_name
}

# Get current public IP for external deployment
# data "http" "current_ip" {
#   count = var.deploy_from_external_network ? 1 : 0
#   url   = "https://api.ipify.org?format=text"
# }

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

resource "azurerm_private_dns_zone" "queue" {
  name                = "privatelink.queue.core.windows.net"
  resource_group_name = azurerm_resource_group.cost_export.name
}

resource "azurerm_private_dns_zone" "sites" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.cost_export.name
}

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

resource "azurerm_private_dns_zone_virtual_network_link" "queue" {
  name                  = "queue-dns-link"
  resource_group_name   = azurerm_resource_group.cost_export.name
  private_dns_zone_name = azurerm_private_dns_zone.queue.name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "sites" {
  name                  = "sites-dns-link"
  resource_group_name   = azurerm_resource_group.cost_export.name
  private_dns_zone_name = azurerm_private_dns_zone.sites.name
  virtual_network_id    = data.azurerm_virtual_network.existing.id
}

resource "azurerm_private_dns_a_record" "storage" {
  name                = azurerm_storage_account.cost_export.name
  zone_name           = azurerm_private_dns_zone.blob.name
  resource_group_name = azurerm_resource_group.cost_export.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage.private_service_connection[0].private_ip_address]
}

resource "azurerm_private_dns_a_record" "storage_queue" {
  name                = azurerm_storage_account.cost_export.name
  zone_name           = azurerm_private_dns_zone.queue.name
  resource_group_name = azurerm_resource_group.cost_export.name
  ttl                 = 300
  records             = [azurerm_private_endpoint.storage_queue.private_service_connection[0].private_ip_address]
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

resource "azurerm_eventgrid_system_topic" "storage_events" {
  name                   = "evgt-storage-${random_string.unique.result}"
  resource_group_name    = azurerm_resource_group.cost_export.name
  location               = azurerm_resource_group.cost_export.location
  source_arm_resource_id = azurerm_storage_account.cost_export.id
  topic_type             = "Microsoft.Storage.StorageAccounts"

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "event_grid_queue_sender" {
  scope                = azurerm_storage_account.cost_export.id
  role_definition_name = "Storage Queue Data Message Sender"
  principal_id         = azurerm_eventgrid_system_topic.storage_events.identity[0].principal_id
}

resource "azurerm_eventgrid_event_subscription" "focus_blob_created" {
  name                  = "evgs-blob-created-${random_string.unique.result}"
  scope                 = azurerm_storage_account.cost_export.id
  event_delivery_schema = "EventGridSchema"

  included_event_types = [
    "Microsoft.Storage.BlobCreated"
  ]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/${azapi_resource.cost_export.name}/blobs/${local.focus_directory_name}/"
    subject_ends_with   = ".parquet"
  }

  storage_queue_endpoint {
    storage_account_id                    = azurerm_storage_account.cost_export.id
    queue_name                            = azapi_resource.cost_data_queue.name
    queue_message_time_to_live_in_seconds = 604800
  }

  delivery_identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_role_assignment.event_grid_queue_sender,
    azapi_resource.cost_data_queue
  ]
}

resource "azapi_resource" "utilization_export" {
  type      = "Microsoft.CostManagement/exports@2023-07-01-preview"
  name      = "utilization-export"
  parent_id = var.report_scope
  location  = var.location
  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      exportDescription = "Resource Utilization Export"
      definition = {
        type = "Usage"
        dataSet = {
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
      format = "Csv"
      deliveryInfo = {
        destination = {
          type           = "AzureBlob"
          resourceId     = azurerm_storage_account.cost_export.id
          container      = azapi_resource.utilization_container.name
          rootFolderPath = local.utilization_directory_name
        }
      }
      partitionData         = true
      dataOverwriteBehavior = "OverwritePreviousReport"
      compressionMode       = "gzip"
    }
  }
}

resource "azapi_resource" "utilization_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01"
  name      = "utilization-exports"
  parent_id = "${azurerm_storage_account.cost_export.id}/blobServices/default"
  body = {
    properties = {
      metadata     = {}
      publicAccess = "None"
    }
  }
}

resource "azurerm_role_assignment" "carbon_optimization_reader" {
  # TODO: Revert to using variable
  #scope                = var.report_scope
  scope                = "/subscriptions/a81ff9b8-d793-4337-92dc-111c37a2e331"
  role_definition_name = "Carbon Optimization Reader"
  principal_id         = azurerm_function_app_flex_consumption.cost_export.identity[0].principal_id
}


resource "azapi_resource" "utilization_data_queue" {
  type      = "Microsoft.Storage/storageAccounts/queueServices/queues@2022-09-01"
  name      = "utilizationdata"
  parent_id = "${azurerm_storage_account.cost_export.id}/queueServices/default"
}

resource "azurerm_eventgrid_event_subscription" "utilization_blob_created" {
  name                  = "evgs-utilization-${random_string.unique.result}"
  scope                 = azurerm_storage_account.cost_export.id
  event_delivery_schema = "EventGridSchema"

  included_event_types = [
    "Microsoft.Storage.BlobCreated"
  ]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/${azapi_resource.utilization_container.name}/blobs/${local.utilization_directory_name}/"
    subject_ends_with   = ".csv.gz"
  }

  storage_queue_endpoint {
    storage_account_id                    = azurerm_storage_account.cost_export.id
    queue_name                            = azapi_resource.utilization_data_queue.name
    queue_message_time_to_live_in_seconds = 604800
  }

  delivery_identity {
    type = "SystemAssigned"
  }

  depends_on = [
    azurerm_role_assignment.event_grid_queue_sender,
    azapi_resource.utilization_data_queue
  ]
}
