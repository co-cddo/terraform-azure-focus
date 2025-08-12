<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.14.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.38.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_cost_forwarding"></a> [cost\_forwarding](#module\_cost\_forwarding) | ../../ | n/a |

## Resources

| Name | Type |
|------|------|
| [azurerm_resource_group.existing](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_subnet.default](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet.functionapp](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_virtual_network.existing](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | AWS IAM role ARN for cross-account access | `string` | n/a | yes |
| <a name="input_aws_target_file_path"></a> [aws\_target\_file\_path](#input\_aws\_target\_file\_path) | AWS S3 path for cost export e.g. <your-s3-bucket>/<your-path> | `string` | n/a | yes |
| <a name="input_default_subnet_name"></a> [default\_subnet\_name](#input\_default\_subnet\_name) | Name of the existing default subnet | `string` | `"default"` | no |
| <a name="input_existing_resource_group_name"></a> [existing\_resource\_group\_name](#input\_existing\_resource\_group\_name) | Name of the existing resource group containing the VNet | `string` | `"existing-infra"` | no |
| <a name="input_existing_vnet_name"></a> [existing\_vnet\_name](#input\_existing\_vnet\_name) | Name of the existing virtual network | `string` | `"existing-vnet"` | no |
| <a name="input_functionapp_subnet_name"></a> [functionapp\_subnet\_name](#input\_functionapp\_subnet\_name) | Name of the existing function app subnet | `string` | `"functionapp"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the cost forwarding resources | `string` | `"uksouth"` | no |
| <a name="input_report_scope"></a> [report\_scope](#input\_report\_scope) | Azure billing scope for cost reporting | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group to create for cost forwarding resources | `string` | `"rg-cost-export"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_app_client_id"></a> [aws\_app\_client\_id](#output\_aws\_app\_client\_id) | The aws app client id |
| <a name="output_carbon_export_name"></a> [carbon\_export\_name](#output\_carbon\_export\_name) | The name of the carbon optimization export |
| <a name="output_focus_export_name"></a> [focus\_export\_name](#output\_focus\_export\_name) | The name of the FOCUS cost export |
| <a name="output_utilization_export_name"></a> [utilization\_export\_name](#output\_utilization\_export\_name) | The name of the cost utilization export |
<!-- END_TF_DOCS -->