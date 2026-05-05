# Get-PurviewPriorityPolicyAuditObjects

A PowerShell module that retrieves and parses Microsoft Purview priority policy cleanup audit events from the Microsoft 365 Unified Audit Log.

## Overview

Microsoft Purview records audit events when priority cleanup operations run against retention and compliance policies. These events are written to the Unified Audit Log with `prioritycleanup` in their `AuditData` payload, but they are scattered across the full audit stream and are not surfaced in a dedicated view in the Purview portal.

This module queries `Search-UnifiedAuditLog` using session-based paging to retrieve the complete result set for a given date range, filters for priority cleanup events, normalises each record into a typed `PurviewPriorityAuditResult` object, and optionally exports the results to CSV.

## Requirements

| Requirement | Detail |
| --- | --- |
| PowerShell | 7.1 or later |
| ExchangeOnlineManagement | Required for `Connect-ExchangeOnline` and `Search-UnifiedAuditLog`. Installed automatically from PSGallery when `-ConnectExchangeOnline` is used and the module is absent. |
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

`-ConnectExchangeOnline` handles the session automatically and disconnects when the function completes.

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

### Save results to a variable for pipeline use

```powershell
$results = Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -ExportResults
$results | Format-Table CreationTime, Operation, User, CompletionStatus, RecordType -AutoSize
```

### Use an existing Exchange Online session

If you have already called `Connect-ExchangeOnline` in your session, omit `-ConnectExchangeOnline`:

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
| `OrganizationId` | Tenant organisation GUID |
| `Workload` | M365 workload (e.g. `Exchange`, `SharePoint`) |
| `ObjectId` | Affected object identifier from AuditData |
| `ItemType` | Item type from AuditData |
| `Action` | `Operation` field from inside the AuditData JSON |
| `AuditEvent` | `AuditEvent` field from inside the AuditData JSON |
| `RawAuditData` | Full parsed AuditData JSON object — all fields present in the API response |

The default `Format-Table` view shows: `CreationTime`, `Operation`, `User`, `CompletionStatus`, `RecordType`.

## Parameters reference

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `-StartDate` | datetime | 7 days ago | Start of the audit log search window |
| `-EndDate` | datetime | Now | End of the audit log search window |
| `-ConnectExchangeOnline` | switch | off | Auto-connect to Exchange Online. Installs `ExchangeOnlineManagement` if absent. Disconnects automatically on completion. |
| `-ExportResults` | switch | off | Export matched events to a timestamped CSV in `-LogDirectory` |
| `-ShowDetails` | switch | off | Write a full per-record detail block to the console for every match, iterating all `RawAuditData` properties |
| `-LogDirectory` | string | `$env:TEMP\PurviewPriorityAudit` | Directory for `Logging.txt` and CSV exports |

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
Search-UnifiedAuditLog pages through all records (ReturnLargeSet, 5000/page)
        ↓
Records are filtered: AuditData -match 'prioritycleanup'
        ↓
AuditData JSON is parsed; fields normalised into PurviewPriorityAuditResult objects
        ↓
Results sorted by CreationTime, optionally exported to CSV
```

A progress bar is displayed during retrieval showing the current page and running record count.

## Logging

Every run appends to `Logging.txt` in `-LogDirectory`. The log records connection steps, each matched event, export paths, and any errors or warnings encountered.

## License

MIT License — Copyright (c) 2026 Dave Goldman. See [LICENSE](LICENSE) for full terms.
