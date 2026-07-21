mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "azapi" {}

#region override resource
override_resource {
  target = random_string.unique
  values = {
    result = "test1234"
    id     = "test1234"
  }
}

override_resource {
  target = azurerm_user_assigned_identity.cost_export
  values = {
    principal_id = "00000000-0000-0000-0000-0000000000aa"
    id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-cost-export-test1234"
  }
}

# These runs use command = apply because the check reads data.azapi_resource_list.billing_role_assignments,
# whose depends_on defers the read to apply time - the check cannot be evaluated at plan. Under apply the
# mock azurerm/azapi providers hand out random computed IDs, and any resource that parses an ID it receives
# (role assignment scopes, diagnostic setting targets, private endpoint connections) rejects them. Pin every
# computed ID that feeds such a resource to a valid value, for both the plan and apply phases (so no
# override_during here). The log_analytics_workspace_id and existing_entra_application_client_id variables
# prune the workspace and Entra app subtrees so their IDs need no overrides.
override_resource {
  target = azurerm_resource_group.cost_export
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test"
  }
}

override_resource {
  target = azurerm_storage_account.cost_export
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.Storage/storageAccounts/stfocustest1234"
  }
}

override_resource {
  target = azurerm_storage_account.deployment
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.Storage/storageAccounts/stcostexdplytest1234"
  }
}

override_resource {
  target = azurerm_eventgrid_system_topic.storage_events
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.EventGrid/systemTopics/evgt-storage-test1234"
  }
}

override_resource {
  target = azurerm_service_plan.cost_export
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.Web/serverFarms/asp-cost-export"
  }
}

override_resource {
  target = azurerm_function_app_flex_consumption.cost_export
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.Web/sites/func-cost-export-test1234"
  }
}

override_resource {
  target = azapi_resource_action.add_role_assignment["test-billing-account"]
  values = {
    id = "/providers/Microsoft.Billing/billingAccounts/test-billing-account/billingRoleAssignments/00000000-0000-0000-0000-000000000000"
    output = {
      id = "/providers/Microsoft.Billing/billingAccounts/test-billing-account/billingRoleAssignments/00000000-0000-0000-0000-000000000000"
    }
  }
}

override_resource {
  target = azurerm_private_dns_zone.sites[0]
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net"
  }
}

override_resource {
  target = azurerm_private_dns_zone.blob[0]
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }
}

override_resource {
  target = azurerm_private_dns_zone.queue[0]
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
  }
}

override_resource {
  target = azurerm_private_dns_zone.file[0]
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.Network/privateDnsZones/privatelink.file.core.windows.net"
  }
}

override_resource {
  target = azurerm_private_dns_zone.table[0]
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.Network/privateDnsZones/privatelink.table.core.windows.net"
  }
}
#endregion

#region override data
override_data {
  target = data.azapi_resource_list.billing_role_definitions["test-billing-account"]
  values = {
    output = {
      value = [{
        id = "/providers/Microsoft.Billing/billingAccounts/test-billing-account/billingRoleDefinitions/00000000-0000-0000-0000-000000000000"
        properties = {
          roleName = "Billing account reader"
        }
      }]
    }
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
#endregion

variables {
  resource_group_name                 = "rg-focus-test"
  virtual_network_name                = "vnet-test"
  virtual_network_resource_group_name = "rg-network-test"
  subnet_id                           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/pe"
  function_app_subnet_id              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/func"
  aws_account_id                      = "123456789012"
  aws_s3_bucket_name                  = "azure-cost-data"
  billing_account_ids                 = ["test-billing-account"]

  # Use an existing workspace and a pre-created Entra app so the module skips creating the log
  # analytics workspace and the azuread app/service principal/role assignment - resources whose
  # mock-generated IDs would otherwise need overriding but are irrelevant to this check.
  log_analytics_workspace_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-focus-test/providers/Microsoft.OperationalInsights/workspaces/log-focus-test"
  existing_entra_application_client_id = "00000000-0000-0000-0000-0000000000bb"
  manage_entra_app_role_assignment     = false

  # Skip the function-code publish step: its provisioner shells out to the Azure CLI, which is
  # unavailable (and meaningless against mocked infrastructure) under terraform test.
  publish_function_code = false
}

run "check_fires_when_assignment_missing" {
  command = apply

  override_data {
    target = data.azapi_resource_list.billing_role_assignments["test-billing-account"]
    values = {
      output = {
        value = []
      }
    }
  }

  expect_failures = [
    check.billing_reader_assignments,
  ]
}

run "check_passes_when_assignment_present" {
  command = apply

  override_data {
    target = data.azapi_resource_list.billing_role_assignments["test-billing-account"]
    values = {
      output = {
        value = [{
          properties = {
            principalId = "00000000-0000-0000-0000-0000000000aa"
          }
        }]
      }
    }
  }
}
