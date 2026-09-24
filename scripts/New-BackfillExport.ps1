#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Creates FOCUS cost backfill exports against an Azure billing account.

.DESCRIPTION
    Calls the Azure Cost Management REST API directly as the logged-in user,
    so the function app's managed identity does not need the EnrollmentReader
    role on the billing account.  The caller must have sufficient billing-scope
    permissions (e.g. Enterprise Admin or Billing Account Contributor).

    Each export is created as an inactive, one-off task pointing at the same
    storage account the Terraform module provisions.

.PARAMETER BillingAccountId
    The billing account ID in Azure format, e.g.
    "bdfa614c-3bed-5e6d-313b-b4bfa3cefe1d:16e4ddda-0100-468b-a32c-abbfc29019d8_2019-05-31"

.PARAMETER StorageAccountResourceId
    Full ARM resource ID of the cost-export storage account, e.g.
    "/subscriptions/.../providers/Microsoft.Storage/storageAccounts/stcostexportp2h9yi0z"

.PARAMETER Container
    Blob container name.  Defaults to "cost-exports".

.PARAMETER RootFolderPath
    Root folder path inside the container.  Defaults to "gds-focus-v1".

.PARAMETER Location
    Azure region for the export resource.  Defaults to "uksouth".

.PARAMETER AccountIndex
    Numeric index matching the billing account's position in
    var.billing_account_ids (0-based).  Defaults to 0.

.PARAMETER Suffix
    Optional suffix appended to each export name, matching the Terraform
    variable cost_mgmt_suffix.  Leave empty when the module was deployed
    without one.

.PARAMETER Months
    Number of months to backfill (counting backwards from last month).
    Defaults to 12.

.PARAMETER DatasetVersion
    FOCUS dataset version.  Defaults to "1.0r2".

.PARAMETER Run
    When set, each export is executed (POST .../run) after creation.
    Exports are triggered in batches (see -BatchSize) with a cooldown
    between each batch (see -BatchIntervalSeconds).

.PARAMETER BatchSize
    Number of exports to trigger per batch when -Run is set.  Defaults to 3.

.PARAMETER BatchIntervalSeconds
    Seconds to wait between batches when -Run is set.  Defaults to 300
    (5 minutes).  A progress bar counts down during the wait.

.PARAMETER ApiVersion
    Cost Management API version.  Defaults to "2025-03-01".

.EXAMPLE
    $params = @{
        BillingAccountId         = "bdfa614c-..._2019-05-31"
        StorageAccountResourceId = "/subscriptions/.../storageAccounts/stcostexport..."
    }
    .\New-BackfillExport.ps1 @params

    Creates 12 months of inactive exports.
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([PSCustomObject])]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$BillingAccountId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$StorageAccountResourceId,

    [ValidateNotNullOrEmpty()]
    [string]$Container = 'cost-exports',

    [ValidateNotNullOrEmpty()]
    [string]$RootFolderPath = 'gds-focus-v1',

    [ValidateNotNullOrEmpty()]
    [string]$Location = 'uksouth',

    [ValidateRange(0, 99)]
    [int]$AccountIndex = 0,

    [string]$Suffix = '',

    [ValidateRange(1, 12)]
    [int]$Months = 12,

    [ValidateNotNullOrEmpty()]
    [string]$DatasetVersion = '1.0r2',

    [switch]$Run,

    [ValidateRange(1, 50)]
    [int]$BatchSize = 3,

    [ValidateRange(1, 3600)]
    [int]$BatchIntervalSeconds = 300,

    [ValidateNotNullOrEmpty()]
    [string]$ApiVersion = '2025-03-01'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


# --- helpers ----------------------------------------------------------------


function Get-ExportName {
    param([int]$Idx, [int]$Year, [int]$Month, [string]$Sfx)
    $sfxPart = if ($Sfx) { "-$Sfx" } else { '' }
    'focus-backfill{0}-{1}-{2:D4}-{3:D2}' -f $sfxPart, $Idx, $Year, $Month
}


function Get-DaysInMonth {
    param([int]$Year, [int]$Month)
    [DateTime]::DaysInMonth($Year, $Month)
}


function Wait-BatchInterval {
    param([int]$Seconds, [int]$CurrentBatch, [int]$TotalBatches)
    $activity = "Waiting between batches (completed $CurrentBatch of $TotalBatches)"
    for ($remaining = $Seconds; $remaining -gt 0; $remaining--) {
        $minutes = [int][math]::Floor($remaining / 60)
        $secs = $remaining % 60
        Write-Progress -Activity $activity `
            -Status ('{0:D2}:{1:D2} remaining' -f $minutes, $secs) `
            -PercentComplete ((($Seconds - $remaining) / $Seconds) * 100)
        Start-Sleep -Seconds 1
    }
    Write-Progress -Activity $activity -Completed
}


function Get-MonthRange {
    param([int]$Count)
    $cursor = (Get-Date).AddMonths(-1)
    $result = [System.Collections.Generic.List[PSCustomObject]]::new($Count)
    for ($i = 0; $i -lt $Count; $i++) {
        $result.Add([PSCustomObject]@{
                Year  = $cursor.Year
                Month = $cursor.Month
            })
        $cursor = $cursor.AddMonths(-1)
    }
    $result.Reverse()
    $result
}


