variable "name" {
  description = "Name of the storage account"
  type        = string
  default     = "costexport"
}

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "uksouth"
}

variable "environment" {
  description = "Environment name for the resources"
  type        = string
  default     = "prod"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-cost-export"
}

variable "virtual_network_name" {
  description = "Name of the existing virtual network"
  type        = string
}

variable "virtual_network_resource_group_name" {
  description = "Name of the resource group where the existing virtual network is located"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet to deploy the private endpoints to. Must be a subnet in the existing virtual network"
  type        = string
}

variable "function_app_subnet_id" {
  description = "ID of the subnet to connect the function app to. This subnet must have delegation configured for Microsoft.App/environments and must be in the same virtual network as the private endpoints"
  type        = string
}

variable "report_scope" {
  description = "Scope of the cost report Eg '/providers/Microsoft.Billing/billingAccounts/00000000-0000-0000-0000-000000000000'"
  type        = string
}

variable "aws_role_arn" {
  description = "ARN of the AWS role to assume  Eg 'arn:aws:iam::000000000000:role/entra_s3'"
  type        = string
}

variable "aws_region" {
  description = "AWS region for the S3 bucket"
  type        = string
  default     = "eu-west-2"
}

variable "aws_target_file_path" {
  description = "S3 target file path Eg 's3://s3bucketname/folder/'"
  type        = string
}