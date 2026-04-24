locals {
  cost_mgmt_suffix = length(var.cost_mgmt_suffix) > 0 ? "-${var.cost_mgmt_suffix}" : ""

  publish_code_command_common = "az functionapp deployment source config-zip --src ${data.archive_file.function.output_path} --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name}"
  publish_code_command        = var.deploy_from_external_network ? "Start-Sleep -Seconds 150 && ${local.publish_code_command_common}" : local.publish_code_command_common
  identifier_uri              = "api://${data.azurerm_client_config.current.tenant_id}/GDS-AWS-Cost-Forwarding${local.cost_mgmt_suffix}"
  focus_dataset_major_version = substr(var.focus_dataset_version, 0, 1)
  # FOCUS directory name should only contain major version number for the data set
  focus_directory_name  = "gds-focus-v${local.focus_dataset_major_version}"
  carbon_directory_name = "gds-carbon-v1"
  aws_role_arn          = "arn:aws:iam::${var.aws_account_id}:role/AzureFederated-${data.azurerm_client_config.current.tenant_id}"
  aws_target_file_path  = "${var.aws_s3_bucket_name}/${data.azurerm_client_config.current.tenant_id}"

  # Create billing account mapping from the provided list
  # Construct full resource manager paths from just the billing account IDs
  billing_accounts_map = {
    for idx, account_id in var.billing_account_ids :
    tostring(idx) => {
      id    = account_id
      scope = "/providers/Microsoft.Billing/billingAccounts/${account_id}"
    }
  }

  # Create report scopes for the provided billing accounts
  report_scopes = [
    for account_id in var.billing_account_ids : "/providers/Microsoft.Billing/billingAccounts/${account_id}"
  ]

  private_dns_zone_names = {
    blob  = "privatelink.blob.core.windows.net"
    queue = "privatelink.queue.core.windows.net"
    sites = "privatelink.azurewebsites.net"
  }

  manage_private_endpoint_dns = var.private_endpoints_manage_dns_zone_group

  managed_private_dns_zone_ids = {
    blob  = try(azurerm_private_dns_zone.blob[0].id, null)
    queue = try(azurerm_private_dns_zone.queue[0].id, null)
    sites = try(azurerm_private_dns_zone.sites[0].id, null)
  }

  effective_private_dns_zone_ids = !local.manage_private_endpoint_dns ? {} : var.use_existing_private_dns_zones ? {
    for zone, _ in local.private_dns_zone_names :
    zone => var.existing_private_dns_zone_ids[zone]
    } : {
    for zone, _ in local.private_dns_zone_names :
    zone => local.managed_private_dns_zone_ids[zone]
  }

  effective_private_dns_zone_resource_group_names = {
    for zone, zone_id in local.effective_private_dns_zone_ids :
    zone => split("/", zone_id)[4]
  }

  effective_private_dns_zone_names = {
    for zone, zone_id in local.effective_private_dns_zone_ids :
    zone => split("/", zone_id)[8]
  }
}
