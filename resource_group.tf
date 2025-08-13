resource "azurerm_resource_group" "cost_export" {
  name     = var.resource_group_name
  location = var.location
}

resource "random_string" "unique" {
  length  = 8
  special = false
  upper   = false
}

resource "random_uuid" "app_uuid" {}

resource "time_static" "recurrence" {}