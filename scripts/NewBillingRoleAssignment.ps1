param(
    [Parameter(Mandatory)]
    [string]$BillingAccountID,

    [Parameter(Mandatory)]
    [string]$ServicePrincipalObjectID,

    #EA Roles: https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/assign-roles-azure-service-principals#permissions-that-can-be-assigned-to-the-service-principal | MCA Roles: https://learn.microsoft.com/en-us/azure/cost-management-billing/manage/understand-mca-roles#billing-role-definitions
    [Parameter(Mandatory)]
    [string]$RoleDefinitionID,

    [switch]$IsEnterpriseAgreement
)

$uri = "/providers/Microsoft.Billing/billingAccounts/$BillingAccountID/createBillingRoleAssignment?api-version=2019-10-01-preview"
$method = 'POST'

# The API expects the fully qualified role definition ID; expand if given a bare GUID
if ($RoleDefinitionID -notlike '/providers/*') {
    $RoleDefinitionID = "/providers/Microsoft.Billing/billingAccounts/$BillingAccountID/billingRoleDefinitions/$RoleDefinitionID"
}

$body = @{
    properties = @{
        principalId      = $ServicePrincipalObjectID
        roleDefinitionId = $RoleDefinitionID
    }
}

if ($IsEnterpriseAgreement.IsPresent) {
    $billingRoleAssignmentID = (New-Guid).Guid
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
