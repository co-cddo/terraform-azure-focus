resource "azurerm_eventgrid_system_topic" "storage_events" {
  count = var.enable_focus_exports ? 1 : 0

  name                = local.names.event_grid_system_topic
  resource_group_name = local.resource_group_name
  location            = local.resource_group_location
  source_resource_id  = azurerm_storage_account.cost_export[0].id
  topic_type          = "Microsoft.Storage.StorageAccounts"

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "storage_events" {
  count = var.enable_focus_exports ? 1 : 0

  name                       = local.names.diag_event_grid
  target_resource_id         = azurerm_eventgrid_system_topic.storage_events[0].id
  log_analytics_workspace_id = local.effective_log_analytics_workspace_id

  # Delivery/publish failures here mean a created cost-export blob never reached the queue and
  # so was never processed - a likely culprit when expected cost data is missing downstream.
  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_eventgrid_event_subscription" "focus_blob_created" {
  count = var.enable_focus_exports ? 1 : 0

  name                  = local.names.event_grid_subscription
  scope                 = azurerm_storage_account.cost_export[0].id
  event_delivery_schema = "EventGridSchema"

  included_event_types = [
    "Microsoft.Storage.BlobCreated"
  ]

  subject_filter {
    subject_begins_with = "/blobServices/default/containers/${azapi_resource.cost_export[0].name}/blobs/${local.focus_directory_name}/"
    subject_ends_with   = ".parquet"
  }

  storage_queue_endpoint {
    storage_account_id                    = azurerm_storage_account.cost_export[0].id
    queue_name                            = azapi_resource.cost_data_queue[0].name
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
