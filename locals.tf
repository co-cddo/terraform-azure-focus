locals {
  publish_code_command_common = "az functionapp deployment source config-zip --src ${data.archive_file.function.output_path} --name ${azurerm_function_app_flex_consumption.cost_export.name} --resource-group ${azurerm_resource_group.cost_export.name}"
  publish_code_command        = var.deploy_from_external_network ? "sleep 180 && ${local.publish_code_command_common}" : local.publish_code_command_common
  identifier_uri              = "api://${data.azurerm_client_config.current.tenant_id}/GDS-AWS-Cost-Forwarding"
  focus_dataset_major_version = substr(var.focus_dataset_version, 0, 1)
  # FOCUS directory name should only contain major version number for the data set
  focus_directory_name       = "gds-focus-v${local.focus_dataset_major_version}"
  carbon_directory_name      = "gds-carbon-v1"
  utilization_directory_name = "gds-recommendations-v1"
  aws_role_arn               = "arn:aws:iam::${var.aws_account_id}:role/AzureFederated-${data.azurerm_client_config.current.tenant_id}"
  aws_target_file_path       = "${var.aws_s3_bucket_name}/${data.azurerm_client_config.current.tenant_id}"

  # Generate backfill exports for each month from January 2022 to last complete month
  # Generate a list of year-month combinations from 2022-01 to 2025-07 (July 2025, last complete month)
  backfill_months = [
    for month_offset in range(0, (2025 - 2022) * 12 + 7) : # From 2022-01 to 2025-07
    format("%04d-%02d",
      2022 + floor(month_offset / 12),
      (month_offset % 12) + 1
    )
  ]

  # Calculate end dates for each month
  month_end_dates = {
    for month in local.backfill_months : month => (
      contains(["01", "03", "05", "07", "08", "10", "12"], split("-", month)[1]) ? "${month}-31" :
      contains(["04", "06", "09", "11"], split("-", month)[1]) ? "${month}-30" :
      split("-", month)[1] == "02" ? (
        parseint(split("-", month)[0], 10) % 4 == 0 && (parseint(split("-", month)[0], 10) % 100 != 0 || parseint(split("-", month)[0], 10) % 400 == 0) ? "${month}-29" : "${month}-28"
      ) : "${month}-31"
    )
  }
}