---
external help file: Get-PurviewPriorityPolicyAuditObjects-help.xml
Module Name: Get-PurviewPriorityPolicyAuditObjects
online version: https://github.com/dgoldman-msft/Get-PurviewPriorityPolicyAuditObjects
schema: 2.0.0
---

# Get-PurviewPriorityPolicyAuditObjects

## SYNOPSIS

Retrieves and parses Microsoft Purview priority cleanup audit events from the Unified Audit Log.

## SYNTAX

```powershell
Get-PurviewPriorityPolicyAuditObjects
    [-StartDate <DateTime>]
    [-EndDate <DateTime>]
    [-ConnectExchangeOnline]
    [-DisableBanner]
    [-ExportResults]
    [-ShowDetails]
    [-DumpErrors]
    [-LogDirectory <String>]
    [<CommonParameters>]
```

## DESCRIPTION

Queries the Unified Audit Log via `Search-UnifiedAuditLog` and filters for events related to Purview priority policy cleanup operations — specifically, records whose `AuditData` payload contains the string `prioritycleanup`.

The function uses session-based paging (`-SessionCommand ReturnLargeSet`, 5 000 records per page) to retrieve the full result set for the specified date range. A progress bar is displayed during retrieval showing the current page number and running record count.

Each matched record is parsed and normalised into a typed `PurviewPriorityAuditResult` object. The original unmodified JSON string is preserved in `RawAuditDataJson`. Results are sorted by `CreationTime` and emitted to the pipeline. Optionally they can be exported to a timestamped CSV file.

Use `-DumpErrors` to write all error `AuditData` fields to `Errors.log`. Error events are always stored in `$global:PurviewAuditErrors`.

Requires active Exchange Online and Security & Compliance Center sessions (`Connect-ExchangeOnline` and `Connect-IPPSSession`). Use `-ConnectExchangeOnline` to have the function connect and disconnect both sessions automatically.

## EXAMPLES

### Example 1: Connect and retrieve the last 7 days

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline
```

Connects to Exchange Online, retrieves all Unified Audit Log records from the last 7 days, filters for priority cleanup events, and outputs the results as `PurviewPriorityAuditResult` objects. The session is disconnected automatically when the function completes.

### Example 2: Custom date range with CSV export

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline `
    -StartDate (Get-Date).AddDays(-30) `
    -EndDate   (Get-Date) `
    -ExportResults
```

Searches the last 30 days and writes a timestamped CSV to `$env:TEMP\PurviewPriorityAudit\`.

### Example 3: Show full per-record detail on the console

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -ShowDetails
```

In addition to emitting objects to the pipeline, writes a colour-coded detail block to the console for every matched event. Each block lists all fields from the parsed `AuditData` JSON payload, alphabetically ordered.

### Example 4: Save results to a variable and inspect

```powershell
$results = Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -ExportResults
$results | Format-Table CreationTime, Operation, User, CompletionStatus, RecordType -AutoSize
```

Captures the output for further pipeline processing. The `-ExportResults` switch writes the CSV simultaneously.

### Example 5: Use an existing Exchange Online session

```powershell
Get-PurviewPriorityPolicyAuditObjects -StartDate (Get-Date).AddDays(-14)
```

When `Connect-ExchangeOnline` has already been called in the session, omit `-ConnectExchangeOnline`. The function validates that `Search-UnifiedAuditLog` is available and proceeds directly.

### Example 6: Custom log directory

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline `
    -ExportResults `
    -LogDirectory 'C:\AuditReports\Purview'
```

Writes `Logging.txt` and the CSV export to a custom path instead of the default `$env:TEMP\PurviewPriorityAudit\` folder.

### Example 7: Connect without the banner

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -DisableBanner
```

Passes `-ShowBanner:$false` to both `Connect-ExchangeOnline` and `Connect-IPPSSession`, suppressing the connection banner. Useful in automated or CI/CD contexts where the banner adds noise to captured output.

### Example 8: Dump full error details to Errors.log

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -DumpErrors
```

For every event where `CompletionStatus = Error`, writes all `AuditData` fields (depth 20, multi-line) to `Errors.log` in `-LogDirectory`.

### Example 9: Inspect post-run globals

```powershell
# Error events from the last run
$global:PurviewAuditErrors | Format-Table CreationTime, Operation, User, CompletionStatus, RecordType, OrganizationId, ObjectId -AutoSize