# --- auth -------------------------------------------------------------------

Write-Verbose -Message 'Acquiring access token for Azure management plane...'

try {
    $tokenObj = Get-AzAccessToken -ResourceUrl 'https://management.azure.com' -ErrorAction Stop
    $token = if ($tokenObj.Token -is [securestring]) {
        $tokenObj.Token | ConvertFrom-SecureString -AsPlainText
    }
    else {
        $tokenObj.Token
    }
}
catch {
    $PSCmdlet.ThrowTerminatingError($_)
}

$headers = @{
    Authorization  = "Bearer $token"
    'Content-Type' = 'application/json'
}

# --- main loop --------------------------------------------------------------

$baseUrl = "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$BillingAccountId/providers/Microsoft.CostManagement/exports"
$monthRange = Get-MonthRange -Count $Months

Write-Verbose -Message "Creating $Months backfill exports for billing account: $BillingAccountId"
Write-Verbose -Message "Storage:   $StorageAccountResourceId"
Write-Verbose -Message "Container: $Container / $RootFolderPath"

$results = [System.Collections.Generic.List[PSCustomObject]]::new($Months)
$created = 0
$failed = 0
$index = 0

foreach ($m in $monthRange) {
    $year = $m.Year
    $month = $m.Month
    $exportName = Get-ExportName -Idx $AccountIndex -Year $year -Month $month -Sfx $Suffix
    $lastDay = Get-DaysInMonth -Year $year -Month $month
    $label = '{0:D4}-{1:D2}' -f $year, $month

    Write-Progress -Activity 'Creating backfill exports' -Status $label -PercentComplete (($index / $Months) * 100)

    $url = "$baseUrl/${exportName}?api-version=$ApiVersion"

    $body = @{
        location   = $Location
        identity   = @{ type = 'SystemAssigned' }
        properties = @{
            definition            = @{
                type       = 'FocusCost'
                dataSet    = @{
                    configuration = @{ dataVersion = $DatasetVersion }
                    granularity   = 'Daily'
                }
                timeframe  = 'Custom'
                timePeriod = @{
                    from = '{0:D4}-{1:D2}-01T00:00:00Z' -f $year, $month
                    to   = '{0:D4}-{1:D2}-{2:D2}T23:59:59Z' -f $year, $month, $lastDay
                }
            }
            schedule              = @{ status = 'Inactive' }
            format                = 'Parquet'
            deliveryInfo          = @{
                destination = @{
                    type           = 'AzureBlob'
                    resourceId     = $StorageAccountResourceId
                    container      = $Container
                    rootFolderPath = $RootFolderPath
                }
            }
            partitionData         = $true
            dataOverwriteBehavior = 'OverwritePreviousReport'
            compressionMode       = 'None'
        }
    } | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($exportName, "PUT export for $label")) {
        try {
            Invoke-RestMethod -Uri $url -Method Put -Headers $headers -Body $body -ContentType 'application/json' -Verbose:$false | Out-Null
            Write-Verbose -Message "  [CREATE] $label  $exportName"
            $created++
            $results.Add([PSCustomObject]@{
                    Month      = $label
                    ExportName = $exportName
                    Created    = $true
                    Executed   = $false
                })
        }
        catch {
            Write-Warning -Message "  [FAIL]   $label  $exportName -- $($_.Exception.Message)"
            $failed++
        }
    }
    $index++
}

Write-Progress -Activity 'Creating backfill exports' -Completed

Write-Verbose -Message "Done. Created: $created, Failed: $failed"
if ($failed -gt 0) {
    Write-Warning -Message "$failed of $Months export(s) failed to create. Review warnings above."
}

# --- run phase ---------------------------------------------------------------

if ($Run -and $results.Count -gt 0) {
    $totalBatches = [math]::Ceiling($results.Count / $BatchSize)
    Write-Verbose -Message "Running $($results.Count) export(s) in $totalBatches batch(es) of $BatchSize"

    for ($b = 0; $b -lt $totalBatches; $b++) {
        $batchStart = $b * $BatchSize
        $batchEnd = [math]::Min($batchStart + $BatchSize, $results.Count) - 1
        $batch = $results[$batchStart..$batchEnd]

        foreach ($export in $batch) {
            $runUrl = "$baseUrl/$($export.ExportName)/run?api-version=$ApiVersion"
            if ($PSCmdlet.ShouldProcess($export.ExportName, "POST run for $($export.Month)")) {
                try {
                    Invoke-RestMethod -Uri $runUrl -Method Post -Headers $headers -Verbose:$false | Out-Null
                    Write-Verbose -Message "  [RUN]    $($export.Month)  $($export.ExportName)"
                    $export.Executed = $true
                }
                catch {
                    Write-Warning -Message "  [RUN FAIL] $($export.Month)  $($export.ExportName) -- $($_.Exception.Message)"
                }
            }
        }

        if ($b -lt ($totalBatches - 1)) {
            Wait-BatchInterval -Seconds $BatchIntervalSeconds -CurrentBatch ($b + 1) -TotalBatches $totalBatches
        }
    }
}

# --- output ------------------------------------------------------------------

$results
