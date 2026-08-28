# Verifies that setting enable_advisor_exports = false and enable_carbon_exports = false
# disables the respective Azure Functions and RBAC role assignments while keeping the
# function app and shared resources intact.
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
  billing_account_ids                 = ["test-billing-account"]
  is_enterprise_customer              = true
  enable_advisor_exports              = false
  enable_carbon_exports               = false
}

run "advisor_disabled_skips_rbac" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.advisor_recommendations_contributor) == 0
    error_message = "Advisor Recommendations Contributor role should not be created when enable_advisor_exports is false"
  }
}

run "carbon_disabled_skips_rbac" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.carbon_optimization_reader) == 0
    error_message = "Carbon Optimization Reader role should not be created when enable_carbon_exports is false"
  }
}

run "function_app_still_created" {
  command = plan

  assert {
    condition     = azurerm_function_app_flex_consumption.cost_export.name == "func-cost-export-test1234"
    error_message = "Function app should still be created when advisor and carbon exports are disabled"
  }
}

run "advisor_function_disabled_via_app_settings" {
  command = plan

  assert {
    condition     = azurerm_function_app_flex_consumption.cost_export.app_settings["AzureWebJobs.AdvisorRecommendationsExporter.Disabled"] == "1"
    error_message = "AdvisorRecommendationsExporter should be disabled via app settings when enable_advisor_exports is false"
  }
}

run "carbon_functions_disabled_via_app_settings" {
  command = plan

  assert {
    condition     = azurerm_function_app_flex_consumption.cost_export.app_settings["AzureWebJobs.CarbonEmissionsExporter.Disabled"] == "1"
    error_message = "CarbonEmissionsExporter should be disabled via app settings when enable_carbon_exports is false"
  }
  assert {
    condition     = azurerm_function_app_flex_consumption.cost_export.app_settings["AzureWebJobs.CarbonEmissionsBackfill.Disabled"] == "1"
    error_message = "CarbonEmissionsBackfill should be disabled via app settings when enable_carbon_exports is false"
  }
  assert {
    condition     = azurerm_function_app_flex_consumption.cost_export.app_settings["AzureWebJobs.CarbonApiDateRangeInfo.Disabled"] == "1"
    error_message = "CarbonApiDateRangeInfo should be disabled via app settings when enable_carbon_exports is false"
  }
}

run "disabled_outputs_null" {
  command = plan

  assert {
    condition     = output.recommendations_export_name == null
    error_message = "recommendations_export_name should be null when enable_advisor_exports is false"
  }
  assert {
    condition     = output.carbon_export_name == null
    error_message = "carbon_export_name should be null when enable_carbon_exports is false"
  }
}
