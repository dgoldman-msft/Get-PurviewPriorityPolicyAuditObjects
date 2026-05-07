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
    [-UserPrincipalName <String>]
    [-DisableBanner]
    [-ShowDetails]
    [-DumpErrors]
    [-StayConnected]
    [-LogDirectory <String>]
    [<CommonParameters>]
```

## DESCRIPTION

Queries the Unified Audit Log via `Search-UnifiedAuditLog` and filters for events related to Purview priority policy cleanup operations — specifically, records whose `AuditData` payload contains the string `prioritycleanup`.

The function uses session-based paging (`-SessionCommand ReturnLargeSet`, 5 000 records per page, `-HighCompleteness`) to retrieve the full result set for the specified date range. A server-side `-FreeText 'priority cleanup'` pre-filter reduces unnecessary traffic. A progress bar is displayed during retrieval showing the current page number and running record count.

Each matched record is parsed and normalised into a typed `PurviewPriorityAuditResult` object. Key fields are pre-formatted for readability:

- `Parameters` and `NonPIIParameters` — each `-Name "Value"` pair on its own line; `Name/Value` array entries (e.g. from `CmdletOptions`) expanded with each cmdlet parameter on its own line.
- `ExtendedProperties` — each entry expanded as `Name: Value`.
- `RawAuditDataJson` — original unmodified JSON string preserved on each object.

Results are sorted by `CreationTime` and emitted to the pipeline.

All log files are **timestamped per run** so prior runs are never overwritten. When `-ShowDetails` is active every result object is written in full to `AuditResultObjects_<stamp>.log`. When `-DumpErrors` is active all error `AuditData` fields are written to `Errors_<stamp>.log`.

Use `-ConnectExchangeOnline` to connect automatically. Pair it with `-UserPrincipalName` to enable silent MSAL token reuse for the IPPS session so only one interactive logon prompt is shown. Use `-StayConnected` to suppress automatic disconnection at the end of the function.

Requires ExchangeOnlineManagement **3.9.2 or later** — the module manifest enforces this as a `RequiredModules` constraint and the runtime install/upgrade logic enforces a `-MinimumVersion` check.

## EXAMPLES

### Example 1: Connect and retrieve the last 7 days

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline
```

Connects to Exchange Online and the Security & Compliance Center, retrieves all priority cleanup audit events from the last 7 days, and outputs typed `PurviewPriorityAuditResult` objects. Both sessions are disconnected automatically when the function completes.

### Example 2: Provide a UPN to avoid a second logon prompt

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline `
    -UserPrincipalName 'admin@contoso.onmicrosoft.com' `
    -DisableBanner
```

Passes the UPN to both `Connect-ExchangeOnline` and `Connect-IPPSSession`. The EXO module's MSAL token cache is used for the IPPS connection so only one interactive browser prompt is shown.

### Example 3: Custom date range

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline `
    -StartDate (Get-Date).AddDays(-30) `
    -EndDate   (Get-Date)
```

Searches the last 30 days instead of the default 7.

### Example 4: Show full per-record detail

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -ShowDetails
```

Writes a colour-coded detail block to the console for every matched event. Each block lists all fields from the parsed `AuditData` JSON payload, alphabetically ordered. `Name/Value` array fields (`ExtendedProperties`, `Parameters` when returned as an array by the service) are fully expanded. The `-Name "Value"` cmdlet-string format is split so each parameter is on its own line. Every result object is also written to `AuditResultObjects_<stamp>.log`.

### Example 5: Dump full error details

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -DumpErrors
```

For every event where `CompletionStatus = Error`, writes all `AuditData` fields (depth 20, fully expanded) to `Errors_<stamp>.log` in `-LogDirectory`. Each error event is stamped with a `Diagnosis` property containing a human-readable likely cause.

### Example 6: Stay connected between runs

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -StayConnected
# ... additional work in the same session ...
Disconnect-ExchangeOnline
```

Skips `Disconnect-ExchangeOnline` in the `end` block so the session can be reused without re-authenticating.

### Example 7: Use an existing Exchange Online session

```powershell
Get-PurviewPriorityPolicyAuditObjects -StartDate (Get-Date).AddDays(-14)
```

Omit `-ConnectExchangeOnline` when `Connect-ExchangeOnline` has already been called. The function validates that `Search-UnifiedAuditLog` is available and proceeds.

### Example 8: Custom log directory

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline `
    -ShowDetails -DumpErrors `
    -LogDirectory 'C:\AuditReports\Purview'
```

Writes all log files to a custom path.

### Example 9: Save results and inspect post-run globals

