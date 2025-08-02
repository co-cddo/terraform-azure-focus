variable "aws_target_file_path" {
  description = "AWS S3 path for cost export"
  type        = string
}

variable "aws_role_arn" {
  description = "AWS IAM role ARN for cross-account access"
  type        = string
}

variable "report_scope" {
  description = "Azure billing scope for cost reporting"
  type        = string
}

variable "existing_resource_group_name" {
  description = "Name of the existing resource group containing the VNet"
  type        = string
  default     = "existing-infra"
}

variable "existing_vnet_name" {
  description = "Name of the existing virtual network"
  type        = string
  default     = "existing-vnet"
}

variable "default_subnet_name" {
  description = "Name of the existing default subnet"
  type        = string
  default     = "default"
}

variable "functionapp_subnet_name" {
  description = "Name of the existing function app subnet"
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

variable "deploy_from_external_network" {
  description = "Whether to deploy from external network"
  type        = bool
  default     = false
}