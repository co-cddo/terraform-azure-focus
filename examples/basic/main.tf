provider "azurerm" {
  resource_providers_to_register = ["Microsoft.CostManagementExports", "Microsoft.App"]
  features {}
}

module "example" {
  name                                = "terraform-azurerm-cost-forwarding"
  source                              = "git::https://github.com/appvia/terraform-azurerm-cost-forwarding?ref=20e97b77949824307985be00dbb1def7b0c11a4c" # release v0.0.2
  aws_target_file_path                = "s3://<your-s3-bucket>/<your-path>/"
  aws_role_arn                        = "arn:aws:iam::<aws-account-id>:role/<your-cost-export-role>"
  report_scope                        = "/providers/Microsoft.Billing/billingAccounts/<billing-account-id>:<billing-profile-id>_2019-05-31"
  subnet_id                           = "/subscriptions/<subscription-id>/resourceGroups/existing-infra/providers/Microsoft.Network/virtualNetworks/existing-vnet/subnets/default"
  function_app_subnet_id              = "/subscriptions/<subscription-id>/resourceGroups/existing-infra/providers/Microsoft.Network/virtualNetworks/existing-vnet/subnets/functionapp"
  virtual_network_name                = "existing-vnet"
  virtual_network_resource_group_name = "existing-infra"
  location                            = "uksouth"
  resource_group_name                 = "rg-cost-export"
  # Setting to false or omitting this argument assumes that you have private GitHub runners configured in the existing virtual network. It is not recommended to set this to true in production
  deploy_from_external_network        = false
}