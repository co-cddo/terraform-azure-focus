# Verifies the "bring your own DNS" behaviour: whether the module creates private DNS zones and
# virtual-network links, or defers to caller-supplied existing zones, across the four supported
# combinations of private_endpoints_manage_dns_zone_group / use_existing_private_dns_zones /
# link_existing_private_dns_zones_to_vnet - plus the input-validation guardrails on
# existing_private_dns_zone_ids. All runs are plan-only against mocked providers.
mock_provider "azurerm" {}
mock_provider "azuread" {}
mock_provider "azapi" {}

# Pin the random suffix so planning is deterministic (storage account names derive from it).
override_resource {
  target          = random_string.unique
  override_during = plan
  values = {
    result = "test1234"
  }
}

# The auto-generated mock id is not a parseable virtual network resource id, which the azurerm
# provider rejects when it is used as a private DNS zone virtual-network-link target.
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
  aws_s3_bucket_name                  = "azure-cost-data"
  billing_account_ids                 = ["test-billing-account"]
  manage_role_assignments             = false

  # Valid existing-zone ids, inherited by the "use existing" runs below. Present (but unused) in the
  # default run, where use_existing_private_dns_zones is false.
  existing_private_dns_zone_ids = {
    blob  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    queue = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
    sites = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net"
  }
}

# Default (use_existing_private_dns_zones = false): the module creates its own zones and links.
run "default_creates_private_dns_zones" {
  command = plan

  assert {
    condition     = length(azurerm_private_dns_zone.blob) == 1
    error_message = "blob private DNS zone should be created by default"
  }
  assert {
    condition     = length(azurerm_private_dns_zone.queue) == 1
    error_message = "queue private DNS zone should be created by default"
  }
  assert {
    condition     = length(azurerm_private_dns_zone.sites) == 1
    error_message = "sites (azurewebsites) private DNS zone should be created by default"
  }
  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.blob) == 1
    error_message = "blob DNS zone vnet link should be created by default"
  }
  # Every private endpoint should carry a private_dns_zone_group when the module manages DNS.
  assert {
    condition     = length(azurerm_private_endpoint.storage[0].private_dns_zone_group) == 1 && length(azurerm_private_endpoint.storage_queue[0].private_dns_zone_group) == 1 && length(azurerm_private_endpoint.deployment.private_dns_zone_group) == 1 && length(azurerm_private_endpoint.function_app.private_dns_zone_group) == 1
    error_message = "each private endpoint should have a private_dns_zone_group when private_endpoints_manage_dns_zone_group is true"
  }
  # use_existing=false => deployment storage stays private (no need to relax public access).
  assert {
    condition     = azurerm_storage_account.deployment.public_network_access_enabled == false
    error_message = "deployment storage public access should remain disabled when the module manages DNS zones"
  }
}

# BYO DNS with a Private DNS Resolver hub (use_existing = true, link = false): the module must
# create NO zones and NO vnet links - the zones live centrally and are already linked to the VNet.
run "byo_resolver_creates_no_zones_or_links" {
  command = plan

  variables {
    use_existing_private_dns_zones          = true
    link_existing_private_dns_zones_to_vnet = false
  }

  assert {
    condition     = length(azurerm_private_dns_zone.blob) == 0
    error_message = "blob private DNS zone must NOT be created when using existing zones"
  }
  assert {
    condition     = length(azurerm_private_dns_zone.queue) == 0
    error_message = "queue private DNS zone must NOT be created when using existing zones"
  }
  assert {
    condition     = length(azurerm_private_dns_zone.sites) == 0
    error_message = "sites private DNS zone must NOT be created when using existing zones"
  }
  assert {
    condition     = length(azurerm_private_dns_zone.file) == 0 && length(azurerm_private_dns_zone.table) == 0
    error_message = "legacy file/table private DNS zones must NOT be created when using existing zones"
  }
  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.blob) == 0 && length(azurerm_private_dns_zone_virtual_network_link.queue) == 0 && length(azurerm_private_dns_zone_virtual_network_link.sites) == 0
    error_message = "no vnet links should be created when zones are resolver-managed and link_existing_private_dns_zones_to_vnet is false"
  }
  assert {
    condition     = output.private_dns_zones["blob"].managed_by_module == false
    error_message = "existing zones must be reported as not managed by the module"
  }
  assert {
    condition     = output.private_dns_zones["blob"].id == var.existing_private_dns_zone_ids["blob"]
    error_message = "effective blob zone id should be the caller-supplied existing zone id"
  }
  # The private endpoints still get a zone group - it just points at the caller's existing zones.
  assert {
    condition     = contains(one(azurerm_private_endpoint.storage[0].private_dns_zone_group).private_dns_zone_ids, var.existing_private_dns_zone_ids["blob"])
    error_message = "blob private endpoint DNS zone group should reference the caller-supplied blob zone"
  }
  assert {
    condition     = contains(one(azurerm_private_endpoint.function_app.private_dns_zone_group).private_dns_zone_ids, var.existing_private_dns_zone_ids["sites"])
    error_message = "function app private endpoint DNS zone group should reference the caller-supplied sites zone"
  }
  # With a resolver hub the module cannot reach the storage private endpoints for its apply-time
  # data-plane reads, so deployment storage public access is relaxed. This guards that coupling.
  assert {
    condition     = azurerm_storage_account.deployment.public_network_access_enabled == true
    error_message = "deployment storage public access should be enabled in the resolver (unlinked existing zones) scenario"
  }
}

