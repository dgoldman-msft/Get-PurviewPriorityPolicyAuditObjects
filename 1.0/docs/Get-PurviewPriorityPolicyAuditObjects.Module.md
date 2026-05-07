---
Module Name: Get-PurviewPriorityPolicyAuditObjects
Module Guid: b9d3f2a4-71c8-4e5b-a917-e84c2b338f52
Download Help Link: https://github.com/dgoldman-msft/Get-PurviewPriorityPolicyAuditObjects
Help Version: 1.0
Locale: en-US
---

# Get-PurviewPriorityPolicyAuditObjects Module

## Description

Retrieves and parses Microsoft Purview priority policy cleanup audit events from the Microsoft 365 Unified Audit Log.

The module queries `Search-UnifiedAuditLog` using session-based paging with a `-FreeText 'priority cleanup'` server-side filter and `-HighCompleteness`, filters records client-side for `prioritycleanup` in `AuditData`, and normalises each match into a typed `PurviewPriorityAuditResult` object.

Key cmdlet parameters (`Parameters`, `NonPIIParameters`) are pre-formatted with each `-Name "Value"` pair on its own line. `ExtendedProperties` entries are expanded into `Name: Value` lines. All log files are timestamped per run so every execution is preserved.

Requires **ExchangeOnlineManagement 3.9.2 or later** — enforced by the module manifest and at runtime.

Use `-DumpErrors` to write full error details to a timestamped `Errors_<stamp>.log`. Use `-ShowDetails` to write every result object to `AuditResultObjects_<stamp>.log`. Error events are stored in `$global:PurviewAuditErrors` for post-run inspection.

Use `-ConnectExchangeOnline` with optional `-UserPrincipalName` to connect to both Exchange Online and the Security & Compliance Center automatically, with silent MSAL token reuse for the IPPS session. Use `-StayConnected` to keep the session open between calls.

## Get-PurviewPriorityPolicyAuditObjects Cmdlets

### [Get-PurviewPriorityPolicyAuditObjects](Get-PurviewPriorityPolicyAuditObjects.md)

Retrieves and parses Microsoft Purview priority cleanup audit events from the Unified Audit Log.
