terraform {
  required_version = ">= 1.0"
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
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}