#requires -Modules Az.Accounts

<#
.DESCRIPTION
Grants a billing role assignment directly against the Billing API, outside Terraform. Only use
this when the module does not manage the assignment itself: Enterprise Agreement billing
accounts (always manual, since creation requires Enterprise Administrator privileges; pass
-IsEnterpriseAgreement), and/or deployments with manage_role_assignments = false. For MCA
accounts with manage_role_assignments = true, azapi_resource_action.add_role_assignment in
rbac.tf grants the role and cleans it up on destroy; assignments created by this script are
invisible to Terraform and are never cleaned up automatically.
#>
param(
    [Parameter(Mandatory)]
    [string]$BillingAccountID,

    [Parameter(Mandatory)]
    [string]$ServicePrincipalObjectID,

    #EA Roles: https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/assign-roles-azure-service-principals#permissions-that-can-be-assigned-to-the-service-principal | MCA Roles: https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/understand-mca-roles#billing-role-definitions
    [Parameter(Mandatory)]
    [ValidateSet(
        '24f8edb6-1668-4659-b5e2-40bb5f3a7d7e', # EnrollmentReader
        '50000000-aaaa-bbbb-cccc-100000000002'  # Billing account reader
    )]
    [string]$RoleDefinitionID,

    [switch]$IsEnterpriseAgreement
)

# https://learn.microsoft.com/en-us/rest/api/billing/billing-role-assignments/create-by-billing-account?view=rest-billing-2019-10-01-preview&tabs=HTTP
$uri = "/providers/Microsoft.Billing/billingAccounts/$BillingAccountID/createBillingRoleAssignment?api-version=2019-10-01-preview"
$method = 'POST'

$body = @{
    properties = @{
        principalId      = $ServicePrincipalObjectID
        # The API expects the fully qualified role definition ID; expand if given a bare GUID
        roleDefinitionId = "/providers/Microsoft.Billing/billingAccounts/$BillingAccountID/billingRoleDefinitions/$RoleDefinitionID"
    }
}

if ($IsEnterpriseAgreement.IsPresent) {
    $billingRoleAssignmentID = (New-Guid).Guid
    # https://learn.microsoft.com/en-us/rest/api/billing/role-assignments/put?view=rest-billing-2019-10-01-preview&tabs=HTTP
    $uri = "/providers/Microsoft.Billing/billingAccounts/$BillingAccountID/billingRoleAssignments/$billingRoleAssignmentID`?api-version=2019-10-01-preview"
    $body.properties.principalTenantId = (Get-AzContext).Tenant.Id
    $method = 'PUT'
}

$body = $body | ConvertTo-Json
$response = Invoke-AzRestMethod -Method $method -Path $uri -Payload $body

if ($response.StatusCode -notin 200, 201) {
    throw "Billing role assignment failed with status $($response.StatusCode): $($response.Content)"
}

Write-Output -InputObject $response
