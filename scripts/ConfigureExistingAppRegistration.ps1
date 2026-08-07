#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications

param(
	[Parameter(Mandatory)]
	[string]$ManagedIdentityClientID,

	[Parameter(Mandatory)]
	[string]$AppRegistrationClientID,

	#If you set the cost_mgmt_suffix variable in your module configuration, set it here too https://github.com/co-cddo/terraform-azure-focus#input_cost_mgmt_suffix
	[Parameter()]
	[string]$CostManagementSuffix = ''
)

$ErrorActionPreference = 'Stop'

Import-Module Microsoft.Graph.Applications

$requiredScopes = @('Directory.Read.All', 'AppRoleAssignment.ReadWrite.All', 'Application.Read.All')

$mgContext = Get-MgContext -ErrorAction SilentlyContinue
$currentScopes = $mgContext |
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
	$mgContext = Get-MgContext
}

$managedIdentityServicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '$managedIdentityClientID'"

$appRegistration = Get-MgApplication -Filter "AppId eq '$AppRegistrationClientID'"

$servicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '$AppRegistrationClientID'"

$appRole = $appRegistration |
Select-Object -ExpandProperty AppRoles |
Where-Object -FilterScript { $_.DisplayName -eq 'AssumeRole' -and $_.Value -eq 'AssumeRoleWithWebIdentity' }

if (-not $appRole) {
	Write-Verbose -Message "Creating app role for app registration with object id: $($appRegistration.Id)..." -Verbose

	$guid = New-Guid | Select-Object -ExpandProperty Guid
	Update-MgApplication -ApplicationId $appRegistration.Id -AppRoles @{
		AllowedMemberTypes = @('User', 'Application')
		Description        = 'Allows the cost-export managed identity to assume an AWS role via OIDC federation.'
		DisplayName        = 'AssumeRole'
		Id                 = $guid
		IsEnabled          = $true
		Value              = 'AssumeRoleWithWebIdentity'
	}

	$appRegistration = Get-MgApplication -Filter "AppId eq '$AppRegistrationClientID'"
	$appRole = $appRegistration |
	Select-Object -ExpandProperty AppRoles |
	Where-Object -FilterScript { $_.DisplayName -eq 'AssumeRole' -and $_.Value -eq 'AssumeRoleWithWebIdentity' }
}

$params = @{
	principalId = $managedIdentityServicePrincipal.Id
	resourceId  = $servicePrincipal.Id
	appRoleId   = $appRole.Id
}

$appRoleAssignment = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentityServicePrincipal.Id -ErrorAction SilentlyContinue |
Where-Object -FilterScript { $_.AppRoleId -eq $appRole.Id }

if (-not ($appRoleAssignment)) {
	Write-Verbose -Message "Creating app role assignment for managed identity with object id: $($managedIdentityServicePrincipal.Id)..." -Verbose
	New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $managedIdentityServicePrincipal.Id -BodyParameter $params
}

$identifierUriSuffix = ''
if ($CostManagementSuffix) {
	$identifierUriSuffix = "-$CostManagementSuffix"
}
$identifierUris = "api://$($mgContext.TenantId)/GDS-AWS-Cost-Forwarding$identifierUriSuffix"

if ($identifierUris -ne $appRegistration.IdentifierUris) {
	Write-Verbose -Message "Setting identifier uris for app registration with object id: $($appRegistration.Id)..." -Verbose
	Update-MgApplication -ApplicationId $appRegistration.Id -IdentifierUris $identifierUris
}
