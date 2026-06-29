# Verifies the custom_resource_names feature by performing a plan with and without populating this object with custom resource names
mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "azapi" {}

# Pin the random suffix so the module's default names are deterministic. This is the
# only definition of the suffix; the custom names below reuse it via the
# random_string_suffix output of the default run.
override_resource {
  target          = random_string.unique
  override_during = plan
  values = {
    result = "test1234"
  }
}

# The auto-generated mock id is not a parseable virtual network resource id, which the
# azurerm provider rejects when it is used as a private DNS zone link target.
override_data {
  target = data.azurerm_virtual_network.existing
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
  }
}

# object_id / tenant_id are validated as UUIDs by the azuread provider (Entra app owners).
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
  billing_account_ids                 = ["test-billing-account"]
  manage_role_assignments             = false
}

# Let the module generate its own names (suffix pinned). resource_names and
# random_string_suffix from this run feed the comparison run below.
run "without_custom_names" {
  command = plan
}

# Supplying custom_resource_names that reproduce each default pattern (reusing the
# generated suffix) must yield an identical names map. If any default prefix changes
# without the patterns below being updated to match, this comparison fails.
run "with_custom_names" {
  command = plan

  variables {
    custom_resource_names = {
      storage_account_cost_export = "stcostexport${run.without_custom_names.random_string_suffix}"
      storage_account_deployment  = "stcostexdply${run.without_custom_names.random_string_suffix}"
      service_plan                = "asp-cost-export"
      user_assigned_identity      = "id-cost-export-${run.without_custom_names.random_string_suffix}"
      function_app                = "func-cost-export-${run.without_custom_names.random_string_suffix}"
      application_insights        = "ai-func-cost-export-${run.without_custom_names.random_string_suffix}"
      log_analytics_workspace     = "log-cost-export-${run.without_custom_names.random_string_suffix}"
      event_grid_system_topic     = "evgt-storage-${run.without_custom_names.random_string_suffix}"
      event_grid_subscription     = "evgs-blob-created-${run.without_custom_names.random_string_suffix}"
      entra_application           = "cost-export-${run.without_custom_names.random_string_suffix}"
      cost_export_prefix          = "focus-daily-cost-export"
      private_endpoints = {
        storage_blob    = "pe-storage-cost-export"
        storage_queue   = "pe-storage-queue-cost-export"
        deployment_blob = "pe-storage-cost-export-deployment"
        function_app    = "pe-func-cost-export"
      }
      private_service_connections = {
        storage_blob    = "psc-storage-cost-export"
        storage_queue   = "psc-storage-queue-cost-export"
        deployment_blob = "psc-storage-cost-export-deployment"
        function_app    = "psc-func-cost-export"
      }
    }
  }

  assert {
    condition     = output.resource_names == run.without_custom_names.resource_names
    error_message = "Resource names in this plan should match automatically generated resource names in the plan above"
  }
}
