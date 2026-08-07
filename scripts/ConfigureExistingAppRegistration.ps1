#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications

# TODO: Add app role (definition) creation to this script
# TODO: Update ACTION REQUIRED comment in the check block to just say 'look at respective output for details of how to run ConfigureExistingAppRegistration.ps1': https://github.com/appvia-lz-azure/test-consume-terraform-azure-focus/actions/runs/31128400368/job/92708960926
# TODO: Replace az rest command in Output with instructions to use this script
# TODO: Ask Lewis where to add the suffix on the end of the application URI

param(
	[Parameter(Mandatory)]
	[string]$ManagedIdentityClientID,

	[Parameter(Mandatory)]
	[string]$AppRegistrationClientID
)

Import-Module Microsoft.Graph.Applications

$requiredScopes = @('Directory.Read.All', 'AppRoleAssignment.ReadWrite.All', 'Application.Read.All')

$currentScopes = Get-MgContext -ErrorAction SilentlyContinue |
Select-Object -ExpandProperty Scopes

$currentScopesContainsRequiredScopes = $true
foreach ($rs in $requiredScopes) {
	if ($currentScopes -notcontains $rs) {
		$currentScopesContainsRequiredScopes = $false
		break
	}
}

if (-not ($currentScopesContainsRequiredScopes)) {
	Connect-MgGraph -Scopes $requiredScopes
}

$managedIdentityServicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '$managedIdentityClientID'"

$appRegistration = Get-MgApplication -Filter "AppId eq '$AppRegistrationClientID'"

$servicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '$AppRegistrationClientID'"
$appRole = $appRegistration |
Select-Object -ExpandProperty AppRoles |
Where-Object -FilterScript { $_.DisplayName -eq 'AssumeRole' -and $_.Value -eq 'AssumeRoleWithWebIdentity' }


$params = @{
	principalId = $managedIdentityServicePrincipal.Id
	resourceId  = $servicePrincipal.Id
	appRoleId   = $appRole.Id
}

$appRoleAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentityServicePrincipal.Id -ErrorAction SilentlyContinue |
Where-Object -FilterScript { $_.AppRoleId -eq $appRole.Id }

if (-not ($appRoleAssignment)) {
	New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentityServicePrincipal.Id -BodyParameter $params
}
