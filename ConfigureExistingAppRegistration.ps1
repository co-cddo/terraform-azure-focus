#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications

# TODO: Add app role (definition) creation to this script
# TODO: Update ACTION REQUIRED comment in the check block to just say 'look at respective output for details of how to run ConfigureExistingAppRegistration.ps1': https://github.com/appvia-lz-azure/test-consume-terraform-azure-focus/actions/runs/31128400368/job/92708960926
# TODO: Replace az rest command in Output with instructions to use this script
# TODO: Ask Lewis where to add the suffix on the end of the application URI

param(
	[Parameter(Mandatory)]
	[string]$managedIdentityObjectID,

	[Parameter(Mandatory)]
	[string]$servicePrincipalObjectID,

	[Parameter(Mandatory)]
	[string]$appRoleID
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

$params = @{
	principalId = $managedIdentityObjectID
	resourceId  = $servicePrincipalObjectID
	appRoleId   = $appRoleId
}

New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentityObjectID -BodyParameter $params
