#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications

<#
.SYNOPSIS
Grants a Microsoft Graph app role to a service principal. All operations are idempotent and safe to re-run.

.DESCRIPTION
Assigns a Microsoft Graph application permission (app role) to the specified service principal.
Use this to grant the deploying service principal(s) the Graph API permissions they need.
When plan and apply use separate service principals, run the script once per principal with the
relevant role. When a single service principal is used for both, grant all required roles to it.

- Application.ReadWrite.OwnedBy: required at apply time to create the AWS-federation Entra app
  registration and service principal. Not required when bringing your own app registration
  (existing_entra_application_client_id).
- Application.Read.All: required at plan time to refresh the Entra app registration and service
  principal during state refresh. Not required when bringing your own app registration
  (existing_entra_application_client_id).
- AppRoleAssignment.ReadWrite.All: required at apply time to create the Entra app role
  assignment that binds the function app's managed identity to the AssumeRoleWithWebIdentity
  app role. Not required when manage_entra_app_role_assignment is false.

The caller must have Application.Read.All and AppRoleAssignment.ReadWrite.All consent to run
this script (the Connect-MgGraph call requests these scopes interactively).

.EXAMPLE
./NewServicePrincipalAppRoleAssignment.ps1 -TenantID '00000000-0000-0000-0000-000000000000' -ServicePrincipalDisplayName 'sp-cost-export-apply' -AppRoleName 'Application.ReadWrite.OwnedBy'

Grants Application.ReadWrite.OwnedBy to the apply service principal so it can create the Entra app registration.

.EXAMPLE
./NewServicePrincipalAppRoleAssignment.ps1 -TenantID '00000000-0000-0000-0000-000000000000' -ServicePrincipalDisplayName 'sp-cost-export-plan' -AppRoleName 'Application.Read.All'

Grants Application.Read.All to the plan service principal so it can refresh Entra resources during terraform plan.
#>
param(
  [Parameter(Mandatory)]
  [string]$TenantID,

  [Parameter(Mandatory)]
  [string]$ServicePrincipalDisplayName,

  [Parameter(Mandatory)]
  [ValidateSet('Application.ReadWrite.OwnedBy', 'Application.Read.All', 'AppRoleAssignment.ReadWrite.All')]
  [string]$AppRoleName
)

Connect-MgGraph -Scopes "Application.Read.All", "AppRoleAssignment.ReadWrite.All" -Tenant $TenantID

$sp = Get-MgServicePrincipal -Filter "displayName eq '$ServicePrincipalDisplayName'"

$graphSpn = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$appRole = $graphSpn.AppRoles |
Where-Object { $_.Value -eq $AppRoleName }

$params = @{
  ServicePrincipalId = $sp.Id
  PrincipalId        = $sp.Id
  ResourceId         = $graphSpn.Id
  AppRoleId          = $appRole.Id
}
New-MgServicePrincipalAppRoleAssignment @params
