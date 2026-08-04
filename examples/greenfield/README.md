# greenfield

<!-- BEGIN_TF_DOCS -->
## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.79.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | AWS account ID (12-digit) used to construct the cross-cloud federation role ARN | `string` | n/a | yes |
| <a name="input_billing_account_ids"></a> [billing\_account\_ids](#input\_billing\_account\_ids) | List of billing account IDs to create FOCUS cost exports for | `list(string)` | n/a | yes |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Azure Subscription ID | `string` | n/a | yes |
| <a name="input_aws_s3_bucket_name"></a> [aws\_s3\_bucket\_name](#input\_aws\_s3\_bucket\_name) | Name of the AWS S3 bucket to store cost data | `string` | `"azure-cost-data"` | no |
| <a name="input_default_subnet_name"></a> [default\_subnet\_name](#input\_default\_subnet\_name) | Name of the default subnet | `string` | `"default"` | no |
| <a name="input_functionapp_subnet_name"></a> [functionapp\_subnet\_name](#input\_functionapp\_subnet\_name) | Name of the function app subnet | `string` | `"functionapp"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the cost forwarding resources | `string` | `"uksouth"` | no |
| <a name="input_network_resource_group_name"></a> [network\_resource\_group\_name](#input\_network\_resource\_group\_name) | Name of the resource group for networking resources | `string` | `"rg-networking"` | no |
| <a name="input_vnet_name"></a> [vnet\_name](#input\_vnet\_name) | Name of the virtual network | `string` | `"vnet-focus"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_app_client_id"></a> [aws\_app\_client\_id](#output\_aws\_app\_client\_id) | The aws app client id |
| <a name="output_carbon_export_name"></a> [carbon\_export\_name](#output\_carbon\_export\_name) | The name of the carbon optimization export |
| <a name="output_recommendations_export_name"></a> [recommendations\_export\_name](#output\_recommendations\_export\_name) | The name of the Azure Advisor recommendations export |
<!-- END_TF_DOCS -->
