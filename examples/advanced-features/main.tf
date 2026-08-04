provider "azurerm" {
  # These need to be explicitly registered
  resource_providers_to_register = ["Microsoft.CostManagementExports", "Microsoft.App"]
  storage_use_azuread            = true
  features {}
}

module "example" {
  source = "../../"

  is_enterprise_customer = true # Comment out or set to false if you do not have an Enterprise Agreement (EA) billing account(s).

  aws_account_id                      = "<aws-account-id>"
  aws_s3_bucket_name                  = "<aws-s3-bucket-name>"
  billing_account_ids                 = ["<billing-account-id>"] # List of billing account IDs
  subnet_id                           = "/subscriptions/<subscription-id>/resourceGroups/existing-infra/providers/Microsoft.Network/virtualNetworks/existing-vnet/subnets/<existing subnet name>"
  function_app_subnet_id              = "/subscriptions/<subscription-id>/resourceGroups/existing-infra/providers/Microsoft.Network/virtualNetworks/existing-vnet/subnets/<existing function app subnet name>"
  virtual_network_name                = "<existing vnet name>"
  virtual_network_resource_group_name = "<existing vnet resource group name>"

  resource_group_name = "rg-cost-export"

  # Comment out the following line if running in the security context of a user principal.
  current_principal_type = "ServicePrincipal"

  management_group_id = "alz"

  # Use a pre-existing Entra app registration for AWS OIDC federation.
  # The app must expose an 'AssumeRoleWithWebIdentity' app role and the
  # identifier URI 'api://<tenant-id>/GDS-AWS-Cost-Forwarding'.
  existing_entra_application_client_id = "00000000-0000-0000-0000-0000000000aa" # Substitute for your client ID here
  manage_entra_app_role_assignment     = false

  # Optional: bring your own private DNS zones instead of module-managed ones.
  use_existing_private_dns_zones = true
  # Set this to false if the VNet is already configured to resolve the private DNS zones. For example, you have a custom DNS configuration pointing to a hub network with linked private DNS zones.
  link_existing_private_dns_zones_to_vnet = false
  existing_private_dns_zone_ids = {
    blob  = "/subscriptions/<subscription id>/resourceGroups/<resource group name>/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    queue = "/subscriptions/<subscription id>/resourceGroups/<resource group name>/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
    sites = "/subscriptions/<subscription id>/resourceGroups/<resource group name>/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net"
  }

  # Optional: override individual resource names.
  # Existing deployments should keep the defaults to avoid forced resource replacement.
  custom_resource_names = {
    storage_account_cost_export = "stfocuscostmjw"
    storage_account_deployment  = "stfocusdeplmjw"
    service_plan                = "asp-focus-cost-mjw"
    user_assigned_identity      = "id-focus-cost-mjw"
    function_app                = "func-focus-cost-mjw"
    application_insights        = "ai-focus-cost-mjw"
    log_analytics_workspace     = "log-focus-cost-mjw"
    event_grid_system_topic     = "evgt-focus-storage-mjw"
    event_grid_subscription     = "evgs-focus-blob-mjw"
    entra_application           = "app-focus-cost-mjw"
    cost_export_prefix          = "focus-daily-export-mjw"

    private_endpoints = {
      storage_blob    = "pe-focus-st-blob"
      storage_queue   = "pe-focus-st-queue"
      deployment_blob = "pe-focus-st-depl"
      function_app    = "pe-focus-func"
    }

    private_service_connections = {
      storage_blob    = "psc-focus-st-blob"
      storage_queue   = "psc-focus-st-queue"
      deployment_blob = "psc-focus-st-depl"
      function_app    = "psc-focus-func"
    }
  }
}
