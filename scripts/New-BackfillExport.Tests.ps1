#Requires -Modules Pester

BeforeAll {
    $script:ScriptPath = Join-Path -Path $PSScriptRoot -ChildPath 'New-BackfillExport.ps1'

    # Parse helper functions out of the script via AST so they can be
    # tested without executing the main body or requiring Az.Accounts.
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput(
        (Get-Content -Path $script:ScriptPath -Raw),
        [ref]$tokens,
        [ref]$parseErrors
    )
    $ast.FindAll(
        { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] },
        $false
    ) | ForEach-Object -Process {
        . ([scriptblock]::Create($_.Extent.Text))
    }
}

Describe 'Get-ExportName' {
    It 'formats correctly without a suffix' {
        Get-ExportName -Idx 0 -Year 2025 -Month 3 -Sfx '' |
        Should -BeExactly 'focus-backfill-0-2025-03'
    }

    It 'formats correctly with a suffix' {
        Get-ExportName -Idx 1 -Year 2024 -Month 12 -Sfx 'tenant2' |
        Should -BeExactly 'focus-backfill-tenant2-1-2024-12'
    }

    It 'zero-pads single-digit months' {
        Get-ExportName -Idx 0 -Year 2025 -Month 1 -Sfx '' |
        Should -BeExactly 'focus-backfill-0-2025-01'
    }

    It 'uses the account index in the name' {
        Get-ExportName -Idx 5 -Year 2025 -Month 6 -Sfx '' |
        Should -BeExactly 'focus-backfill-5-2025-06'
    }
}

Describe 'Get-DaysInMonth' {
    It 'returns 31 for January' {
        Get-DaysInMonth -Year 2025 -Month 1 | Should -Be 31
    }

    It 'returns 28 for February in a non-leap year' {
        Get-DaysInMonth -Year 2025 -Month 2 | Should -Be 28
    }

    It 'returns 29 for February in a leap year' {
        Get-DaysInMonth -Year 2024 -Month 2 | Should -Be 29
    }

    It 'returns 30 for April' {
        Get-DaysInMonth -Year 2025 -Month 4 | Should -Be 30
    }
}

Describe 'Get-MonthRange' {
    It 'returns the requested number of months' {
        Get-MonthRange -Count 3 | Should -HaveCount 3
    }

    It 'is ordered oldest-first' {
        $result = Get-MonthRange -Count 3
        $first = [datetime]::new($result[0].Year, $result[0].Month, 1)
        $last = [datetime]::new($result[2].Year, $result[2].Month, 1)
        $first | Should -BeLessThan $last
    }

    It 'ends at last month' {
        $expected = (Get-Date).AddMonths(-1)
        $result = Get-MonthRange -Count 1
        $result[0].Year  | Should -Be $expected.Year
        $result[0].Month | Should -Be $expected.Month
    }

    It 'spans the correct range for 12 months' {
        $result = Get-MonthRange -Count 12
        $result | Should -HaveCount 12
        $oldest = [datetime]::new($result[0].Year, $result[0].Month, 1)
        $newest = [datetime]::new($result[11].Year, $result[11].Month, 1)
        $spanMonths = (($newest.Year - $oldest.Year) * 12) + ($newest.Month - $oldest.Month)
        $spanMonths | Should -Be 11
    }
}

