@{
    # Module identity
    RootModule        = 'Get-PurviewPriorityPolicyAuditObjects.psm1'
    ModuleVersion     = '1.0'
    GUID              = 'b9d3f2a4-71c8-4e5b-a917-e84c2b338f52'
    Author            = 'Dave Goldman'
    CompanyName       = ' '
    Copyright         = '(c) Dave Goldman. All rights reserved.'

    # Description
    Description       = 'Retrieves and parses Microsoft Purview priority policy cleanup audit events from the Unified Audit Log. Filters Search-UnifiedAuditLog output for prioritycleanup-related operations, normalises records into typed output objects, and supports optional CSV export and logging.'

    # Minimum PowerShell version required
    PowerShellVersion = '7.1'

    # ExchangeOnlineManagement >= 3.9.2 is required at runtime but NOT listed in RequiredModules.
    # Listing it here would force PowerShell to import it at module-load time, which fails in
    # debug sessions where the module is not yet present. Version enforcement is done at runtime
    # inside the function when -ConnectExchangeOnline is used.
    RequiredModules   = @()

    # Format file
    FormatsToProcess  = @('.\xml\Get-PurviewPriorityPolicyAuditObjects.Format.ps1xml')

    # Exports
    FunctionsToExport = @(
        'Get-PurviewPriorityPolicyAuditObjects'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('GPPPAudit', 'Get-PriorityPolicyAudit')

    # Private data
    PrivateData       = @{
        PSData = @{
            Tags         = @('Purview', 'AuditLog', 'Exchange', 'Compliance', 'PriorityCleanup', 'UnifiedAuditLog', 'Security', 'MicrosoftPurview')
            LicenseUri   = 'https://github.com/dgoldman-msft/Get-PurviewPriorityPolicyAuditObjects/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/dgoldman-msft/Get-PurviewPriorityPolicyAuditObjects'
            ReleaseNotes = 'Initial release.'
        }
    }
}
