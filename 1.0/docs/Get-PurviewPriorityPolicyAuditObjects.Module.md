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

The module queries `Search-UnifiedAuditLog` using session-based paging, filters for records whose `AuditData` payload contains `prioritycleanup`, normalises each match into a typed `PurviewPriorityAuditResult` object, and optionally exports results to CSV.

## Get-PurviewPriorityPolicyAuditObjects Cmdlets

### [Get-PurviewPriorityPolicyAuditObjects](Get-PurviewPriorityPolicyAuditObjects.md)

Retrieves and parses Microsoft Purview priority cleanup audit events from the Unified Audit Log.
