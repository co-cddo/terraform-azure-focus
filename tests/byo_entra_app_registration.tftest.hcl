# Verifies the "bring your own Entra app registration" feature (separation of duties).
#
# Three scenarios, each a plan against mocked providers (no real Azure calls):
#   1. Default          - the module creates the app registration, SP and app-role binding.
#   2. Bring your own    - a client id is supplied, so the module creates none of the app
#                          registration but still manages the app-role binding.
#   3. Strict separation - as (2) but manage_entra_app_role_assignment = false, so the module
#                          performs NO Entra writes/reads and emits the manual-action output.

mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "azapi" {}

# Pin the random suffix so the plan is deterministic (see the custom-naming test).
override_resource {
  target          = random_string.unique
  override_during = plan
  values = {
    result = "test1234"
  }
}

# Pin the function app managed identity's principal id so the strict-separation manual-action
# output (which interpolates it) is fully known at plan time and can be asserted on. A valid-format
# resource id must also be supplied, since the function app validates identity_ids.
override_resource {
  target          = azurerm_user_assigned_identity.cost_export
  override_during = plan
  values = {
    principal_id = "00000000-0000-0000-0000-0000000000aa"
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-cost-export-test1234"
  }
}

# The auto-generated mock id is not a parseable virtual network resource id.
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

# 1. Default: no existing app supplied, so the module creates everything itself.
run "module_creates_entra_app_by_default" {
  command = plan

  assert {
    condition     = length(azuread_application.aws_app) == 1
    error_message = "By default the module should create the Entra app registration."
  }

  assert {
    condition     = length(azuread_service_principal.aws_app) == 1
    error_message = "By default the module should create the service principal."
  }

  assert {
    condition     = length(azuread_app_role_assignment.aws_app) == 1
    error_message = "By default the module should create the app-role assignment."
  }

  assert {
    condition     = length(data.azuread_service_principal.existing_aws_app) == 0
    error_message = "The existing-SP lookup must not run when the module creates its own app."
  }

  assert {
    condition     = output.entra_app_role_assignment_manual_action_required == ""
    error_message = "No manual action should be required when the module manages the binding."
  }
}

# 2. Bring your own app registration, but let the module manage the app-role binding.
run "byo_app_module_manages_binding" {
  command = plan

  variables {
    existing_entra_application_client_id = "11111111-1111-1111-1111-111111111111"
    manage_entra_app_role_assignment     = true
  }

  # The module resolves the supplied app's SP by a directory read; give it deterministic values.
  override_data {
    target = data.azuread_service_principal.existing_aws_app
    values = {
      object_id    = "22222222-2222-2222-2222-222222222222"
      app_role_ids = { AssumeRoleWithWebIdentity = "33333333-3333-3333-3333-333333333333" }
    }
  }

  assert {
    condition     = length(azuread_application.aws_app) == 0
    error_message = "The module must not create an app registration when one is supplied."
  }

  assert {
    condition     = length(azuread_service_principal.aws_app) == 0
    error_message = "The module must not create a service principal when an app is supplied."
  }

  assert {
    condition     = length(data.azuread_service_principal.existing_aws_app) == 1
    error_message = "The module should look up the supplied app's service principal."
  }

  assert {
    condition     = length(azuread_app_role_assignment.aws_app) == 1
    error_message = "The module should still create the app-role assignment in this mode."
  }

  assert {
    condition     = output.aws_app_client_id == "11111111-1111-1111-1111-111111111111"
    error_message = "aws_app_client_id output should echo the supplied client id."
  }
}

# 3. Bring your own app + strict separation: the module performs no Entra writes or reads.
run "byo_app_strict_separation" {
  command = plan

  variables {
    existing_entra_application_client_id = "11111111-1111-1111-1111-111111111111"
    manage_entra_app_role_assignment     = false
  }

  assert {
    condition     = length(azuread_application.aws_app) == 0
    error_message = "No app registration should be created in strict separation mode."
  }

  assert {
    condition     = length(azuread_app_role_assignment.aws_app) == 0
    error_message = "No app-role assignment should be created in strict separation mode."
  }

  assert {
    condition     = length(data.azuread_service_principal.existing_aws_app) == 0
    error_message = "No directory read should happen in strict separation mode."
  }

  assert {
    condition     = output.entra_app_role_assignment_manual_action_required != ""
    error_message = "The manual-action output should be populated in strict separation mode."
  }
}
