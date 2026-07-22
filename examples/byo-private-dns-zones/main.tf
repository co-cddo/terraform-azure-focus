provider "azurerm" {
  # These need to be explicitly registered
  resource_providers_to_register = ["Microsoft.CostManagementExports", "Microsoft.App"]
  features {}
}

module "example" {
  source = "../../"

  is_enterprise_customer              = false
  aws_s3_bucket_name                  = "<aws s3 bucket name>"
  aws_account_id                      = "<aws-account-id>"
  billing_account_ids                 = ["<billing-account-id>"] # List of billing account IDs
  subnet_id                           = "/subscriptions/<subscription-id>/resourceGroups/existing-infra/providers/Microsoft.Network/virtualNetworks/existing-vnet/subnets/default"
  function_app_subnet_id              = "/subscriptions/<subscription-id>/resourceGroups/existing-infra/providers/Microsoft.Network/virtualNetworks/existing-vnet/subnets/functionapp"
  virtual_network_name                = "existing-vnet"
  virtual_network_resource_group_name = "existing-infra"
  resource_group_name                 = "rg-cost-export"
  deploy_from_external_network        = false

  private_endpoints_manage_dns_zone_group = true
  use_existing_private_dns_zones          = true

  existing_private_dns_zone_ids = {
    blob  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    queue = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
    sites = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net"
  }

  backfill_start_date = "2022-01-01"
  logging_level       = "INFO" # INFO (default) or DEBUG
  cost_mgmt_suffix    = "dev"

  # Uncomment the following line if running in CI/CD with a service principal
  # current_principal_type = "ServicePrincipal"
}
