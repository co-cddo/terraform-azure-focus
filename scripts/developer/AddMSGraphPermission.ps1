$TenantID = '<tenant id>'
$ManagedIdentityDisplayName = '<managed identity display name>'

Connect-MgGraph -Scopes "Application.Read.All", "AppRoleAssignment.ReadWrite.All" -Tenant $TenantID

$mi = Get-MgServicePrincipal -Filter "displayName eq '$ManagedIdentityDisplayName'"

$graphSpn = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$appRole = $graphSpn.AppRoles | Where-Object { $_.Value -eq "Application.Read.All" }

New-MgServicePrincipalAppRoleAssignment `
  -ServicePrincipalId $mi.Id `
  -PrincipalId $mi.Id `
  -ResourceId $graphSpn.Id `
  -AppRoleId $appRole.Id
