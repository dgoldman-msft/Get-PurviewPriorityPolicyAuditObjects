# Get-PurviewPriorityPolicyAuditObjects

A PowerShell module that retrieves and parses Microsoft Purview priority policy cleanup audit events from the Microsoft 365 Unified Audit Log.

## Overview

Microsoft Purview records audit events when priority cleanup operations run against retention and compliance policies. These events are written to the Unified Audit Log with `prioritycleanup` in their `AuditData` payload, but they are scattered across the full audit stream and are not surfaced in a dedicated view in the Purview portal.

This module queries `Search-UnifiedAuditLog` using session-based paging to retrieve the complete result set for a given date range, filters for priority cleanup events, and normalises each record into a typed `PurviewPriorityAuditResult` object. Key cmdlet parameters (`Parameters`, `NonPIIParameters`) are pre-formatted with each `-Name "Value"` pair on its own line. `ExtendedProperties` entries are expanded into `Name: Value` lines. All log files are timestamped so every run is preserved.

## Requirements

| Requirement | Detail |
| --- | --- |
| PowerShell | 7.1 or later |
| ExchangeOnlineManagement | **3.9.2 or later** — enforced both by the module manifest and at runtime. Installed or updated automatically from PSGallery when `-ConnectExchangeOnline` is used. |
| M365 role | **Audit Logs** role (included in Compliance Administrator, Security Administrator, Global Administrator) |
| Unified Audit Log | Must be enabled for the tenant. See [Turn auditing on or off](https://learn.microsoft.com/en-us/purview/audit-log-enable-disable). |

## Installation

```powershell
# Clone or download the repository, then import the module
Import-Module .\1.0\Get-PurviewPriorityPolicyAuditObjects.psd1
```

## Usage

### Connect and retrieve — last 7 days (default)

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline
```

`-ConnectExchangeOnline` connects to both Exchange Online and the Security & Compliance Center, then disconnects both when the function completes.

### Provide a UPN to avoid a second logon prompt

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline `
    -UserPrincipalName 'admin@contoso.onmicrosoft.com' `
    -DisableBanner
```

Passes `-UserPrincipalName` to both `Connect-ExchangeOnline` and `Connect-IPPSSession`. The EXO module's MSAL token cache is reused for the IPPS connection so only one interactive logon prompt is shown.

### Specify a custom date range

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline `
    -StartDate (Get-Date).AddDays(-30) `
    -EndDate   (Get-Date)
```

### Show full per-record detail

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -ShowDetails
```

Writes a colour-coded block to the console for every matched event showing all fields from the parsed `AuditData` JSON payload. `Parameters`, `NonPIIParameters` and array-typed fields (e.g. `ExtendedProperties`) are expanded so each entry is on its own line. Every result object is also written to a per-run `AuditResultObjects_<stamp>.log` file.

### Dump full error details to Errors log

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -DumpErrors
```

Whenever error events are found (`CompletionStatus = Error`), writes every field from every error record's `AuditData` to a timestamped `Errors_<stamp>.log` in `-LogDirectory`. Each error event is also stamped with a `Diagnosis` property containing a human-readable likely cause derived from the parameter values in the audit record. Covered operations: `New-ComplianceTag`, `Set-ComplianceTag`, `New-RetentionComplianceRule`. `New-RetentionCompliancePolicy` and `Set-RetentionCompliancePolicy` return an `Unknown` cause (those cmdlets do not carry diagnosable retention parameters in their audit data).

### Keep the session alive between runs

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -StayConnected
# ... make additional calls ...
Disconnect-ExchangeOnline
```

When `-StayConnected` is specified the function skips `Disconnect-ExchangeOnline` in its `end` block, leaving the session open for subsequent calls in the same PowerShell session.

### Review errors after a run

```powershell
# All error events from the last run
$global:PurviewAuditErrors | Format-Table CreationTime, Operation, User, CompletionStatus -AutoSize

# Diagnosis for each error
$global:PurviewAuditErrors | Select-Object CreationTime, Operation, Diagnosis | Format-List

# Full AuditData JSON for the first error
$global:PurviewAuditErrors[0].RawAuditDataJson
```

### Save results to a variable for pipeline use

```powershell
$results = Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline
$results | Format-Table CreationTime, Operation, User, CompletionStatus, RecordType -AutoSize
```

### Connect without the banner

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -DisableBanner
```

Passes `-ShowBanner:$false` to both `Connect-ExchangeOnline` and `Connect-IPPSSession`. Useful in automated or CI/CD contexts.

### Use an existing session

If you have already called `Connect-ExchangeOnline` and `Connect-IPPSSession` in your session, omit `-ConnectExchangeOnline`:

```powershell
Get-PurviewPriorityPolicyAuditObjects -StartDate (Get-Date).AddDays(-14)
```

## Output objects

Each matched event is returned as a `PurviewPriorityAuditResult` object.

| Property | Description |
| --- | --- |
| `CreationTime` | Timestamp of the audit event |
| `Operation` | Operation name from the audit record |
| `User` | UPN of the user or service principal that triggered the event |
| `CompletionStatus` | Result status of the operation (`ResultStatus` / `CompletionStatus` from AuditData) |
| `RecordType` | Audit record type from Exchange Online |
| `OrganizationId` | Tenant organization GUID |
| `Workload` | M365 workload (e.g. `Exchange`, `SharePoint`) |
| `ObjectId` | Affected object identifier from AuditData |
| `ItemType` | Item type from AuditData |
| `Action` | `Operation` field from inside the AuditData JSON |
| `AuditEvent` | `AuditEvent` field from inside the AuditData JSON |
| `Parameters` | Pre-formatted cmdlet parameters — each `-Name "Value"` pair on its own line |
| `NonPIIParameters` | Same as `Parameters` but with PII values redacted by the service |
| `ExtendedProperties` | Expanded `Name: Value` lines from the `ExtendedProperties` array |
| `RawAuditDataJson` | The original unmodified AuditData JSON string as returned by the UAL API |

The default `Format-Table` view shows: `CreationTime`, `Operation`, `User`, `CompletionStatus`, `RecordType`.

## Parameters reference

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `-StartDate` | datetime | 7 days ago | Start of the audit log search window |
| `-EndDate` | datetime | Now | End of the audit log search window |
| `-ConnectExchangeOnline` | switch | off | Auto-connects to Exchange Online **and** Security & Compliance Center (`Connect-IPPSSession`). Installs/updates `ExchangeOnlineManagement` (minimum 3.9.2) if needed. Both sessions are disconnected automatically on completion unless `-StayConnected` is set. |
| `-UserPrincipalName` | string | — | UPN passed to both `Connect-ExchangeOnline` and `Connect-IPPSSession`. Enables silent MSAL token reuse so only one interactive logon prompt is shown. Only used with `-ConnectExchangeOnline`. |
| `-DisableBanner` | switch | off | Passes `-ShowBanner:$false` to both connect cmdlets. Only takes effect with `-ConnectExchangeOnline`. |
| `-ShowDetails` | switch | off | Write a full per-record detail block to the console and to `AuditResultObjects_<stamp>.log`. `Parameters`, `NonPIIParameters`, and `ExtendedProperties` are fully expanded. |
| `-DumpErrors` | switch | off | Write full error detail (all `AuditData` fields, depth 20) to `Errors_<stamp>.log` for every event where `CompletionStatus = Error`. |
| `-StayConnected` | switch | off | Skip `Disconnect-ExchangeOnline` in the `end` block, leaving the session open for subsequent calls. |
| `-LogDirectory` | string | `$env:TEMP\PurviewPriorityAudit` | Directory for all log files. Each run creates new timestamped files so prior runs are preserved. |

## Aliases

| Alias | Resolves to |
| --- | --- |
| `GPPPAudit` | `Get-PurviewPriorityPolicyAuditObjects` |
| `Get-PriorityPolicyAudit` | `Get-PurviewPriorityPolicyAuditObjects` |

## How it works

```text
Exchange Online / Purview runs a priority cleanup operation
        ↓
An audit event is written to the Unified Audit Log
AuditData payload contains "prioritycleanup"
        ↓
Connect-ExchangeOnline + Connect-IPPSSession (if -ConnectExchangeOnline)
MSAL token reused for IPPS when -UserPrincipalName is supplied
        ↓
Search-UnifiedAuditLog pages through all records
(-FreeText 'priority cleanup', ReturnLargeSet, 5000/page, HighCompleteness)
        ↓
Client-side filter: AuditData -match 'priority.?cleanup'
        ↓
AuditData JSON parsed; fields normalised into PurviewPriorityAuditResult objects
Parameters / NonPIIParameters / ExtendedProperties pre-formatted on the object
RawAuditDataJson (original string) preserved on each object
        ↓
Results sorted by CreationTime and emitted to the pipeline
        ↓
If any errors found (CompletionStatus = Error):
  → Diagnosis stamped on each error event
  → Full AuditData written to Errors_<stamp>.log (if -DumpErrors)
  → $global:PurviewAuditErrors populated
  → Error summary table + per-error diagnosis displayed at end
        ↓
If -ShowDetails:
  → Colour-coded detail block per record written to console
  → Full result objects written to AuditResultObjects_<stamp>.log
```

A progress bar is displayed during retrieval showing the current page and running record count.

## Post-run global variables

| Variable | Content |
| --- | --- |
| `$global:PurviewAuditErrors` | Array of `PurviewPriorityAuditResult` objects where `CompletionStatus = Error`. Each object has a `Diagnosis` property with the likely cause. Populated on every run; `$null` if no errors. |

## Logging

Every run creates **new timestamped log files** in `-LogDirectory` (default: `$env:TEMP\PurviewPriorityAudit`):

| File | Created when | Content |
| --- | --- | --- |
| `Logging_<yyyyMMdd_HHmmss>.txt` | Always | Connection steps, matched event summary lines, warnings, run-end info |
| `Errors_<yyyyMMdd_HHmmss>.log` | `-DumpErrors` + errors found | All `AuditData` fields for every error event, depth 20, fully expanded |
| `AuditResultObjects_<yyyyMMdd_HHmmss>.log` | `-ShowDetails` | Every `$result` object with all properties on separate lines |

Prior runs are never overwritten — all historical runs accumulate in the log directory.

## License

MIT License — Copyright (c) 2026 Dave Goldman. See [LICENSE](LICENSE) for full terms.
