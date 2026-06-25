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

variable "billing_account_ids" {
  description = "List of billing account IDs to create FOCUS/cost exports for. Use the billing account ID format from Azure portal (e.g., 'bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31'). Home tenant ID for all billing accounts must match the AzureRM provider configuration (tenant_id)."
  type        = list(string)
  validation {
    condition     = length(var.billing_account_ids) > 0
    error_message = "At least one billing account ID must be provided."
  }
}

variable "aws_account_id" {
  description = "AWS account ID to use for the S3 bucket"
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
  default     = "uksouth"
}

variable "aws_s3_bucket_name" {
  description = "Name of the AWS S3 bucket to store cost data"
  type        = string
  default     = "uk-gov-gds-cost-inbound-azure"
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

variable "current_principal_type" {
  description = "Type of the current principal running Terraform. Set to 'ServicePrincipal' when running in CI/CD with a service principal, 'User' for interactive usage."
  type        = string
  default     = "User"
  validation {
    condition     = contains(["User", "ServicePrincipal"], var.current_principal_type)
    error_message = "current_principal_type must be either 'User' or 'ServicePrincipal'."
  }
}

variable "backfill_start_date" {
  description = "The year and month to start backfill - in the format 'YYYY-MM-01'; defaults to 2022-01-01"
  type        = string
  default     = "2022-01-01"
  validation {
    condition     = can(regex("^(19|20|21|22|23|24|25)\\d{2}-(0?[1-9]|1[012])-01$", var.backfill_start_date))
    error_message = "backfill_start_date must be given and in the format'YYYY-MM-01'"
  }
}

variable "cost_export_daily_schedule_to_years" {
  description = "The number of years from initial deployment to set the end date of the daily schedule for cost export"
  type        = number
  default     = 15
}

variable "logging_level" {
  description = "Logging level for the app; can be DEBUG or INFO (default)"
  type        = string
  default     = "INFO"
}

variable "cost_mgmt_suffix" {
  description = "[optional] suffix to add to cost mgmt export tasks - to allow multiple deployments of this module in one tenant"
  type        = string
  default     = ""
}

variable "is_enterprise_customer" {
  description = "Set to true if you are an Enterprise Agreement customer"
  type        = bool
  default     = false
}

variable "manage_role_assignments" {
  description = "Whether the module creates the role assignments it needs (section (b) of the README 'Privileges'). Set to false when RBAC is managed externally - you must then pre-provision every grant yourself, including the deploying principal's Storage Blob/Queue Data Contributor roles, or apply will fail. The Entra app role assignment for AWS federation is always created (it is internal to the module's federation app)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of an existing Log Analytics workspace to use for diagnostic settings. If not provided, a new workspace will be created."
  type        = string
  default     = null

  validation {
    condition     = var.log_analytics_workspace_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be null or a valid Log Analytics workspace resource ID."
  }
}

variable "custom_resource_names" {
  description = <<-EOT
    Override the auto-generated names for resources created by this module.
    Every attribute is optional and defaults to null, which means the module
    uses its built-in name (typically a prefix plus an 8-character random suffix).
    Storage account names must be 3-24 characters, lowercase alphanumeric only.
    WARNING: Changing a resource name after initial deployment will cause Terraform
    to destroy and recreate that resource.
  EOT
  type = object({
    storage_account_cost_export = optional(string)
    storage_account_deployment  = optional(string)
    service_plan                = optional(string)
    user_assigned_identity      = optional(string)
    function_app                = optional(string)
    application_insights        = optional(string)
    log_analytics_workspace     = optional(string)
    event_grid_system_topic     = optional(string)
    event_grid_subscription     = optional(string)
    entra_application           = optional(string)
    cost_export_prefix          = optional(string)
    private_endpoints = optional(object({
      storage_blob    = optional(string)
      storage_queue   = optional(string)
      deployment_blob = optional(string)
      function_app    = optional(string)
    }))
    private_service_connections = optional(object({
      storage_blob    = optional(string)
      storage_queue   = optional(string)
      deployment_blob = optional(string)
      function_app    = optional(string)
    }))
  })
  default = {}

  validation {
    condition = (
      var.custom_resource_names.storage_account_cost_export == null ||
      can(regex("^[a-z0-9]{3,24}$", var.custom_resource_names.storage_account_cost_export))
    )
    error_message = "storage_account_cost_export must be 3-24 characters, lowercase letters and digits only."
  }

  validation {
    condition = (
      var.custom_resource_names.storage_account_deployment == null ||
      can(regex("^[a-z0-9]{3,24}$", var.custom_resource_names.storage_account_deployment))
    )
    error_message = "storage_account_deployment must be 3-24 characters, lowercase letters and digits only."
  }

  validation {
    condition = (
      var.custom_resource_names.storage_account_cost_export == null ||
      var.custom_resource_names.storage_account_deployment == null ||
      var.custom_resource_names.storage_account_cost_export != var.custom_resource_names.storage_account_deployment
    )
    error_message = "storage_account_cost_export and storage_account_deployment must be different names."
  }
}
