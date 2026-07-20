locals {
  # Setting to true enables 'public' access to the Function App for the duration of the deployment. This is not recommended for production.
  deploy_from_external_network = true
}
provider "azurerm" {
  resource_providers_to_register = ["Microsoft.CostManagementExports", "Microsoft.App"]
  subscription_id                = var.subscription_id
  storage_use_azuread            = true
  features {}
}

# Create the resource group for networking
resource "azurerm_resource_group" "networking" {
  name     = var.network_resource_group_name
  location = var.location
}

# Create the virtual network
resource "azurerm_virtual_network" "this" {
  name                = var.vnet_name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.networking.location
  resource_group_name = azurerm_resource_group.networking.name
}

# Create the default subnet
resource "azurerm_subnet" "default" {
  name                 = var.default_subnet_name
  resource_group_name  = azurerm_resource_group.networking.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.0.0/24"]
}

# Create the function app subnet with delegation
resource "azurerm_subnet" "functionapp" {
  name                 = var.functionapp_subnet_name
  resource_group_name  = azurerm_resource_group.networking.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = ["10.0.1.0/24"]

  delegation {
    name = "Microsoft.App.environments"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }

  lifecycle {
    ignore_changes = [
      delegation[0].service_delegation[0].actions
    ]
  }
}

# Network security groups for the subnets. They have no custom rules here (the default
# rules deny inbound internet traffic), but associating an NSG with every subnet is best
# practice and lets you add rules later without re-architecting.
resource "azurerm_network_security_group" "default" {
  name                = "nsg-${var.default_subnet_name}"
  location            = azurerm_resource_group.networking.location
  resource_group_name = azurerm_resource_group.networking.name
}

resource "azurerm_network_security_group" "functionapp" {
  name                = "nsg-${var.functionapp_subnet_name}"
  location            = azurerm_resource_group.networking.location
  resource_group_name = azurerm_resource_group.networking.name
}

resource "azurerm_subnet_network_security_group_association" "default" {
  subnet_id                 = azurerm_subnet.default.id
  network_security_group_id = azurerm_network_security_group.default.id
}

resource "azurerm_subnet_network_security_group_association" "functionapp" {
  subnet_id                 = azurerm_subnet.functionapp.id
  network_security_group_id = azurerm_network_security_group.functionapp.id
}

module "cost_forwarding" {
  source = "../../"

  is_enterprise_customer              = true
  aws_s3_bucket_name                  = var.aws_s3_bucket_name
  aws_account_id                      = var.aws_account_id
  billing_account_ids                 = var.billing_account_ids
  subnet_id                           = azurerm_subnet.default.id
  function_app_subnet_id              = azurerm_subnet.functionapp.id
  virtual_network_name                = azurerm_virtual_network.this.name
  virtual_network_resource_group_name = azurerm_resource_group.networking.name
  location                            = var.location
  resource_group_name                 = var.resource_group_name
  deploy_from_external_network        = local.deploy_from_external_network

  depends_on = [azurerm_subnet.default, azurerm_subnet.functionapp]

  # Uncomment the following line if running in CI/CD with a service principal
  # current_principal_type = "ServicePrincipal"

  # Optional: override individual resource names.
  # Existing deployments should keep the defaults to avoid forced resource replacement.
  # custom_resource_names = {
  #   application_insights = "appi-func-cost-export-<suffix>"
  # }
}
