provider "azurerm" {
  # These need to be explicitly registered
  resource_providers_to_register = ["Microsoft.CostManagementExports", "Microsoft.App"]
  storage_use_azuread            = true
  features {}
}

module "example" {
  source = "../../"

  is_enterprise_customer = false # Set to true if you have Enterprise Agreement (EA) billing account(s).

  aws_account_id                      = "<aws-account-id>"
  aws_s3_bucket_name                  = "<aws-s3-bucket-name>"
  billing_account_ids                 = ["<billing-account-id>"] # List of billing account IDs
  subnet_id                           = "/subscriptions/<subscription-id>/resourceGroups/existing-infra/providers/Microsoft.Network/virtualNetworks/existing-vnet/subnets/<existing subnet name>"
  function_app_subnet_id              = "/subscriptions/<subscription-id>/resourceGroups/existing-infra/providers/Microsoft.Network/virtualNetworks/existing-vnet/subnets/<existing function app subnet name>"
  virtual_network_name                = "<existing vnet name>"
  virtual_network_resource_group_name = "<existing vnet resource group name>"

  resource_group_name = "rg-cost-export"

  # Setting to false or omitting this argument assumes that you have private GitHub runners configured in the existing virtual network. It is not recommended to set this to true in production
  deploy_from_external_network = false

  # Uncomment the following line if running in CI/CD with a service principal
  # current_principal_type = "ServicePrincipal"
}
