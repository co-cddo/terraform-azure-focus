variable "existing_resource_group_name" {
  description = "[optional] Name of a pre-existing resource group to deploy into. When set, the module does not create a resource group and looks up this one instead. Use when manage_role_assignments is false and the resource group (with its role assignments) must exist before the first apply. Leave null to have the module create the resource group."
  type        = string
  default     = null
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

variable "enable_focus_exports" {
  description = "Whether to create the FOCUS cost export infrastructure (storage account, Event Grid, daily export schedule, billing role assignments). Set to false for secondary tenant deployments that share a billing account with a primary deployment — FOCUS exports are scoped at the billing account level, so only one deployment per billing account should create them."
  type        = bool
  default     = true
}

variable "billing_account_ids" {
  description = "List of billing account IDs to create FOCUS/cost exports for. Use the billing account ID format from Azure portal (e.g., 'bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31'). Home tenant ID for all billing accounts must match the AzureRM provider configuration (tenant_id). Can be empty when enable_focus_exports is false."
  type        = list(string)
  validation {
    condition     = !var.enable_focus_exports || length(var.billing_account_ids) > 0
    error_message = "At least one billing account ID must be provided when enable_focus_exports is true."
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
}

variable "deploy_from_external_network" {
  description = "If you don't have existing GitHub runners in the same virtual network, set this to true. This will enable 'public' access to the function app during deployment. This is added for convenience and is not recommended in production environments"
  type        = bool
  default     = false
}

variable "publish_function_code" {
  description = "Whether the module publishes the function app code via the bundled 'az functionapp deployment source config-zip' step. Set to false when the function code is deployed out-of-band (for example by a separate CI pipeline), which also avoids the Azure CLI dependency in environments where it is unavailable such as 'terraform test'."
  type        = bool
  default     = true
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

variable "management_group_id" {
  description = "[optional] ID of the management group scoping the carbon emissions and Azure Advisor feeds. It sets the scope of the function identity's 'Carbon Optimization Reader' and 'Advisor Recommendations Contributor' role assignments, and the set of subscriptions the CarbonEmissionsExporter and AdvisorRecommendationsExporter enumerate. Defaults to null, meaning the Tenant Root management group, whose ID is the tenant ID. Set it to a child management group when role assignments at the tenant root are not permitted, or to limit the estate these two feeds cover; FOCUS cost exports are scoped by billing account and are unaffected, so narrowing this makes carbon and Advisor data cover a subset of the subscriptions the cost data covers. Supply the ID shown in the portal's 'ID' column (e.g. 'alz'), not the display name in its 'Name' column and not a full resource ID - note that the azurerm_management_group data source confusingly calls this field 'name'."
  type        = string
  default     = null

  validation {
    condition     = var.management_group_id == null || can(regex("^[-_().a-zA-Z0-9]{1,90}$", var.management_group_id))
    error_message = "management_group_id must be null or a management group ID (1-90 characters, letters, digits, hyphens, underscores, periods or parentheses) - the portal's 'ID' column, not its display name and not a full resource ID."
  }
}

variable "manage_role_assignments" {
  description = "Whether the module creates the role assignments it needs (section (b) of the README 'Privileges'). Set to false when RBAC is managed externally - you must then pre-provision every grant yourself, including the deploying principal's Storage Blob/Queue Data Contributor roles, or apply will fail. The Entra app role assignment for AWS federation is not governed by this variable - it is controlled separately by manage_entra_app_role_assignment."
  type        = bool
  default     = true
}

variable "existing_entra_application_client_id" {
  description = "[optional] Client (application) ID of a pre-existing Entra app registration to use for AWS OIDC federation. Set this for separation of duties: when supplied, the module does NOT create the app registration, service principal, or app role (all of which require directory-write privileges) and consumes this client ID instead. The pre-created app must expose an 'AssumeRoleWithWebIdentity' app role and the identifier URI 'api://<tenant-id>/GDS-AWS-Cost-Forwarding<cost_mgmt_suffix>' (the AWS OIDC token audience). Leave null to have the module create the app registration as before."
  type        = string
  default     = null

  validation {
    condition     = var.existing_entra_application_client_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.existing_entra_application_client_id))
    error_message = "existing_entra_application_client_id must be null or a GUID."
  }
}

variable "manage_entra_app_role_assignment" {
  description = "Whether the module creates the Entra app role assignment that binds the function app's managed identity to the 'AssumeRoleWithWebIdentity' app role. Defaults to true (current behaviour). Only takes effect when bringing your own app registration (existing_entra_application_client_id set); when the module creates the app registration it already holds the privileges to create the binding, so this is forced true. Set to false for strict separation of duties when the deploying principal has no directory-write privileges: the module then skips the binding and the 'entra_app_role_assignment_manual_action_required' output prints the details for your Entra team to create it out-of-band."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "private_endpoints_manage_dns_zone_group" {
  description = "Whether to manage private DNS integration for private endpoints with this module. If set to false, private DNS zone groups and records must be managed externally, for example by Azure Policy."
  type        = bool
  default     = true
}

variable "use_existing_private_dns_zones" {
  description = "If true, use existing private DNS zones provided via existing_private_dns_zone_ids instead of creating them in this module when private_endpoints_manage_dns_zone_group is enabled"
  type        = bool
  default     = false
}

variable "link_existing_private_dns_zones_to_vnet" {
  description = "When use_existing_private_dns_zones is true, whether to create virtual network links from the existing private DNS zones to the module virtual network. Leave as false when your DNS zones are centrally managed (e.g. via a Private DNS Resolver hub) and already linked to the VNet."
  type        = bool
  default     = false
}

variable "existing_private_dns_zone_ids" {
  description = <<-EOT
Map of existing private DNS zone IDs keyed by blob, queue, and sites.

Example:
{
  blob  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  queue = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.queue.core.windows.net"
  sites = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.azurewebsites.net"
}
EOT
  type        = map(string)
  default     = {}

  validation {
    condition = !var.private_endpoints_manage_dns_zone_group || !var.use_existing_private_dns_zones || alltrue([
      for zone in ["blob", "queue", "sites"] :
      contains(keys(var.existing_private_dns_zone_ids), zone)
    ])
    error_message = "When private_endpoints_manage_dns_zone_group and use_existing_private_dns_zones are both true, existing_private_dns_zone_ids must include keys: blob, queue, and sites."
  }

  validation {
    condition = alltrue([
      for _, zone_id in var.existing_private_dns_zone_ids :
      can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/[^/]+$", zone_id))
    ])
    error_message = "Each existing_private_dns_zone_ids value must be a valid private DNS zone resource ID."
  }

  validation {
    condition = !var.private_endpoints_manage_dns_zone_group || !var.use_existing_private_dns_zones || alltrue([
      for zone, expected_name in {
        blob  = "privatelink.blob.core.windows.net"
        queue = "privatelink.queue.core.windows.net"
        sites = "privatelink.azurewebsites.net"
      } :
      try(lower(split("/", var.existing_private_dns_zone_ids[zone])[8]) == lower(expected_name), false)
    ])
    error_message = "existing_private_dns_zone_ids must use Azure privatelink zone names matching each key (blob, queue, sites)."
  }
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
    resource_group              = optional(string)
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
    diagnostic_settings = optional(object({
      cost_export_blob  = optional(string)
      cost_export_queue = optional(string)
      deployment_blob   = optional(string)
      deployment_queue  = optional(string)
      event_grid        = optional(string)
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
