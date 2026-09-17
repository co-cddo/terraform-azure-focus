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

$mi = Get-MgServicePrincipal -Filter "displayName eq '$ServicePrincipalDisplayName'"

$graphSpn = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$appRole = $graphSpn.AppRoles |
Where-Object { $_.Value -eq $AppRoleName }

$params = @{
  ServicePrincipalId = $mi.Id
  PrincipalId        = $mi.Id
  ResourceId         = $graphSpn.Id
  AppRoleId          = $appRole.Id
}
New-MgServicePrincipalAppRoleAssignment @params
