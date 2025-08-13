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