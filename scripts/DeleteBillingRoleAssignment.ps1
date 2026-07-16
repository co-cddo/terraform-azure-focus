#requires -Modules Az.Accounts

<#
Deletes a billing role assignment. Commented out pending verification against an EA billing
account. api-version 2024-04-01 documents DELETE as supported for EA, MCA and MPA agreement
types, returning 200 on deletion and 204 when the assignment does not exist:
https://learn.microsoft.com/en-us/rest/api/billing/billing-role-assignments/delete-by-billing-account?view=rest-billing-2024-04-01&tabs=HTTP
#>
[CmdletBinding(SupportsShouldProcess)]
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
    [string]$RoleDefinitionID
)

$accountPath = "/providers/Microsoft.Billing/billingAccounts/$BillingAccountID"
$expectedRoleDefSuffix = "/billingRoleDefinitions/$RoleDefinitionID"

$items = [System.Collections.Generic.List[object]]::new()
$path = "$accountPath/billingRoleAssignments?api-version=2024-04-01"
do {
    $response = Invoke-AzRestMethod -Method 'GET' -Path $path

    if ($response.StatusCode -ne 200) {
        throw "GET $path failed with status $($response.StatusCode): $($response.Content)"
    }

    $content = $response.Content | ConvertFrom-Json
    $pageItems = if ($content.PSObject.Properties['value']) { $content.value } else { @($content) }
    foreach ($item in $pageItems) { $items.Add($item) }
    $path = $content.nextLink -replace '^https://[^/]+', ''
} while ($path)

$assignmentId = (($items |
    Where-Object -FilterScript { $_.properties.principalId -eq $ServicePrincipalObjectID -and $_.properties.roleDefinitionId.EndsWith($expectedRoleDefSuffix) } |
        Select-Object -ExpandProperty id) -split '/')[-1]

if (-not $assignmentId) {
    Write-Warning "Billing role assignment not found for principal $ServicePrincipalObjectID with role definition $RoleDefinitionID"
    return
}

$uri = "$accountPath/billingRoleAssignments/$assignmentId`?api-version=2024-04-01"

if ($PSCmdlet.ShouldProcess($assignmentId, "Delete billing role assignment on $BillingAccountID")) {
    $response = Invoke-AzRestMethod -Method 'DELETE' -Path $uri

    if ($response.StatusCode -notin 200, 204) {
        throw "Deleting billing role assignment failed with status $($response.StatusCode): $($response.Content)"
    }

    Write-Output -InputObject $response
}
