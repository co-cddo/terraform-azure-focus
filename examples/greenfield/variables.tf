variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "aws_s3_bucket_name" {
  description = "Name of the AWS S3 bucket to store cost data"
  type        = string
  default     = "azure-cost-data"
}

variable "aws_account_id" {
  description = "AWS account ID (12-digit) used to construct the cross-cloud federation role ARN"
  type        = string
}

variable "billing_account_ids" {
  description = "List of billing account IDs to create FOCUS cost exports for"
  type        = list(string)
}

variable "network_resource_group_name" {
  description = "Name of the resource group for networking resources"
  type        = string
  default     = "rg-networking"
}

variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
  default     = "vnet-focus"
}

variable "default_subnet_name" {
  description = "Name of the default subnet"
  type        = string
  default     = "default"
}

variable "functionapp_subnet_name" {
  description = "Name of the function app subnet"
  type        = string
  default     = "functionapp"
}

variable "location" {
  description = "Azure region for the cost forwarding resources"
  type        = string
  default     = "uksouth"
}

variable "resource_group_name" {
  description = "Name of the resource group to create for cost forwarding resources"
  type        = string
  default     = "rg-cost-export"
}
