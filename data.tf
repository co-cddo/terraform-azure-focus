data "azurerm_client_config" "current" {}

data "azurerm_virtual_network" "existing" {
  name                = var.virtual_network_name
  resource_group_name = var.virtual_network_resource_group_name
}

data "archive_file" "function" {
  type        = "zip"
  source_dir  = "${path.module}/src/cost_export"
  output_path = "${path.module}/cost_export.zip"

  excludes = [
    "__pycache__",
    "*.pyc",
    "*.pyo",
    ".pytest_cache",
    ".DS_Store",
    "*.log"
  ]
}
