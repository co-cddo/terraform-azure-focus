data "azurerm_client_config" "current" {}

data "azurerm_virtual_network" "existing" {
  name                = var.virtual_network_name
  resource_group_name = var.virtual_network_resource_group_name
}

# Note: Billing accounts are now provided as input variables instead of being enumerated

# Get current public IP for external deployment
# data "http" "current_ip" {
#   count = var.deploy_from_external_network ? 1 : 0
#   url   = "https://api.ipify.org?format=text"
# }

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