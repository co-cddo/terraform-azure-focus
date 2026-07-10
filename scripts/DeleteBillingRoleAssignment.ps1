[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$BillingAccountID,

    # Accepts the assignment name or the fully qualified ID returned by GetBillingRoleAssignment
    [Parameter(Mandatory)]
    [string]$BillingRoleAssignmentID
)

$BillingRoleAssignmentID = ($BillingRoleAssignmentID -split '/')[-1]

# https://learn.microsoft.com/en-us/rest/api/billing/billing-role-assignments/delete-by-billing-account?view=rest-billing-2019-10-01-preview&tabs=HTTP
$uri = "/providers/Microsoft.Billing/billingAccounts/$BillingAccountID/billingRoleAssignments/$BillingRoleAssignmentID`?api-version=2019-10-01-preview"

if ($PSCmdlet.ShouldProcess($BillingRoleAssignmentID, "Delete billing role assignment on $BillingAccountID")) {
    $response = Invoke-AzRestMethod -Method 'DELETE' -Path $uri

    if ($response.StatusCode -notin 200, 204) {
        throw "Deleting billing role assignment failed with status $($response.StatusCode): $($response.Content)"
    }

    Write-Output -InputObject $response
}
