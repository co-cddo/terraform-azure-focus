#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications

<#
.SYNOPSIS
Configures an existing Entra ID app registration for AWS OIDC federation. All operations are idempotent and safe to re-run.

.DESCRIPTION
This script performs up to three tasks against an existing app registration:

1. Adds the 'AssumeRole' app role definition (if not already present).
2. Sets the identifier URI to 'api://<tenant-id>/GDS-AWS-Cost-Forwarding[-suffix]' (if not already set).
3. Assigns the AssumeRole app role to the function app's user-assigned managed identity (if -ManagedIdentityClientID is provided and the assignment does not already exist).

When the app registration is managed entirely out-of-band (i.e. existing_entra_application_client_id is set and manage_entra_app_role_assignment = false), the script must be run twice:

- Before terraform apply: run with -AppRegistrationClientID only. This creates the app role definition and identifier URI that Terraform references during plan/apply.
- After terraform apply: run again, adding -ManagedIdentityClientID (the client ID of the newly created function app user-assigned managed identity). This creates the app role assignment that the function app needs at runtime.

.EXAMPLE
./ConfigureExistingAppRegistration.ps1 -AppRegistrationClientID 'a1b2c3d4-e5f6-7890-a1b2-c3d4e5f6a7b8'

Before module deployment: adds the AssumeRole app role definition and sets the identifier URI. No app role assignment is created because the managed identity does not exist yet.

.EXAMPLE
./ConfigureExistingAppRegistration.ps1 -AppRegistrationClientID 'a1b2c3d4-e5f6-7890-a1b2-c3d4e5f6a7b8' -ManagedIdentityClientID 'f9e8d7c6-b5a4-3210-fedc-ba9876543210'

After module deployment: re-runs all steps (skipping those already complete) and assigns the AssumeRole app role to the function app's user-assigned managed identity.

.EXAMPLE
./ConfigureExistingAppRegistration.ps1 -AppRegistrationClientID 'a1b2c3d4-e5f6-7890-a1b2-c3d4e5f6a7b8' -ManagedIdentityClientID 'f9e8d7c6-b5a4-3210-fedc-ba9876543210' -CostManagementSuffix 'secondary'

Same as above, but appends '-secondary' to the identifier URI. Only needed if the existing deployment already uses the deprecated cost_mgmt_suffix variable - the identifier URI must match.
#>
param(
	[Parameter(Mandatory)]
	[string]$AppRegistrationClientID,

	#Omit if you are preparing an app registration prior to module deployment - populate with the client id for the function app user-assigned managed identity if you have completed module deployment and now want to manually add the required app role assignment.
	[Parameter()]
	[string]$ManagedIdentityClientID,

	#[deprecated] Only needed if the existing deployment uses the cost_mgmt_suffix variable - the identifier URI must match. See https://github.com/co-cddo/terraform-azure-focus#input_cost_mgmt_suffix
	[Parameter()]
	[string]$CostManagementSuffix = ''
)

$ErrorActionPreference = 'Stop'

try {
	Import-Module Microsoft.Graph.Applications

	$requiredScopes = @('Directory.Read.All', 'AppRoleAssignment.ReadWrite.All', 'Application.ReadWrite.All')

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

	if ($ManagedIdentityClientID) {
		$managedIdentityServicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '$ManagedIdentityClientID'"
		if (-not $managedIdentityServicePrincipal) {
			throw "Could not find managed identity with client id: $ManagedIdentityClientID"
		}
	}

	$appRegistration = Get-MgApplication -Filter "AppId eq '$AppRegistrationClientID'"
	$appRole = $appRegistration |
	Select-Object -ExpandProperty AppRoles |
	Where-Object -FilterScript { $_.DisplayName -eq 'AssumeRole' -and $_.Value -eq 'AssumeRoleWithWebIdentity' }

	if (-not $appRole) {
		$guid = New-Guid | Select-Object -ExpandProperty Guid

		$roleList = [System.Collections.Generic.List[Microsoft.Graph.PowerShell.Models.IMicrosoftGraphAppRole]]::new()
		$roleList.Add(@{
				AllowedMemberTypes = @('User', 'Application')
				Description        = 'Allows the cost-export managed identity to assume an AWS role via OIDC federation.'
				DisplayName        = 'AssumeRole'
				Id                 = $guid
				IsEnabled          = $true
				Value              = 'AssumeRoleWithWebIdentity'
			})

		if ($appRegistration.AppRoles) {
			$roleList.AddRange($appRegistration.AppRoles)
		}
		Write-Verbose -Message "Upserting app role(s) for app registration with object id: $($appRegistration.Id)..." -Verbose
		Update-MgApplication -ApplicationId $appRegistration.Id -AppRoles $roleList

		$appRegistration = Get-MgApplication -Filter "AppId eq '$AppRegistrationClientID'"
		$appRole = $appRegistration |
		Select-Object -ExpandProperty AppRoles |
		Where-Object -FilterScript { $_.DisplayName -eq 'AssumeRole' -and $_.Value -eq 'AssumeRoleWithWebIdentity' }
	}

	if ($ManagedIdentityClientID) {
		$servicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '$AppRegistrationClientID'"

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
}
catch {
	throw
}
