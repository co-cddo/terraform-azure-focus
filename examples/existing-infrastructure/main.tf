provider "azurerm" {
  resource_providers_to_register = ["Microsoft.CostManagementExports", "Microsoft.App"]
  subscription_id                = var.subscription_id
  features {}
}

locals {
  # Setting to true enables 'public' access to the Function App for the duration of the deployment. This is not recommended for production.
  deploy_from_external_network = true
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "aws_s3_bucket_name" {
  description = "Name of the AWS S3 bucket to store cost data"
  type        = string
}

variable "aws_account_id" {
  description = "AWS IAM role ARN for cross-account access"
  type        = string
}

variable "billing_account_ids" {
  description = "List of billing account IDs to create FOCUS cost exports for"
  type        = list(string)
}

variable "existing_resource_group_name" {
  description = "Name of the existing resource group containing the VNet"
  type        = string
  default     = "existing-infra"
}

variable "existing_vnet_name" {
  description = "Name of the existing virtual network"
  type        = string
  default     = "existing-vnet"
}

variable "default_subnet_name" {
  description = "Name of the existing default subnet"
  type        = string
  default     = "default"
}

variable "functionapp_subnet_name" {
  description = "Name of the existing function app subnet"
  type        = string
  default     = "functionapp"
}

variable "location" {
  description = "Azure region for the cost forwarding resources"
  type        = string
  default     = "uksouth"
}

variable "resource_group_name" {
  description = "Name of the resource group to create for cost forwarding resources"
  type        = string
  default     = "rg-cost-export"
}

# Create the resource group for existing infrastructure
resource "azurerm_resource_group" "existing" {
  name     = var.existing_resource_group_name
  location = var.location
}

# Create the virtual network
resource "azurerm_virtual_network" "existing" {
  name                = var.existing_vnet_name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.existing.location
  resource_group_name = azurerm_resource_group.existing.name
}

# Create the default subnet
resource "azurerm_subnet" "default" {
  name                 = var.default_subnet_name
  resource_group_name  = azurerm_resource_group.existing.name
  virtual_network_name = azurerm_virtual_network.existing.name
  address_prefixes     = ["10.0.0.0/24"]
}

# Create the function app subnet with delegation
resource "azurerm_subnet" "functionapp" {
  name                 = var.functionapp_subnet_name
  resource_group_name  = azurerm_resource_group.existing.name
  virtual_network_name = azurerm_virtual_network.existing.name
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
  location            = azurerm_resource_group.existing.location
  resource_group_name = azurerm_resource_group.existing.name
}

resource "azurerm_network_security_group" "functionapp" {
  name                = "nsg-${var.functionapp_subnet_name}"
  location            = azurerm_resource_group.existing.location
  resource_group_name = azurerm_resource_group.existing.name
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
  virtual_network_name                = azurerm_virtual_network.existing.name
  virtual_network_resource_group_name = azurerm_resource_group.existing.name
  location                            = var.location
  resource_group_name                 = var.resource_group_name
  deploy_from_external_network        = local.deploy_from_external_network
  backfill_start_date                 = "2022-01-01"
  logging_level                       = "INFO"
  cost_mgmt_suffix                    = "dev"

  depends_on = [azurerm_subnet.default, azurerm_subnet.functionapp]
}