# Raw unmodified AuditData JSON for the first error
$global:PurviewAuditErrors[0].RawAuditDataJson
```

## PARAMETERS

### -StartDate

The start of the audit log search window passed to `Search-UnifiedAuditLog`.

Defaults to 7 days before the current date and time.

```yaml
Type: DateTime
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: (Get-Date).AddDays(-7)
Accept pipeline input: False
Accept wildcard characters: False
```

### -EndDate

The end of the audit log search window passed to `Search-UnifiedAuditLog`.

Defaults to the current date and time.

```yaml
Type: DateTime
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: (Get-Date)
Accept pipeline input: False
Accept wildcard characters: False
```

### -ConnectExchangeOnline

When specified, the function checks for the `ExchangeOnlineManagement` module, installs it from PSGallery if absent, imports it, and calls both `Connect-ExchangeOnline` and `Connect-IPPSSession` (Security & Compliance Center). In the `end` block both sessions are automatically closed via `Disconnect-ExchangeOnline`.

If active sessions already exist, omit this switch and the function will use the existing connections.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -DisableBanner

When specified together with `-ConnectExchangeOnline`, passes `-ShowBanner:$false` to both `Connect-ExchangeOnline` and `Connect-IPPSSession` to suppress the EXO module connection banner.

Has no effect if `-ConnectExchangeOnline` is not also specified.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ExportResults

When specified, exports the sorted results to a CSV file named `PurviewPriorityAudit_<yyyyMMdd_HHmmss>.csv` inside `-LogDirectory`. The CSV includes all normalised properties.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -ShowDetails

When specified, writes a colour-coded per-record detail block to the console after the retrieval loop completes. Each block shows the fixed summary fields followed by every property present in the parsed `RawAuditDataJson` payload, sorted alphabetically. Nested objects and arrays are rendered as compact JSON inline. `Parameters` and `NonPIIParameters` fields are expanded so each `-Name "Value"` pair appears on its own line.

Objects are emitted to the pipeline regardless of whether this switch is set.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -DumpErrors

When specified, writes a detailed block to `Errors.log` in `-LogDirectory` for every event where `CompletionStatus = Error`. The block includes all fields from the record's `AuditData` JSON, serialised to depth 20 with no truncation. Each error event is also stamped with a `Diagnosis` property containing a human-readable likely cause derived from the parameter values present in the audit record. Operations with active diagnosis logic: `New-ComplianceTag` (RetentionDuration, RetentionAction, RetentionType, PriorityCleanup rules), `Set-ComplianceTag` (RetentionDuration), `New-RetentionComplianceRule` (RetentionDuration, RetentionComplianceAction, ExpirationDateOption). Policy cmdlets (`New/Set-RetentionCompliancePolicy`) return `Unknown` — they carry no diagnosable retention parameters in their audit data.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

### -LogDirectory

Full path to the directory used for `Logging.txt`, `Errors.log`, and any CSV exports. The directory is created automatically if it does not exist.

Defaults to `$env:TEMP\PurviewPriorityAudit`.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: $env:TEMP\PurviewPriorityAudit
Accept pipeline input: False
Accept wildcard characters: False
```

### CommonParameters

This cmdlet supports the common parameters: `-Debug`, `-ErrorAction`, `-ErrorVariable`, `-InformationAction`, `-InformationVariable`, `-OutVariable`, `-OutBuffer`, `-PipelineVariable`, `-Verbose`, `-WarningAction`, and `-WarningVariable`. For more information, see [about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### None

This function does not accept pipeline input.

## OUTPUTS

### PurviewPriorityAuditResult

One object per matched audit event. The default `Format-Table` view shows `CreationTime`, `Operation`, `User`, `CompletionStatus`, and `RecordType`.

| Property | Type | Description |
| --- | --- | --- |
| `CreationTime` | DateTime | Timestamp of the audit event |
| `Operation` | String | Operation name from the audit record |
| `User` | String | UPN of the user or service principal that triggered the event |
| `CompletionStatus` | String | Result status (`ResultStatus` or `CompletionStatus` from AuditData) |
| `RecordType` | String | Audit record type from Exchange Online |
| `OrganizationId` | String | Tenant organisation GUID |
| `Workload` | String | M365 workload (e.g. `Exchange`, `SharePoint`) |
| `ObjectId` | String | Affected object identifier from AuditData |
| `ItemType` | String | Item type from AuditData |
| `Action` | String | `Operation` field from inside the AuditData JSON |
| `AuditEvent` | String | `AuditEvent` field from inside the AuditData JSON |
| `RawAuditDataJson` | String | Original unmodified AuditData JSON string as returned by the UAL API |

## NOTES

- Requires the **Audit Logs** role in Exchange Online (included in Compliance Administrator, Security Administrator, and Global Administrator).
- The Unified Audit Log must be enabled for the tenant. See [Turn auditing on or off](https://learn.microsoft.com/en-us/purview/audit-log-enable-disable).
- `-ConnectExchangeOnline` calls both `Connect-ExchangeOnline` (for `Search-UnifiedAuditLog`) and `Connect-IPPSSession` (Security & Compliance Center). A single `Disconnect-ExchangeOnline` closes both sessions.
- Session-based paging retrieves up to 5 000 records per request. For large tenants or long date ranges the retrieval loop may take several minutes.
- The function uses `-HighCompleteness` to maximise result accuracy at the cost of some additional latency.
- All error events from the last run are in `$global:PurviewAuditErrors`. Each object has a `Diagnosis` property with the likely cause stamped automatically.
- All runs append to `Logging.txt` in `-LogDirectory`. When `-DumpErrors` is specified, `Errors.log` is written to the same directory. Rotate or archive these files as needed.

**Aliases:** `GPPPAudit`, `Get-PriorityPolicyAudit`

## RELATED LINKS

- [Project repository](https://github.com/dgoldman-msft/Get-PurviewPriorityPolicyAuditObjects)
- [Search-UnifiedAuditLog](https://learn.microsoft.com/en-us/powershell/module/exchange/search-unifiedauditlog)
- [Connect-ExchangeOnline](https://learn.microsoft.com/en-us/powershell/module/exchange/connect-exchangeonline)
- [Connect-IPPSSession](https://learn.microsoft.com/en-us/powershell/module/exchange/connect-ippssession)
- [Turn auditing on or off](https://learn.microsoft.com/en-us/purview/audit-log-enable-disable)
- [Audit log activities](https://learn.microsoft.com/en-us/purview/audit-log-activities)
- [New-ComplianceTag](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-compliancetag?view=exchange-ps)
- [Set-ComplianceTag](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/set-compliancetag?view=exchange-ps)
- [New-RetentionCompliancePolicy](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-retentioncompliancepolicy?view=exchange-ps)
- [Set-RetentionCompliancePolicy](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/set-retentioncompliancepolicy?view=exchange-ps)
- [New-RetentionComplianceRule](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-retentioncompliancerule?view=exchange-ps)
