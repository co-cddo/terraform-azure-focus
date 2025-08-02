
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    # tflint-ignore: terraform_unused_required_providers
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.14.0"
    }
  }
}
