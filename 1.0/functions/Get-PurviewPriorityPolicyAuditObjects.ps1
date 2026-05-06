function Get-PurviewPriorityPolicyAuditObjects {
    <#
        .SYNOPSIS
            Retrieves and parses Microsoft Purview priority cleanup audit events from the Unified Audit Log.

        .DESCRIPTION
            Queries the Unified Audit Log via Search-UnifiedAuditLog and filters for events
            related to Purview priority policy cleanup operations (AuditData containing "prioritycleanup").

            The function uses session-based paging (ReturnLargeSet) to retrieve the full result set,
            normalises each record into a typed PurviewPriorityAuditResult object, and optionally
            exports results to CSV.

            Requires an active Exchange Online PowerShell session. Use -ConnectExchangeOnline to
            have the function connect automatically.

        .PARAMETER StartDate
            The start of the audit log search window.
            Defaults to 7 days before the current date/time.

        .PARAMETER EndDate
            The end of the audit log search window.
            Defaults to the current date/time.

        .PARAMETER ConnectExchangeOnline
            When specified, imports ExchangeOnlineManagement (installing from PSGallery if absent)
            and calls Connect-ExchangeOnline if no active session is detected. The session is
            automatically disconnected via Disconnect-ExchangeOnline when the function completes.

        .PARAMETER ExportResults
            When specified, exports the parsed results to a timestamped CSV file inside -LogDirectory.

        .PARAMETER ShowDetails
            When specified, writes a full per-record detail block to the console for every matched event,
            showing all parsed fields: CreationTime, Operation, OrganizationId, User, Workload, ObjectId,
            ItemType, Action, and AuditEvent. Objects are still emitted to the pipeline regardless.

        .PARAMETER LogDirectory
            Directory for Logging.txt and any CSV exports.
            Defaults to a 'PurviewPriorityAudit' subfolder inside $env:TEMP.

        .EXAMPLE
            Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline

            Connects to Exchange Online and retrieves all priority cleanup audit events from the last 7 days.

        .EXAMPLE
            Get-PurviewPriorityPolicyAuditObjects -StartDate (Get-Date).AddDays(-30) -EndDate (Get-Date) -ExportResults

            Searches the last 30 days and exports results to CSV.

        .EXAMPLE
            $results = Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -ExportResults
            $results | Format-Table CreationTime, Operation, User, Workload, ObjectId -AutoSize

        .OUTPUTS
            PurviewPriorityAuditResult — one object per matched audit event with properties:
                CreationTime, Operation, OrganizationId, User, Workload, ObjectId, ItemType, Action, AuditEvent

        .NOTES
            Requires the ExchangeOnlineManagement module and the Audit Logs role (or equivalent) in Exchange Online.
            The Unified Audit Log must be enabled for your tenant.
    #>

    [CmdletBinding(DefaultParameterSetName = 'Default')]
    [Alias('GPPPAudit', 'Get-PriorityPolicyAudit')]
    param(
        [Parameter()]
        [datetime]$StartDate = (Get-Date).AddDays(-7),

        [Parameter()]
        [datetime]$EndDate = (Get-Date),

        [Parameter()]
        [switch]$ConnectExchangeOnline,

        [Parameter()]
        [switch]$ExportResults,

        [Parameter()]
        [switch]$ShowDetails,

        [Parameter()]
        [string]$LogDirectory = (Join-Path $env:TEMP 'PurviewPriorityAudit')
    )

    begin {
        # Ensure log directory exists
        if (-not (Test-Path -Path $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }

        $separator = "$(Get-TimeStamp) " + ("-" * 80)
        Write-ToLogFile -StringObject $separator -LogDirectory $LogDirectory
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Starting Get-PurviewPriorityPolicyAuditObjects" -LogDirectory $LogDirectory
        Write-ToLogFile -StringObject "$(Get-TimeStamp) StartDate      : $StartDate" -LogDirectory $LogDirectory
        Write-ToLogFile -StringObject "$(Get-TimeStamp) EndDate        : $EndDate" -LogDirectory $LogDirectory
        Write-ToLogFile -StringObject "$(Get-TimeStamp) ExportResults  : $ExportResults" -LogDirectory $LogDirectory
        Write-ToLogFile -StringObject "$(Get-TimeStamp) LogDirectory   : $LogDirectory" -LogDirectory $LogDirectory

        # Optional auto-connect
        if ($ConnectExchangeOnline) {
            Write-Verbose "Auto-connecting to Exchange Online"
            Write-ToLogFile -StringObject "$(Get-TimeStamp) Checking for ExchangeOnlineManagement module" -LogDirectory $LogDirectory

            try {
                if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) ExchangeOnlineManagement not found. Installing from PSGallery..." -LogDirectory $LogDirectory
                    Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) ExchangeOnlineManagement installed successfully" -LogDirectory $LogDirectory
                }
                else {
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) ExchangeOnlineManagement module found" -LogDirectory $LogDirectory
                }

                Import-Module ExchangeOnlineManagement -ErrorAction Stop
                Write-ToLogFile -StringObject "$(Get-TimeStamp) ExchangeOnlineManagement imported" -LogDirectory $LogDirectory

                Connect-ExchangeOnline -ErrorAction Stop
                Write-Verbose "Successfully connected to Exchange Online"
                Write-ToLogFile -StringObject "$(Get-TimeStamp) Successfully connected to Exchange Online" -LogDirectory $LogDirectory
            }
            catch {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Failed to connect to Exchange Online: $($_.Exception.Message)" -LogDirectory $LogDirectory
                Write-Host "ERROR: Could not connect to Exchange Online." -ForegroundColor Red
                Write-Host "  Action required: Ensure you have the ExchangeOnlineManagement module installed and that your account" -ForegroundColor Yellow
                Write-Host "  has the 'Compliance Administrator' or 'Global Administrator' role, then retry with -ConnectExchangeOnline." -ForegroundColor Yellow
                return
            }
        }

        # Validate that the required cmdlets are available
        Write-Verbose "Validating Exchange Online session..."
        if (-not (Get-Command -Name 'Search-UnifiedAuditLog' -ErrorAction SilentlyContinue)) {
            Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Search-UnifiedAuditLog cmdlet not found. No active Exchange Online session detected." -LogDirectory $LogDirectory
            Write-Host "ERROR: No active Exchange Online session was found." -ForegroundColor Red
            Write-Host "  Action required: Run 'Connect-ExchangeOnline' before calling this function, or re-run with the -ConnectExchangeOnline switch." -ForegroundColor Yellow
            return
        }

        Write-Verbose "Exchange Online session validated successfully"
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Exchange Online session validated" -LogDirectory $LogDirectory
    }

    process {
        $sessionId = [guid]::NewGuid().Guid
        $rawResults = [System.Collections.Generic.List[object]]::new()

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Beginning Unified Audit Log retrieval (SessionId: $sessionId)" -LogDirectory $LogDirectory
        Write-Verbose "Retrieving audit log entries — this may take several minutes for large date ranges"

        $pageNumber = 0

        # Retrieve the full dataset using session-based paging
        do {
            $pageNumber++
            Write-Progress `
                -Activity 'Get-PurviewPriorityPolicyAuditObjects' `
                -Status "Retrieving audit log records — page $pageNumber (total so far: $($rawResults.Count))" `
                -CurrentOperation "SessionId: $sessionId" `
                -PercentComplete -1

            try {
                $batch = Search-UnifiedAuditLog `
                    -StartDate $StartDate `
                    -EndDate $EndDate `
                    -SessionId $sessionId `
                    -SessionCommand ReturnLargeSet `
                    -ResultSize 5000 `
                    -HighCompleteness `
                    -Formatted `
                    -ErrorAction Stop

                if ($batch) {
                    $rawResults.AddRange($batch)
                    Write-Verbose "  Retrieved batch of $($batch.Count) record(s) — total so far: $($rawResults.Count)"
                }
            }
            catch {
                $errMsg = $_.Exception.Message

                # Detect broken/missing Exchange Online session — HttpResponseMessage.GetResponseHeader
                # is called internally by the EXO V3 module and throws this specific error when no
                # active session exists or the session token has expired.
                $isSessionError = $errMsg -match 'GetResponseHeader' -or
                                  $errMsg -match 'HttpResponseMessage' -or
                                  $errMsg -match 'not connected' -or
                                  $errMsg -match 'no active.*session' -or
                                  $errMsg -match 'Connect-ExchangeOnline'

                Write-Progress -Activity 'Get-PurviewPriorityPolicyAuditObjects' -Completed

                if ($isSessionError) {
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: No active Exchange Online session detected. Run Connect-ExchangeOnline first, or re-run with -ConnectExchangeOnline. Detail: $errMsg" -LogDirectory $LogDirectory -ForegroundColor Red
                    Write-Host ""
                    Write-Host "ERROR: No active Exchange Online session was found." -ForegroundColor Red
                    Write-Host "  Action required: Run 'Connect-ExchangeOnline' before calling this function," -ForegroundColor Yellow
                    Write-Host "  or re-run with the -ConnectExchangeOnline switch to connect automatically." -ForegroundColor Yellow
                }
                else {
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Search-UnifiedAuditLog failed: $errMsg" -LogDirectory $LogDirectory
                    Write-Host "ERROR: Audit log retrieval failed: $errMsg" -ForegroundColor Red
                }
                return
            }
        } while ($batch -and $batch.Count -gt 0)

        Write-Progress -Activity 'Get-PurviewPriorityPolicyAuditObjects' -Completed

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Audit log retrieval complete. Total records: $($rawResults.Count)" -LogDirectory $LogDirectory

        # Filter for priority cleanup-related events
        $priority = $rawResults | Where-Object { $_.AuditData -match 'prioritycleanup' }

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Priority cleanup records found: $($priority.Count)" -LogDirectory $LogDirectory
        Write-Verbose "Priority cleanup records found: $($priority.Count)"

        if ($priority.Count -eq 0) {
            Write-ToLogFile -StringObject "$(Get-TimeStamp) No priority cleanup audit events found in the specified date range." -LogDirectory $LogDirectory
            Write-Host "No priority cleanup audit events found in the specified date range." -ForegroundColor Yellow
            return
        }

        # Parse and normalise each record
        $parsed = foreach ($r in $priority) {
            $json = $null
            try {
                $json = $r.AuditData | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) WARNING: Could not parse AuditData JSON for record dated $($r.CreationDate): $($_.Exception.Message)" -LogDirectory $LogDirectory
            }

            $result = [pscustomobject]@{
                PSTypeName        = 'PurviewPriorityAuditResult'
                CreationTime      = $r.CreationDate
                Operation         = $r.Operations
                User              = $r.UserIds
                CompletionStatus  = if ($json -and $json.PSObject.Properties['ResultStatus'])         { $json.ResultStatus }
                                    elseif ($json -and $json.PSObject.Properties['CompletionStatus']) { $json.CompletionStatus }
                                    else { '' }
                RecordType        = if ($r.PSObject.Properties['RecordType'] -and $r.RecordType)     { $r.RecordType }
                                    elseif ($json -and $json.PSObject.Properties['RecordType'])       { $json.RecordType }
                                    else { '' }
                OrganizationId    = if ($json) { $json.OrganizationId } else { '' }
                Workload          = if ($r.Workload) { $r.Workload } elseif ($json -and $json.Workload) { $json.Workload } else { '' }
                ObjectId          = if ($json) { $json.ObjectId }       else { '' }
                ItemType          = if ($json) { $json.ItemType }        else { '' }
                Action            = if ($json) { $json.Operation }       else { '' }
                AuditEvent        = if ($json) { $json.AuditEvent }      else { '' }
                RawAuditData      = $json
            }

            Write-ToLogFile -StringObject "$(Get-TimeStamp) MATCH: User='$($result.User)' | Operation='$($result.Operation)' | Workload='$($result.Workload)' | ObjectId='$($result.ObjectId)'" -LogDirectory $LogDirectory
            $result
        }

        $sorted = @($parsed | Sort-Object CreationTime)

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Parsed and sorted $($sorted.Count) priority cleanup event(s)." -LogDirectory $LogDirectory

        # Optional CSV export
        if ($ExportResults -and $sorted.Count -gt 0) {
            $csvPath = Join-Path $LogDirectory "PurviewPriorityAudit_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            try {
                $sorted | Select-Object CreationTime, Operation, OrganizationId, User, Workload, ObjectId, ItemType, Action, AuditEvent |
                    Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                Write-ToLogFile -StringObject "$(Get-TimeStamp) CSV exported to: $csvPath" -LogDirectory $LogDirectory -ForegroundColor Green
                Write-Host "  CSV report : $csvPath" -ForegroundColor Green
            }
            catch {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Could not export CSV: $($_.Exception.Message)" -LogDirectory $LogDirectory
                Write-Host "ERROR: CSV export failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        # Optional detailed per-record console output
        if ($ShowDetails) {
            Write-Host ""
            Write-Host ("$(Get-TimeStamp) " + ("-" * 80)) -ForegroundColor DarkGray
            Write-Host "$(Get-TimeStamp) DETAILED OPERATION INFO ($($sorted.Count) event(s))" -ForegroundColor Yellow
            Write-Host ("$(Get-TimeStamp) " + ("-" * 80)) -ForegroundColor DarkGray

            $counter = 0
            foreach ($evt in $sorted) {
                $counter++
                Write-Host ""
                Write-Host "  [$counter / $($sorted.Count)] " + ("-" * 70) -ForegroundColor Yellow

                # Fixed summary fields
                Write-Host "  CreationTime   : $($evt.CreationTime)"   -ForegroundColor White
                Write-Host "  Operation      : $($evt.Operation)"      -ForegroundColor Cyan
                Write-Host "  User           : $($evt.User)"           -ForegroundColor Green
                Write-Host "  Workload       : $($evt.Workload)"       -ForegroundColor Green
                Write-Host "  OrganizationId : $($evt.OrganizationId)" -ForegroundColor Gray

                # All fields from the raw parsed AuditData JSON
                if ($evt.RawAuditData) {
                    Write-Host ""
                    Write-Host "  -- AuditData fields --" -ForegroundColor DarkYellow
                    foreach ($prop in ($evt.RawAuditData.PSObject.Properties | Sort-Object Name)) {
                        $val = $prop.Value
                        # Pretty-print nested objects/arrays as JSON
                        if ($null -ne $val -and ($val -is [System.Management.Automation.PSCustomObject] -or $val -is [System.Object[]])) {
                            $val = $val | ConvertTo-Json -Depth 5 -Compress
                        }
                        Write-Host ("  {0,-28}: {1}" -f $prop.Name, $val) -ForegroundColor Gray
                    }
                }

                Write-Host "  $("-" * 78)" -ForegroundColor DarkGray
            }
        }

        Write-Host ""
        Write-Host "Scan complete. Priority cleanup events found: $($sorted.Count)" -ForegroundColor Cyan
        Write-Host "Log file : $(Join-Path $LogDirectory 'Logging.txt')" -ForegroundColor Cyan

        $sorted | ForEach-Object { $_ }
    }

    end {
        # Disconnect if this function established the session
        if ($ConnectExchangeOnline) {
            try {
                Disconnect-ExchangeOnline -Confirm:$false -ErrorAction Stop
                Write-Verbose "Disconnected from Exchange Online"
                Write-ToLogFile -StringObject "$(Get-TimeStamp) Disconnected from Exchange Online" -LogDirectory $LogDirectory
            }
            catch {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) WARNING: Could not disconnect from Exchange Online: $($_.Exception.Message)" -LogDirectory $LogDirectory
            }
        }
    }
}
