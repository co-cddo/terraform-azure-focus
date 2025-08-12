variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the new resource group"
  type        = string
}

variable "virtual_network_name" {
  description = "Name of the existing virtual network"
  type        = string
}

variable "virtual_network_resource_group_name" {
  description = "Name of the existing resource group where the virtual network is located"
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

variable "aws_account_id" {
  description = "AWS account ID to use for the S3 bucket"
  type        = string
}

variable "aws_target_file_path" {
  description = "S3 target file path Eg 's3://s3bucketname/folder/'"
  type        = string
}

variable "deploy_from_external_network" {
  description = "If you don't have existing GitHub runners in the same virtual network, set this to true. This will enable 'public' access to the function app during deployment. This is added for convenience and is not recommended in production environments"
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "AWS region for the S3 bucket"
  type        = string
  default     = "eu-west-2"
}

variable "focus_dataset_version" {
  description = "Version of the cost and usage details (FOCUS) dataset to use"
  type        = string
  default     = "1.0r2"
}