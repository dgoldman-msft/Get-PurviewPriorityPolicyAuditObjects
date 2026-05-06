# Get-PurviewPriorityPolicyAuditObjects

A PowerShell module that retrieves and parses Microsoft Purview priority policy cleanup audit events from the Microsoft 365 Unified Audit Log.

## Overview

Microsoft Purview records audit events when priority cleanup operations run against retention and compliance policies. These events are written to the Unified Audit Log with `prioritycleanup` in their `AuditData` payload, but they are scattered across the full audit stream and are not surfaced in a dedicated view in the Purview portal.

This module queries `Search-UnifiedAuditLog` using session-based paging to retrieve the complete result set for a given date range, filters for priority cleanup events, normalises each record into a typed `PurviewPriorityAuditResult` object, and optionally exports the results to CSV.

## Requirements

| Requirement | Detail |
| --- | --- |
| PowerShell | 7.1 or later |
| ExchangeOnlineManagement | Required for `Connect-ExchangeOnline`, `Connect-IPPSSession`, and `Search-UnifiedAuditLog`. Installed automatically from PSGallery when `-ConnectExchangeOnline` is used and the module is absent. |
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

### Specify a custom date range

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline `
    -StartDate (Get-Date).AddDays(-30) `
    -EndDate   (Get-Date)
```

### Export results to CSV

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -ExportResults
```

Results are written to a timestamped CSV inside `-LogDirectory` (default: `$env:TEMP\PurviewPriorityAudit\`).

### Show full per-record detail

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -ShowDetails
```

Writes a colour-coded block to the console for every matched event showing all fields from the parsed `AuditData` JSON payload. Objects are still emitted to the pipeline.

### Dump full error details to Errors.log

```powershell
Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -DumpErrors
```

Whenever error events are found (`CompletionStatus = Error`), writes every field from every error record's `AuditData` to `Errors.log` in `-LogDirectory` (all fields, depth 20, no truncation). Each error event is also stamped with a `Diagnosis` property containing a human-readable likely cause derived from the parameter values in the audit record. Covered operations: `New-ComplianceTag`, `Set-ComplianceTag`, `New-RetentionComplianceRule`. `New-RetentionCompliancePolicy` and `Set-RetentionCompliancePolicy` return an `Unknown` cause (those cmdlets do not carry diagnosable retention parameters in their audit data).

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
$results = Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -ExportResults
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
| `RawAuditDataJson` | The original unmodified AuditData JSON string as returned by the UAL API |

The default `Format-Table` view shows: `CreationTime`, `Operation`, `User`, `CompletionStatus`, `RecordType`.

## Parameters reference

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `-StartDate` | datetime | 7 days ago | Start of the audit log search window |
| `-EndDate` | datetime | Now | End of the audit log search window |
| `-ConnectExchangeOnline` | switch | off | Auto-connects to Exchange Online **and** Security & Compliance Center (`Connect-IPPSSession`). Installs `ExchangeOnlineManagement` if absent. Both sessions are disconnected automatically on completion. |
| `-DisableBanner` | switch | off | Passes `-ShowBanner:$false` to both `Connect-ExchangeOnline` and `Connect-IPPSSession`. Only takes effect when `-ConnectExchangeOnline` is also specified. |
| `-ExportResults` | switch | off | Export matched events to a timestamped CSV in `-LogDirectory` |
| `-ShowDetails` | switch | off | Write a full per-record detail block to the console for every match, iterating all parsed `RawAuditDataJson` properties. `Parameters` and `NonPIIParameters` are expanded so each `-Name "Value"` pair is on its own line. |
| `-DumpErrors` | switch | off | Write full error detail (all `AuditData` fields, depth 20) to `Errors.log` in `-LogDirectory` for every event where `CompletionStatus = Error`. `Parameters` and `NonPIIParameters` are expanded so each `-Name "Value"` pair is on its own line. |
| `-LogDirectory` | string | `$env:TEMP\PurviewPriorityAudit` | Directory for `Logging.txt`, `Errors.log`, and CSV exports |

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
        ↓
Search-UnifiedAuditLog pages through all records (ReturnLargeSet, 5000/page)
        ↓
Records are filtered: AuditData -match 'prioritycleanup'
        ↓
AuditData JSON is parsed; fields normalized into PurviewPriorityAuditResult objects
RawAuditDataJson (original string) preserved on each object
        ↓
Results sorted by CreationTime, optionally exported to CSV
        ↓
If any errors found (CompletionStatus = Error):
  → Diagnosis stamped on each error event (likely cause from audit parameters)
  → Full AuditData written to Errors.log (if -DumpErrors)
  → $global:PurviewAuditErrors populated
  → Error summary table + per-error diagnosis displayed at end
```

A progress bar is displayed during retrieval showing the current page and running record count.

## Post-run global variables

| Variable | Content |
| --- | --- |
| `$global:PurviewAuditErrors` | Array of `PurviewPriorityAuditResult` objects where `CompletionStatus = Error`. Each object has a `Diagnosis` property with the likely cause. Populated on every run; `$null` if no errors. |

## Logging

Every run appends to `Logging.txt` in `-LogDirectory`. The log records connection steps, each matched event, export paths, and any errors or warnings encountered.

When `-DumpErrors` is specified and error events are found, a separate `Errors.log` is written to the same directory containing every field of every error record's `AuditData` JSON (all properties, serialised to depth 20).

## License

MIT License — Copyright (c) 2026 Dave Goldman. See [LICENSE](LICENSE) for full terms.
