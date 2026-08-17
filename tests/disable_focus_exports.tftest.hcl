# Verifies that setting enable_focus_exports = false skips all FOCUS cost export infrastructure
# while keeping the function app and shared resources intact. This supports multi-tenant
# deployments where only one tenant should create exports per billing account.
mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "azapi" {}

override_resource {
  target          = random_string.unique
  override_during = plan
  values = {
    result = "test1234"
  }
}

override_data {
  target = data.azurerm_virtual_network.existing
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
  }
}

override_data {
  target = data.azurerm_client_config.current
  values = {
    tenant_id = "00000000-0000-0000-0000-000000000001"
    object_id = "00000000-0000-0000-0000-000000000002"
  }
}

variables {
  resource_group_name                 = "rg-focus-test"
  virtual_network_name                = "vnet-test"
  virtual_network_resource_group_name = "rg-network-test"
  subnet_id                           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/pe"
  function_app_subnet_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/func"
  aws_account_id                      = "123456789012"
  aws_s3_bucket_name                  = "azure-cost-data"
  billing_account_ids                 = []
  enable_focus_exports                = false
  is_enterprise_customer              = true
}

run "focus_exports_disabled_skips_cost_export_infra" {
  command = plan

  assert {
    condition     = length(azurerm_storage_account.cost_export) == 0
    error_message = "Cost export storage account should not be created when enable_focus_exports is false"
  }
  assert {
    condition     = length(azapi_resource.cost_export) == 0
    error_message = "Cost export blob container should not be created when enable_focus_exports is false"
  }
  assert {
    condition     = length(azapi_resource.cost_data_queue) == 0
    error_message = "Cost data queue should not be created when enable_focus_exports is false"
  }
  assert {
    condition     = length(azurerm_eventgrid_system_topic.storage_events) == 0
    error_message = "Event Grid system topic should not be created when enable_focus_exports is false"
  }
  assert {
    condition     = length(azurerm_eventgrid_event_subscription.focus_blob_created) == 0
    error_message = "Event Grid subscription should not be created when enable_focus_exports is false"
  }
  assert {
    condition     = length(azurerm_private_endpoint.storage) == 0
    error_message = "Cost export storage blob private endpoint should not be created when enable_focus_exports is false"
  }
  assert {
    condition     = length(azurerm_private_endpoint.storage_queue) == 0
    error_message = "Cost export storage queue private endpoint should not be created when enable_focus_exports is false"
  }
  assert {
    condition     = length(azapi_resource.daily_cost_export) == 0
    error_message = "Daily cost export should not be created when enable_focus_exports is false"
  }
}

run "focus_exports_disabled_keeps_function_app" {
  command = plan

  assert {
    condition     = azurerm_function_app_flex_consumption.cost_export.name == "func-cost-export-test1234"
    error_message = "Function app should still be created when enable_focus_exports is false"
  }
  assert {
    condition     = azurerm_service_plan.cost_export.name == "asp-cost-export"
    error_message = "Service plan should still be created when enable_focus_exports is false"
  }
  assert {
    condition     = azurerm_private_endpoint.deployment.name == "pe-storage-cost-export-deployment"
    error_message = "Deployment storage private endpoint should still be created when enable_focus_exports is false"
  }
  assert {
    condition     = azurerm_private_endpoint.function_app.name == "pe-func-cost-export"
    error_message = "Function app private endpoint should still be created when enable_focus_exports is false"
  }
}

run "focus_exports_disabled_outputs_null" {
  command = plan

  assert {
    condition     = output.focus_container_name == null
    error_message = "focus_container_name should be null when enable_focus_exports is false"
  }
  assert {
    condition     = output.cost_export_storage_account_name == null
    error_message = "cost_export_storage_account_name should be null when enable_focus_exports is false"
  }
  assert {
    condition     = output.cost_export_storage_account_id == null
    error_message = "cost_export_storage_account_id should be null when enable_focus_exports is false"
  }
  assert {
    condition     = output.event_grid_system_topic_name == null
    error_message = "event_grid_system_topic_name should be null when enable_focus_exports is false"
  }
  assert {
    condition     = output.event_grid_subscription_name == null
    error_message = "event_grid_subscription_name should be null when enable_focus_exports is false"
  }
  assert {
    condition     = output.storage_private_endpoint_ip == null
    error_message = "storage_private_endpoint_ip should be null when enable_focus_exports is false"
  }
  assert {
    condition     = output.storage_queue_private_endpoint_ip == null
    error_message = "storage_queue_private_endpoint_ip should be null when enable_focus_exports is false"
  }
  assert {
    condition     = output.billing_role_assignment_manual_action_required == ""
    error_message = "billing_role_assignment_manual_action_required should be empty when enable_focus_exports is false"
  }
}
