# Verifies management_group_id moves the carbon/Advisor role assignments and the BILLING_SCOPE app
# setting together, and defaults both to the Tenant Root management group.
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

# The auto-generated mock id is not a parseable virtual network resource id.
override_data {
  target = data.azurerm_virtual_network.existing
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
  }
}

# object_id / tenant_id are validated as UUIDs by the azuread provider. tenant_id doubles as the
# Tenant Root management group ID, which the default-scope assertions below expect.
override_data {
  target = data.azurerm_client_config.current
  values = {
    tenant_id = "00000000-0000-0000-0000-000000000001"
    object_id = "00000000-0000-0000-0000-000000000002"
  }
}

variables {
  virtual_network_name                = "vnet-test"
  virtual_network_resource_group_name = "rg-network-test"
  subnet_id                           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/pe"
  function_app_subnet_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/func"
  aws_account_id                      = "123456789012"
  aws_s3_bucket_name                  = "azure-cost-data"
  billing_account_ids                 = ["test-billing-account"]

  # manage_role_assignments is left at its default because these runs assert on the role
  # assignments. EA prunes the billing role lookups instead, which keeps check
  # "billing_reader_assignments" evaluable at plan.
  is_enterprise_customer = true
  enable_advisor_exports = true
}

run "defaults_to_tenant_root" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.carbon_optimization_reader[0].scope == "/providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000001"
    error_message = "Carbon Optimization Reader should be assigned at the Tenant Root management group by default"
  }
  assert {
    condition     = azurerm_role_assignment.advisor_recommendations_contributor[0].scope == "/providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000001"
    error_message = "Advisor Recommendations Contributor should be assigned at the Tenant Root management group by default"
  }
  assert {
    condition     = azurerm_function_app_flex_consumption.cost_export.app_settings["BILLING_SCOPE"] == "/providers/Microsoft.Management/managementGroups/00000000-0000-0000-0000-000000000001"
    error_message = "BILLING_SCOPE should be the Tenant Root management group by default"
  }
}

# The grants and the enumeration scope must move together, or the exporters enumerate subscriptions
# they have no permission to read.
run "child_management_group" {
  command = plan

  variables {
    management_group_id = "mg-platform"
  }

  assert {
    condition     = azurerm_role_assignment.carbon_optimization_reader[0].scope == "/providers/Microsoft.Management/managementGroups/mg-platform"
    error_message = "Carbon Optimization Reader should be assigned at the supplied management group"
  }
  assert {
    condition     = azurerm_role_assignment.advisor_recommendations_contributor[0].scope == "/providers/Microsoft.Management/managementGroups/mg-platform"
    error_message = "Advisor Recommendations Contributor should be assigned at the supplied management group"
  }
  assert {
    condition     = azurerm_function_app_flex_consumption.cost_export.app_settings["BILLING_SCOPE"] == "/providers/Microsoft.Management/managementGroups/mg-platform"
    error_message = "BILLING_SCOPE must follow management_group_id so the grants and the enumerated subscriptions stay in step"
  }
}

# A full resource ID would produce a doubled path in the scope, failing late at apply.
run "full_resource_id_fails_validation" {
  command = plan

  variables {
    management_group_id = "/providers/Microsoft.Management/managementGroups/mg-platform"
  }

  expect_failures = [var.management_group_id]
}
