provider "azurerm" {
  # These need to be explicitly registered
  resource_providers_to_register = ["Microsoft.CostManagementExports", "Microsoft.App"]
  # The cost_export storage account disables shared access keys, so the provider must
  # authenticate to the storage data plane with Entra ID instead of account keys.
  # Without this, post-create data-plane polls fail with KeyBasedAuthenticationNotPermitted (403).
  storage_use_azuread = true
  features {}
}

module "example" {
  source = "../../"

  is_enterprise_customer              = false
  aws_account_id                      = "<aws-account-id>"
  billing_account_ids                 = ["<billing-account-id>"] # List of billing account IDs
  subnet_id                           = "/subscriptions/<subscription-id>/resourceGroups/existing-infra/providers/Microsoft.Network/virtualNetworks/existing-vnet/subnets/default"
  function_app_subnet_id              = "/subscriptions/<subscription-id>/resourceGroups/existing-infra/providers/Microsoft.Network/virtualNetworks/existing-vnet/subnets/functionapp"
  virtual_network_name                = "existing-vnet"
  virtual_network_resource_group_name = "existing-infra"
  resource_group_name                 = "rg-cost-export"
  # Setting to false or omitting this argument assumes that you have private GitHub runners configured in the existing virtual network. It is not recommended to set this to true in production
  deploy_from_external_network = false

  backfill_start_date = "2022-01-01"
  logging_level       = "DEBUG" # INFO (default) or DEBUG

  # only provide a suffix if deploying multiple modules into the same tenant (Cost Mgmt is common to all deployments)
  # must still provide billing account for the module. If you only have one billing account for the tenant
  # then each deployed Cost Mgmt Export jobs will write the same cost export to target (S3); no conflict.
  cost_mgmt_suffix = "dev"

  # Uncomment the following line if running in CI/CD with a service principal
  # current_principal_type = "ServicePrincipal"
}
