terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "> 2.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 1.7.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.7.0"
    }
  }
}