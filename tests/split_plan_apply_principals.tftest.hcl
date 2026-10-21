# Verifies split plan/apply service principal detection.
#
# Each run is a plan against mocked providers (no real Azure calls):
#   1. Split detected       - deploying SP ends in '-plan' and an '-apply' twin exists: both own the
#                             Entra app, plan SP gets Reader data roles, apply SP gets Contributor.
#   2. No apply twin        - '-plan' SP but no '-apply' match: falls back to single-SP behaviour.
#   3. Name without suffix  - 'plan' appears mid-name only: no apply lookup is attempted.
#   4. Strict separation    - manage_entra_app_role_assignment = false: no Entra reads at all.

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

override_resource {
  target          = azurerm_user_assigned_identity.cost_export
  override_during = plan
  values = {
    principal_id = "00000000-0000-0000-0000-0000000000aa"
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-cost-export-test1234"
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

override_data {
  target = data.azuread_service_principal.plan
  values = {
    object_id    = "00000000-0000-0000-0000-000000000002"
    display_name = "sp-focus-Plan"
  }
}

variables {
  virtual_network_name                = "vnet-test"
  virtual_network_resource_group_name = "rg-network-test"
  subnet_id                           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/pe"
  function_app_subnet_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/func"
  aws_account_id                      = "123456789012"
  aws_s3_bucket_name                  = "azure-cost-data"
  current_principal_type              = "ServicePrincipal"

  # manage_role_assignments stays at its default (true) so the deployer grants exist. FOCUS exports
  # are disabled to drop the billing reader check, which cannot be evaluated at plan time.
  enable_focus_exports = false
  billing_account_ids  = []
}

# 1. '-plan' suffix (matched case-insensitively) with an '-apply' twin.
run "split_detected" {
  command = plan

  override_data {
    target = data.azuread_service_principals.apply
    values = {
      object_ids = ["00000000-0000-0000-0000-000000000003"]
    }
  }

  assert {
    condition     = one(data.azuread_service_principals.apply[0].display_names) == "sp-focus-apply"
    error_message = "The apply SP should be looked up by swapping the '-plan' suffix for '-apply'."
  }

  assert {
    condition     = local.has_separate_apply_sp
    error_message = "A separate apply SP should be detected."
  }

  assert {
    condition = toset(azuread_application.aws_app[0].owners) == toset([
      "00000000-0000-0000-0000-000000000002",
      "00000000-0000-0000-0000-000000000003",
    ])
    error_message = "Both plan and apply SPs should own the Entra app registration."
  }

  assert {
    condition     = azurerm_role_assignment.grant_deployer_cost_export_blob[0].role_definition_name == "Storage Blob Data Reader"
    error_message = "The plan SP should only get Storage Blob Data Reader."
  }

  assert {
    condition     = azurerm_role_assignment.grant_deployer_cost_export_queue[0].role_definition_name == "Storage Queue Data Reader"
    error_message = "The plan SP should only get Storage Queue Data Reader."
  }

  assert {
    condition     = azurerm_role_assignment.grant_deployer_apply_cost_export_blob[0].principal_id == "00000000-0000-0000-0000-000000000003"
    error_message = "The apply SP should get Storage Blob Data Contributor."
  }

  assert {
    condition     = azurerm_role_assignment.grant_deployer_apply_cost_export_queue[0].principal_id == "00000000-0000-0000-0000-000000000003"
    error_message = "The apply SP should get Storage Queue Data Contributor."
  }
}

# 2. '-plan' SP with no '-apply' twin: the lookup returns nothing and the module stays single-SP.
run "no_apply_twin_falls_back" {
  command = plan

  override_data {
    target = data.azuread_service_principals.apply
    values = {
      object_ids = []
    }
  }

  assert {
    condition     = !local.has_separate_apply_sp
    error_message = "With no apply SP found the module should behave as single-SP."
  }

  assert {
    condition     = azurerm_role_assignment.grant_deployer_cost_export_blob[0].role_definition_name == "Storage Blob Data Contributor"
    error_message = "The single deploying SP should keep Storage Blob Data Contributor."
  }

  assert {
    condition     = length(azurerm_role_assignment.grant_deployer_apply_cost_export_blob) == 0
    error_message = "No apply SP grants should be created without an apply SP."
  }
}

# 3. 'plan' only appears mid-name, so it is not a split pipeline and no lookup is attempted.
run "plan_mid_name_not_matched" {
  command = plan

  override_data {
    target = data.azuread_service_principal.plan
    values = {
      object_id    = "00000000-0000-0000-0000-000000000002"
      display_name = "sp-planning-team"
    }
  }

  assert {
    condition     = length(data.azuread_service_principals.apply) == 0
    error_message = "No apply SP lookup should happen unless the name ends in '-plan'."
  }

  assert {
    condition     = !local.has_separate_apply_sp
    error_message = "The module should behave as single-SP."
  }
}

# 4. Strict separation: the module must not read the directory, so no split detection either.
run "strict_separation_no_entra_reads" {
  command = plan

  variables {
    existing_entra_application_client_id = "11111111-1111-1111-1111-111111111111"
    manage_entra_app_role_assignment     = false
  }

  assert {
    condition     = length(data.azuread_service_principal.plan) == 0
    error_message = "No plan SP lookup should happen in strict separation mode."
  }

  assert {
    condition     = length(data.azuread_service_principals.apply) == 0
    error_message = "No apply SP lookup should happen in strict separation mode."
  }

  assert {
    condition     = azurerm_role_assignment.grant_deployer_cost_export_blob[0].role_definition_name == "Storage Blob Data Contributor"
    error_message = "The deploying SP should keep Storage Blob Data Contributor."
  }
}