Describe 'New-BackfillExport script' -Tag 'Integration' {
    BeforeAll {
        # Stub Get-AzAccessToken when Az.Accounts is not loaded so Pester
        # can create a mock for it.
        if (-not (Get-Command -Name 'Get-AzAccessToken' -ErrorAction SilentlyContinue)) {
            function global:Get-AzAccessToken {
                param($ResourceUrl, $ErrorAction)
            }
        }
    }

    BeforeEach {
        Mock -CommandName 'Get-AzAccessToken' -MockWith {
            [PSCustomObject]@{ Token = 'fake-token' }
        }
        Mock -CommandName 'Invoke-RestMethod'
    }

    Context 'successful creation' {
        It 'creates one export per month' {
            $result = & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 3

            $result | Should -HaveCount 3
        }

        It 'outputs objects with the expected properties' {
            $result = & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 1

            $result.Month      | Should -Not -BeNullOrEmpty
            $result.ExportName | Should -Not -BeNullOrEmpty
            $result.Created    | Should -BeTrue
            $result.Executed   | Should -BeFalse
        }

        It 'calls Invoke-RestMethod with PUT for each month' {
            & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 2 | Out-Null

            Should -Invoke -CommandName 'Invoke-RestMethod' -Times 2 -Exactly -ParameterFilter {
                $Method -eq 'Put'
            }
        }

        It 'targets the correct billing account in the URL' {
            & $script:ScriptPath `
                -BillingAccountId 'my-billing-acct' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 1 | Out-Null

            Should -Invoke -CommandName 'Invoke-RestMethod' -ParameterFilter {
                $Uri -like '*billingAccounts/my-billing-acct/*'
            }
        }

        It 'includes the requested API version in the URL' {
            & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 1 `
                -ApiVersion '2025-03-01' | Out-Null

            Should -Invoke -CommandName 'Invoke-RestMethod' -ParameterFilter {
                $Uri -like '*api-version=2025-03-01*'
            }
        }

        It 'sends partitionData as a JSON boolean' {
            & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 1 | Out-Null

            Should -Invoke -CommandName 'Invoke-RestMethod' -ParameterFilter {
                $parsed = $Body | ConvertFrom-Json
                $parsed.properties.partitionData -is [bool] -and
                $parsed.properties.partitionData -eq $true
            }
        }

        It 'sets the schedule to Inactive' {
            & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 1 | Out-Null

            Should -Invoke -CommandName 'Invoke-RestMethod' -ParameterFilter {
                $parsed = $Body | ConvertFrom-Json
                $parsed.properties.schedule.status -eq 'Inactive'
            }
        }

        It 'sends the correct storage destination' {
            $storageId = '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/sttest'
            & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId $storageId `
                -Container 'my-container' `
                -RootFolderPath 'my-root' `
                -Months 1 | Out-Null

            Should -Invoke -CommandName 'Invoke-RestMethod' -ParameterFilter {
                $dest = ($Body | ConvertFrom-Json).properties.deliveryInfo.destination
                $dest.resourceId -eq $storageId -and
                $dest.container -eq 'my-container' -and
                $dest.rootFolderPath -eq 'my-root'
            }
        }

        It 'formats the time period correctly' {
            & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 1 | Out-Null

            Should -Invoke -CommandName 'Invoke-RestMethod' -ParameterFilter {
                $tp = ($Body | ConvertFrom-Json).properties.definition.timePeriod
                $tp.from.ToString('o') -match '^\d{4}-\d{2}-01T00:00:00.0000000Z$' -and
                $tp.to.ToString('o') -match '^\d{4}-\d{2}-\d{2}T23:59:59.0000000Z$'
            }
        }

        It 'applies the suffix to export names' {
            $result = & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Suffix 'tenant2' `
                -Months 1

            $result.ExportName | Should -BeLike 'focus-backfill-tenant2-*'
        }
    }

    Context 'API failure handling' {
        BeforeEach {
            Mock -CommandName 'Get-AzAccessToken' -MockWith {
                [PSCustomObject]@{ Token = 'fake-token' }
            }
            Mock -CommandName 'Invoke-RestMethod' -MockWith {
                throw 'Simulated API error'
            }
        }

        It 'continues to the next month after a failure' {
            & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 3 `
                -WarningAction SilentlyContinue | Out-Null

            Should -Invoke -CommandName 'Invoke-RestMethod' -Times 3 -Exactly
        }

        It 'does not output an object for a failed export' {
            $result = & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 1 `
                -WarningAction SilentlyContinue

            $result | Should -BeNullOrEmpty
        }
    }

    Context 'WhatIf support' {
        It 'does not call the API when -WhatIf is set' {
            & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 2 `
                -WhatIf | Out-Null

            Should -Invoke -CommandName 'Invoke-RestMethod' -Times 0 -Exactly
        }
    }

    Context 'run phase' {
        BeforeEach {
            Mock -CommandName 'Get-AzAccessToken' -MockWith {
                [PSCustomObject]@{ Token = 'fake-token' }
            }
            Mock -CommandName 'Invoke-RestMethod'
            Mock -CommandName 'Start-Sleep'
        }

        It 'triggers POST run calls when -Run is set' {
            & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 2 `
                -Run | Out-Null

            Should -Invoke -CommandName 'Invoke-RestMethod' -Times 2 -Exactly -ParameterFilter {
                $Method -eq 'Post' -and $Uri -like '*/run?*'
            }
        }

        It 'sets Executed to true for successfully run exports' {
            $result = & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 1 `
                -Run

            $result.Executed | Should -BeTrue
        }

        It 'waits between batches' {
            & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 4 `
                -Run `
                -BatchSize 2 `
                -BatchIntervalSeconds 10 | Out-Null

            Should -Invoke -CommandName 'Start-Sleep' -Times 10 -Exactly
        }

        It 'does not wait after the final batch' {
            & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 2 `
                -Run `
                -BatchSize 2 `
                -BatchIntervalSeconds 10 | Out-Null

            Should -Invoke -CommandName 'Start-Sleep' -Times 0 -Exactly
        }

        It 'does not trigger runs without -Run' {
            & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 2 | Out-Null

            Should -Invoke -CommandName 'Invoke-RestMethod' -Times 0 -Exactly -ParameterFilter {
                $Method -eq 'Post'
            }
        }
    }

    Context 'SecureString token handling' {
        It 'extracts the token when Get-AzAccessToken returns a SecureString' {
            Mock -CommandName 'Get-AzAccessToken' -MockWith {
                [PSCustomObject]@{
                    Token = ConvertTo-SecureString -String 'secure-token-value' -AsPlainText -Force
                }
            }

            & $script:ScriptPath `
                -BillingAccountId 'test-id' `
                -StorageAccountResourceId '/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st' `
                -Months 1 | Out-Null

            Should -Invoke -CommandName 'Invoke-RestMethod' -ParameterFilter {
                $Headers.Authorization -eq 'Bearer secure-token-value'
            }
        }
    }
}
