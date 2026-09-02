# Bill of Materials

> **terraform-azure-focus** -- Azure FOCUS Cost Export Module

This document lists every Azure resource the module deploys and the key pricing drivers.

---

## Compute

| Resource | Type | SKU / Tier | Lifecycle | Notes |
| --- | --- | --- | --- | --- |
| App Service Plan | `azurerm_service_plan` | FC1 (Flex Consumption) | Always | Linux |
| Function App | `azurerm_function_app_flex_consumption` | FC1 / Python 3.13 | Always | Processes cost export blobs and ships them to S3 |
| User Assigned Identity | `azurerm_user_assigned_identity` | - | Always | Managed identity for the Function App |

## Storage

| Resource | Type | SKU / Tier | Lifecycle | Notes |
| --- | --- | --- | --- | --- |
| Cost Export Storage Account | `azurerm_storage_account` | Standard LRS | Conditional | HNS-enabled (Data Lake). Shared keys disabled. Created when `enable_focus_exports = true` |
| Blob Container `cost-exports` | `azapi_resource` | - | Conditional | Landing zone for FOCUS parquet files |
| Queue `costdata` | `azapi_resource` | - | Conditional | Receives blob-created events for Function App processing |
| Deployment Storage Account | `azurerm_storage_account` | Standard LRS | Always | HNS-enabled. Hosts the Function App deployment package |
| Blob Container `cost-exports-deployment` | `azapi_resource` | - | Always | Contains the zipped Python function code |

## Networking

| Resource | Type | Sub-resource | Lifecycle | Notes |
| --- | --- | --- | --- | --- |
| PE: Cost Export Storage (Blob) | `azurerm_private_endpoint` | blob | Conditional | When `enable_focus_exports = true` |
| PE: Cost Export Storage (Queue) | `azurerm_private_endpoint` | queue | Conditional | When `enable_focus_exports = true` |
| PE: Deployment Storage (Blob) | `azurerm_private_endpoint` | blob | Always | |
| PE: Function App | `azurerm_private_endpoint` | sites | Always | |

### Private DNS Zones

Created by default. Set `use_existing_private_dns_zones = true` and supply zone IDs to skip creation. Each zone includes a VNet link.

| Zone | FQDN | Lifecycle |
| --- | --- | --- |
| Blob | `privatelink.blob.core.windows.net` | Conditional |
| Queue | `privatelink.queue.core.windows.net` | Conditional |
| Sites | `privatelink.azurewebsites.net` | Conditional |

## Event Grid

| Resource | Type | Lifecycle | Notes |
| --- | --- | --- | --- |
| System Topic (Storage Events) | `azurerm_eventgrid_system_topic` | Conditional | Scoped to the cost export storage account |
| Event Subscription (BlobCreated) | `azurerm_eventgrid_event_subscription` | Conditional | Delivers to the `costdata` queue |

## Cost Management Exports

| Resource | Type | Lifecycle | Notes |
| --- | --- | --- | --- |
| Daily Cost Export | `azapi_resource` (`Microsoft.CostManagement/exports@2025-03-01`) | Conditional | One instance per billing account. FOCUS dataset version configurable (default `1.0r2`). Schedule runs for up to 15 years |

## Identity & RBAC

Set `manage_role_assignments = false` to handle RBAC externally. Set `existing_entra_application_client_id` to reuse an existing Entra app.

| Resource | Type | Scope | Lifecycle |
| --- | --- | --- | --- |
| Entra Application (AWS OIDC) | `azuread_application` | Tenant | Conditional |
| Service Principal | `azuread_service_principal` | Tenant | Conditional |
| App Role Assignment | `azuread_app_role_assignment` | Application | Conditional |
| Storage Blob Data Contributor (Function) | `azurerm_role_assignment` | Storage Account | Conditional |
| Storage Queue Data Contributor (Function) | `azurerm_role_assignment` | Storage Account | Conditional |
| Storage Account Owner (ABAC-constrained) | `azurerm_role_assignment` | Storage Account | Conditional |
| Event Grid Queue Sender | `azurerm_role_assignment` | Storage Account | Conditional |
| Deployer Blob + Queue Contributor | `azurerm_role_assignment` | Storage Account | Conditional |
| Deployment Storage Blob + Queue Contributor | `azurerm_role_assignment` | Storage Account | Conditional |
| Billing Account Reader | `azapi_resource_action` | Billing Account | Conditional |
| Carbon Optimization Reader | `azurerm_role_assignment` | Management Group | Conditional |
| Advisor Recommendations Contributor | `azurerm_role_assignment` | Management Group | Conditional |

## Monitoring & Diagnostics

Supply an existing workspace ID via `log_analytics_workspace_id` to skip Log Analytics creation.

| Resource | Type | SKU / Config | Lifecycle |
| --- | --- | --- | --- |
| Log Analytics Workspace | `azurerm_log_analytics_workspace` | PerGB2018 / 30-day retention | Conditional |
| Application Insights | `azurerm_application_insights` | - | Always |
| Diag: Function App | `azurerm_monitor_diagnostic_setting` | - | Always |
| Diag: Event Grid System Topic | `azurerm_monitor_diagnostic_setting` | - | Conditional |
| Diag: Cost Export Blob Service | `azurerm_monitor_diagnostic_setting` | - | Conditional |
| Diag: Cost Export Queue Service | `azurerm_monitor_diagnostic_setting` | - | Conditional |
| Diag: Deployment Blob Service | `azurerm_monitor_diagnostic_setting` | - | Always |
| Diag: Deployment Queue Service | `azurerm_monitor_diagnostic_setting` | - | Always |

---

## Pricing Considerations

The primary cost drivers are:

- **Function App executions** -- Flex Consumption bills per invocation and GB-s; no idle cost
- **Storage** -- transaction and capacity charges on two Standard LRS accounts
- **Log Analytics** -- data ingestion under the PerGB2018 tier
- **Private endpoints** -- hourly charge per endpoint (up to 4 in a full deployment)
- **Event Grid** -- system topic events are free or near-free at typical volumes
- **Cost Management exports** -- no direct charge for the export definitions
- **RBAC role assignments and Entra ID objects** -- no direct Azure charges

Actual cost depends on the number of billing accounts, export frequency, and data volume. Our rough cost estimate is between £25 and £30 per month per deployment.
