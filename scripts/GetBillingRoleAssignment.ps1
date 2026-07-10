param(
    [Parameter(Mandatory)]
    [string]$BillingAccountID,

    # Get a single assignment by its ID (GUID); omit to list all assignments on the account
    [string]$BillingRoleAssignmentID,

    # Filter results to assignments for this principal
    [string]$ServicePrincipalObjectID
)

function Invoke-BillingGet {
    param([string]$Path)

    $items = @()
    do {
        $response = Invoke-AzRestMethod -Method 'GET' -Path $Path

        if ($response.StatusCode -ne 200) {
            throw "GET $Path failed with status $($response.StatusCode): $($response.Content)"
        }

        $content = $response.Content | ConvertFrom-Json
        $items += if ($content.PSObject.Properties['value']) { $content.value } else { $content }
        # nextLink is absolute; Invoke-AzRestMethod -Path expects a relative path
        $Path = $content.nextLink -replace '^https://[^/]+', ''
    } while ($Path)

    return $items
}

$accountPath = "/providers/Microsoft.Billing/billingAccounts/$BillingAccountID"

if ($BillingRoleAssignmentID) {
    # https://learn.microsoft.com/en-us/rest/api/billing/billing-role-assignments/get-by-billing-account?view=rest-billing-2019-10-01-preview&tabs=HTTP
    $assignments = Invoke-BillingGet -Path "$accountPath/billingRoleAssignments/$BillingRoleAssignmentID`?api-version=2019-10-01-preview"
}
else {
    # https://learn.microsoft.com/en-us/rest/api/billing/billing-role-assignments/list-by-billing-account?view=rest-billing-2019-10-01-preview&tabs=HTTP
    $assignments = Invoke-BillingGet -Path "$accountPath/billingRoleAssignments?api-version=2019-10-01-preview"
}

if ($ServicePrincipalObjectID) {
    $assignments = @($assignments | Where-Object { $_.properties.principalId -eq $ServicePrincipalObjectID })
}

# https://learn.microsoft.com/en-us/rest/api/billing/billing-role-definition/list-by-billing-account?view=rest-billing-2024-04-01&tabs=HTTP
$roleNames = @{}
foreach ($roleDefinition in Invoke-BillingGet -Path "$accountPath/billingRoleDefinitions?api-version=2024-04-01") {
    $roleNames[$roleDefinition.id] = $roleDefinition.properties.roleName
}

$assignments |
    Select-Object -Property @{
                                Name = 'RoleID'
                                Expression = { $_.id }
                            },
                            @{
                                Name = 'RoleName'
                                Expression = { $roleNames[$_.properties.roleDefinitionId] }
                            },

                            @{
                                Name = 'PrincipalID'
                                Expression = { $_.properties.principalId }
                            },
                            @{
                                Name = 'CreatedOn'
                                Expression = { $_.properties.createdOn }
                            },
                            @{
                                Name = 'ModifiedOn'
                                Expression = { $_.properties.modifiedOn }
                            }
