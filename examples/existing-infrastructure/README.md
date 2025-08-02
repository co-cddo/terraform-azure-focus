# Existing Infrastructure Example

This example demonstrates how to use the terraform-azurerm-cost-forwarding module when you need to create the prerequisite infrastructure (virtual network and subnets) in the same Terraform configuration.

## Infrastructure Created

This example creates:

- A resource group named `existing-infra`
- A virtual network named `existing-vnet` with address space `10.0.0.0/16`
- A default subnet with address prefix `10.0.1.0/24`
- A function app subnet with address prefix `10.0.2.0/24` and delegation to `Microsoft.App/environments`

Then it calls the cost forwarding module using the created infrastructure.

## Usage

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in the required values:

```hcl
subscription_id          = "your-azure-subscription-id"
aws_target_file_path     = "s3://your-bucket/path/"
aws_role_arn            = "arn:aws:iam::account:role/YourRole"
report_scope            = "/providers/Microsoft.Billing/billingAccounts/your-billing-scope"
```

2. Initialize and apply:

```bash
terraform init
terraform plan
terraform apply
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| subscription_id | The Azure subscription ID | string | n/a | yes |
| aws_target_file_path | AWS S3 path for cost export | string | n/a | yes |
| aws_role_arn | AWS IAM role ARN for cross-account access | string | n/a | yes |
| report_scope | Azure billing scope for cost reporting | string | n/a | yes |
| existing_resource_group_name | Name of the resource group to create | string | "existing-infra" | no |
| existing_vnet_name | Name of the virtual network to create | string | "existing-vnet" | no |
| default_subnet_name | Name of the default subnet to create | string | "default" | no |
| functionapp_subnet_name | Name of the function app subnet to create | string | "functionapp" | no |
| location | Azure region | string | "uksouth" | no |
| resource_group_name | Name of the resource group for cost forwarding resources | string | "rg-cost-export" | no |
| deploy_from_external_network | Whether to deploy from external network | bool | true | no |