# BYO existing zones that the module SHOULD link to the VNet (use_existing = true, link = true):
# still no zones created, but blob/queue/sites vnet links are.
run "byo_existing_zones_linked_to_vnet" {
  command = plan

  variables {
    use_existing_private_dns_zones          = true
    link_existing_private_dns_zones_to_vnet = true
  }

  assert {
    condition     = length(azurerm_private_dns_zone.blob) == 0 && length(azurerm_private_dns_zone.queue) == 0 && length(azurerm_private_dns_zone.sites) == 0
    error_message = "existing zones must not be recreated even when linking them to the VNet"
  }
  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.blob) == 1 && length(azurerm_private_dns_zone_virtual_network_link.queue) == 1 && length(azurerm_private_dns_zone_virtual_network_link.sites) == 1
    error_message = "blob/queue/sites vnet links should be created when link_existing_private_dns_zones_to_vnet is true"
  }
  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.file) == 0 && length(azurerm_private_dns_zone_virtual_network_link.table) == 0
    error_message = "legacy file/table links must not be created for existing zones"
  }
  assert {
    condition     = azurerm_storage_account.deployment.public_network_access_enabled == false
    error_message = "deployment storage public access should stay disabled when existing zones are linked to the VNet"
  }
}

# DNS integration disabled entirely (private_endpoints_manage_dns_zone_group = false): the module
# creates no zones and no links, and surfaces an empty effective-zone map for external tooling.
run "dns_management_disabled" {
  command = plan

  variables {
    private_endpoints_manage_dns_zone_group = false
  }

  assert {
    condition     = length(azurerm_private_dns_zone.blob) == 0 && length(azurerm_private_dns_zone.queue) == 0 && length(azurerm_private_dns_zone.sites) == 0
    error_message = "no private DNS zones should be created when private_endpoints_manage_dns_zone_group is false"
  }
  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.blob) == 0 && length(azurerm_private_dns_zone_virtual_network_link.queue) == 0 && length(azurerm_private_dns_zone_virtual_network_link.sites) == 0
    error_message = "no vnet links should be created when private_endpoints_manage_dns_zone_group is false"
  }
  assert {
    condition     = length(output.private_dns_zones) == 0
    error_message = "private_dns_zones output should be empty when DNS integration is disabled"
  }
  # With DNS management off, the private endpoints must be created WITHOUT a zone group (records
  # are expected to be handled externally, e.g. by Azure Policy).
  assert {
    condition     = length(azurerm_private_endpoint.storage[0].private_dns_zone_group) == 0 && length(azurerm_private_endpoint.storage_queue[0].private_dns_zone_group) == 0 && length(azurerm_private_endpoint.deployment.private_dns_zone_group) == 0 && length(azurerm_private_endpoint.function_app.private_dns_zone_group) == 0
    error_message = "no private endpoint should have a private_dns_zone_group when private_endpoints_manage_dns_zone_group is false"
  }
}

# Guardrail: using existing zones without supplying every required key must fail validation.
run "byo_missing_zone_key_fails" {
  command = plan

  variables {
    use_existing_private_dns_zones = true
    existing_private_dns_zone_ids = {
      blob  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
      queue = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
      # sites deliberately omitted
    }
  }

  expect_failures = [var.existing_private_dns_zone_ids]
}

# Guardrail: a supplied zone id whose zone name does not match its key must fail validation
# (here the blob key points at a queue privatelink zone).
run "byo_wrong_zone_name_fails" {
  command = plan

  variables {
    use_existing_private_dns_zones = true
    existing_private_dns_zone_ids = {
      blob  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
      queue = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
      sites = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net"
    }
  }

  expect_failures = [var.existing_private_dns_zone_ids]
}
