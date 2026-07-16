# Deletes a billing role assignment. Commented out pending verification against an EA billing
# account. api-version 2024-04-01 documents DELETE as supported for EA, MCA and MPA agreement
# types, returning 200 on deletion and 204 when the assignment does not exist:
# https://learn.microsoft.com/en-us/rest/api/billing/billing-role-assignments/delete-by-billing-account?view=rest-billing-2024-04-01&tabs=HTTP
<#
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$BillingAccountID,

    # Accepts the assignment name or the fully qualified ID returned by GetBillingRoleAssignment
    [Parameter(Mandatory)]
    [string]$BillingRoleAssignmentID
)

$BillingRoleAssignmentID = ($BillingRoleAssignmentID -split '/')[-1]

$uri = "/providers/Microsoft.Billing/billingAccounts/$BillingAccountID/billingRoleAssignments/$BillingRoleAssignmentID`?api-version=2024-04-01"

if ($PSCmdlet.ShouldProcess($BillingRoleAssignmentID, "Delete billing role assignment on $BillingAccountID")) {
    $response = Invoke-AzRestMethod -Method 'DELETE' -Path $uri

    if ($response.StatusCode -notin 200, 204) {
        throw "Deleting billing role assignment failed with status $($response.StatusCode): $($response.Content)"
    }

    Write-Output -InputObject $response
}
#>