```powershell
$results = Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -DumpErrors

# Summary table
$results | Format-Table CreationTime, Operation, User, CompletionStatus, RecordType -AutoSize

# Formatted Parameters on the first result
$results[0].Parameters

# Error events from the last run
$global:PurviewAuditErrors | Select-Object CreationTime, Operation, Diagnosis | Format-List
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

When specified, the function checks for `ExchangeOnlineManagement` 3.9.2 or later, installs or upgrades it from PSGallery if needed, imports it, and calls both `Connect-ExchangeOnline` and `Connect-IPPSSession`. In the `end` block both sessions are closed via `Disconnect-ExchangeOnline` unless `-StayConnected` is also specified.

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

### -UserPrincipalName

The UPN (e.g. `user@contoso.com`) passed to both `Connect-ExchangeOnline` and `Connect-IPPSSession`. When provided, `Connect-IPPSSession` performs a silent MSAL token acquisition from the cache populated by `Connect-ExchangeOnline`, avoiding a second interactive logon prompt.

If omitted, the UPN is retrieved automatically from `Get-ConnectionInformation` after the EXO connection is established.

Only used when `-ConnectExchangeOnline` is also specified.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
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

### -ShowDetails

When specified, writes a colour-coded per-record detail block to the console after the retrieval loop completes. Each block shows all properties present in the parsed `RawAuditDataJson` payload, sorted alphabetically.

`Name/Value` object arrays (e.g. `ExtendedProperties`, `Parameters` when returned as an array by the service) are iterated individually. Entries whose `Value` is a cmdlet invocation string are further split so each `-Parameter "Value"` token appears on its own line.

Flat string `Parameters` and `NonPIIParameters` fields receive the same split treatment.

Every result object is also written in full to `AuditResultObjects_<yyyyMMdd_HHmmss>.log` in `-LogDirectory`. Objects are emitted to the pipeline regardless of whether this switch is set.

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

When specified, writes a detailed block to `Errors_<yyyyMMdd_HHmmss>.log` in `-LogDirectory` for every event where `CompletionStatus = Error`. The block includes all fields from the record's `AuditData` JSON, serialised to depth 20 with no truncation. `Name/Value` arrays and cmdlet-string parameters are fully expanded onto separate lines.

Each error event is also stamped with a `Diagnosis` property containing a human-readable likely cause derived from the parameter values in the audit record.

Operations with active diagnosis logic:

| Operation | Validated fields |
| --- | --- |
| `New-ComplianceTag` | `RetentionDuration` (positive integer or `unlimited`), `RetentionAction` (Delete/Keep/KeepAndDelete), `RetentionType` (CreationAgeInDays/EventAgeInDays/ModificationAgeInDays/TaggedAgeInDays), `PriorityCleanup` requires `RetentionAction Delete` |
| `Set-ComplianceTag` | `RetentionDuration` |
| `New-RetentionComplianceRule` | `RetentionDuration`, `RetentionComplianceAction` (Delete/Keep/KeepAndDelete), `ExpirationDateOption` (CreationAgeInDays/ModificationAgeInDays) |
| `New/Set-RetentionCompliancePolicy` | No diagnosable parameters — returns `Unknown` |

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

### -StayConnected

When specified, the function skips `Disconnect-ExchangeOnline` in the `end` block, leaving both the Exchange Online and IPPS sessions open for subsequent calls in the same PowerShell session.

Only relevant when `-ConnectExchangeOnline` is also specified.

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

Full path to the directory used for all log files. The directory is created automatically if it does not exist. Each invocation creates new timestamped files so prior runs are never overwritten:

| File | Created when |
| --- | --- |
| `Logging_<yyyyMMdd_HHmmss>.txt` | Always |
| `Errors_<yyyyMMdd_HHmmss>.log` | `-DumpErrors` and at least one error event found |
| `AuditResultObjects_<yyyyMMdd_HHmmss>.log` | `-ShowDetails` |

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
| `Parameters` | String | Pre-formatted cmdlet parameters; each `-Name "Value"` pair on its own line; `Name/Value` array entries further split per parameter |
| `NonPIIParameters` | String | Same as `Parameters` but with PII values redacted by the service |
| `ExtendedProperties` | String | Expanded `Name: Value` lines from the `ExtendedProperties` array |
| `RawAuditDataJson` | String | Original unmodified AuditData JSON string as returned by the UAL API |

## NOTES

- Requires the **Audit Logs** role in Exchange Online (included in Compliance Administrator, Security Administrator, and Global Administrator).
- The Unified Audit Log must be enabled for the tenant. See [Turn auditing on or off](https://learn.microsoft.com/en-us/purview/audit-log-enable-disable).
- Requires **ExchangeOnlineManagement 3.9.2 or later**. Enforced by the module manifest (`RequiredModules`) and by a runtime version check that will install or upgrade the module automatically when `-ConnectExchangeOnline` is specified.
- `-ConnectExchangeOnline` calls both `Connect-ExchangeOnline` and `Connect-IPPSSession`. A single `Disconnect-ExchangeOnline` closes both sessions.
- When `-UserPrincipalName` is not supplied, the UPN is read from `Get-ConnectionInformation` after the EXO session is established, enabling silent MSAL token reuse for `Connect-IPPSSession`.
- Session-based paging retrieves up to 5 000 records per request. For large tenants or long date ranges the retrieval loop may take several minutes.
- The function uses `-HighCompleteness` to maximise result accuracy at the cost of some additional latency.
- All error events from the last run are in `$global:PurviewAuditErrors`. Each object has a `Diagnosis` property stamped automatically.
- All log files are timestamped. Historical runs accumulate in `-LogDirectory`; rotate or archive them as needed.

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


Requires active Exchange Online and Security & Compliance Center sessions (`Connect-ExchangeOnline` and `Connect-IPPSSession`). Use `-ConnectExchangeOnline` to have the function connect and disconnect both sessions automatically.
