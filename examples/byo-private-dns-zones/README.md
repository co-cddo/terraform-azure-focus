## BYO Private DNS Zones Example

This example shows how to use existing private DNS zones instead of having the module create them.

Set:

- `private_endpoints_manage_dns_zone_group = true`
- `use_existing_private_dns_zones = true`
- `existing_private_dns_zone_ids` with keys `blob`, `queue`, and `sites`

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.14.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_example"></a> [example](#module\_example) | ../../ | n/a |

## Resources

No resources.

## Inputs

No inputs.

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_aws_app_client_id"></a> [aws\_app\_client\_id](#output\_aws\_app\_client\_id) | The aws app client id |
| <a name="output_carbon_export_name"></a> [carbon\_export\_name](#output\_carbon\_export\_name) | The name of the carbon optimization export |
| <a name="output_private_dns_zones"></a> [private\_dns\_zones](#output\_private\_dns\_zones) | Effective private DNS zone configuration used by the module |
| <a name="output_recommendations_export_name"></a> [recommendations\_export\_name](#output\_recommendations\_export\_name) | The name of the Azure Advisor recommendations export |
<!-- END_TF_DOCS -->