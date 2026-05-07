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

        .PARAMETER UserPrincipalName
            The UPN (e.g. user@contoso.com) to pass to Connect-ExchangeOnline and Connect-IPPSSession.
            When provided, both connections use the supplied UPN for silent/certificate-based or
            pre-authenticated flows, avoiding a second interactive logon prompt.
            Only used when -ConnectExchangeOnline is also specified.

        .PARAMETER DisableBanner
            When specified together with -ConnectExchangeOnline, passes -ShowBanner:$false to
            Connect-ExchangeOnline to suppress the connection banner. Has no effect if
            -ConnectExchangeOnline is not also specified.

        .PARAMETER ShowDetails
            When specified, writes a full per-record detail block to the console for every matched event,
            showing all parsed fields: CreationTime, Operation, OrganizationId, User, Workload, ObjectId,
            ItemType, Action, and AuditEvent. Objects are still emitted to the pipeline regardless.

        .PARAMETER DumpErrors
            When specified, writes all error events (CompletionStatus = 'Error') and any runtime
            exceptions to a separate timestamped Errors_<stamp>.log file inside -LogDirectory.
            Normal run information goes to Logging_<stamp>.txt. Has no effect when there are no errors.

        .PARAMETER LogDirectory
            Directory for log files (Logging_<stamp>.txt, Errors_<stamp>.log, AuditResultObjects_<stamp>.log).
            Each run creates new timestamped files so prior runs are preserved.
            Defaults to a 'PurviewPriorityAudit' subfolder inside $env:TEMP.

        .EXAMPLE
            Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline

            Connects to Exchange Online and retrieves all priority cleanup audit events from the last 7 days.

        .EXAMPLE
            Get-PurviewPriorityPolicyAuditObjects -StartDate (Get-Date).AddDays(-30) -EndDate (Get-Date) -ShowDetails

            Searches the last 30 days and displays detailed per-record output.

        .EXAMPLE
            $results = Get-PurviewPriorityPolicyAuditObjects -ConnectExchangeOnline -ShowDetails -DumpErrors
            $results | Format-Table CreationTime, Operation, User, Workload, ObjectId -AutoSize

        .OUTPUTS
            PurviewPriorityAuditResult — one object per matched audit event with properties:
                CreationTime, Operation, CompletionStatus, RecordType, OrganizationId, User, Workload,
                ObjectId, ItemType, Action, AuditEvent, Parameters, NonPIIParameters, ExtendedProperties,
                RawAuditDataJson

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
        [string]$UserPrincipalName,

        [Parameter()]
        [switch]$DisableBanner,

        [Parameter()]
        [switch]$ShowDetails,

        [Parameter()]
        [switch]$DumpErrors,

        [Parameter()]
        [switch]$StayConnected,

        [Parameter()]
        [string]$LogDirectory = (Join-Path $env:TEMP 'PurviewPriorityAudit')
    )

    begin {
        $script:_abortRun = $false

        # Unique run stamp — all log files for this invocation share the same stamp so
        # prior runs are never overwritten.
        $script:_runStamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
        $script:_logFile   = Join-Path $LogDirectory "Logging_$($script:_runStamp).txt"
        $script:_errFile   = Join-Path $LogDirectory "Errors_$($script:_runStamp).log"
        $script:_auditFile = Join-Path $LogDirectory "AuditResultObjects_$($script:_runStamp).log"

        # Internal helper — appends to the timestamped Errors log (only when -DumpErrors is set)
        function Write-ToErrorLog {
            param([string]$Message)
            if (-not $DumpErrors) { return }
            try {
                Out-File -FilePath $script:_errFile -InputObject $Message -Encoding utf8 -Append -ErrorAction Stop
            }
            catch {
                Write-Host "$(Get-TimeStamp) WARNING: Could not write to Errors log: $_" -ForegroundColor DarkYellow
            }
        }

        # Shadow the module-level Write-ToLogFile so every call in this function writes to
        # the run-scoped timestamped log file without changing any call sites.
        function Write-ToLogFile {
            param(
                [Parameter(Mandatory = $true, Position = 0)]
                [string]$StringObject,
                [string]$LogDirectory = '.\Logs',
                [System.ConsoleColor]$ForegroundColor
            )
            try {
                if ($PSBoundParameters.ContainsKey('ForegroundColor')) {
                    Write-Host $StringObject -ForegroundColor $ForegroundColor
                }
                else {
                    Write-Host $StringObject
                }
                Out-File -FilePath $script:_logFile -InputObject $StringObject -Encoding utf8 -Append -ErrorAction Stop
            }
            catch {
                Write-Host "$(Get-TimeStamp) WARNING: Could not write to log: $_" -ForegroundColor DarkYellow
            }
        }

        # Helper — writes each $result object to the per-run AuditResultObjects log (active when -ShowDetails)
        function Write-ToAuditLog {
            param([string]$Message)
            try {
                Out-File -FilePath $script:_auditFile -InputObject $Message -Encoding utf8 -Append -ErrorAction Stop
            }
            catch {
                Write-Host "$(Get-TimeStamp) WARNING: Could not write to AuditResultObjects log: $_" -ForegroundColor DarkYellow
            }
        }

        # Helper — after " -" splitting, expands any param value that starts with { as pretty-printed JSON
        # Each JSON line is indented by $Indent under the -ParamName: label
        function Expand-EmbeddedParamJson {
            param([string]$ParamStr, [string]$Indent = '    ')
            if (-not $ParamStr) { return $ParamStr }
            $lines = $ParamStr -split "`n"
            $out = [System.Collections.Generic.List[string]]::new()
            foreach ($line in $lines) {
                # Match lines like:  -ParamName "{JSON...}" (value starts with {)
                if ($line -match '^(\s*-\w+)\s+"(\{.+)') {
                    $paramPart = $Matches[1]
                    $jsonPart  = $Matches[2]
                    if ($jsonPart.EndsWith('"')) { $jsonPart = $jsonPart.Substring(0, $jsonPart.Length - 1) }
                    $parsed = $null
                    try { $parsed = $jsonPart | ConvertFrom-Json -Depth 10 -ErrorAction Stop } catch {}
                    # Always put the value on its own indented line — even if JSON is truncated/unparseable
                    $out.Add("${paramPart}:")
                    if ($parsed) {
                        foreach ($jl in (($parsed | ConvertTo-Json -Depth 10) -split "`n")) {
                            $out.Add("$Indent$($jl.TrimEnd())")
                        }
                    } else {
                        # Truncated/unparseable — depth-tracking character scan:
                        # insert newlines at commas that are at property/element depth (≤3)
                        # so each stage object and each property within it gets its own line,
                        # but commas inside nested arrays (depth 4+) are left intact.
                        $jChars = $jsonPart.ToCharArray()
                        $jSb    = [System.Text.StringBuilder]::new()
                        $jDepth = 0; $jInStr = $false; $jEsc = $false
                        foreach ($jc in $jChars) {
                            if ($jEsc)                    { $null = $jSb.Append($jc); $jEsc = $false; continue }
                            if ($jc -eq '\' -and $jInStr) { $null = $jSb.Append($jc); $jEsc = $true;  continue }
                            if ($jc -eq '"')              { $jInStr = -not $jInStr;   $null = $jSb.Append($jc); continue }
                            if ($jInStr)                  { $null = $jSb.Append($jc); continue }
                            if ($jc -in '{','[')          { $jDepth++ }
                            elseif ($jc -in '}',']')      { $jDepth-- }
                            if ($jc -eq ',' -and $jDepth -le 3) {
                                $null = $jSb.Append($jc)
                                $null = $jSb.AppendLine()
                                continue
                            }
                            $null = $jSb.Append($jc)
                        }
                        foreach ($jl in ($jSb.ToString() -split "`r?`n")) {
                            if ($jl.Trim() -ne '') { $out.Add("$Indent$($jl.TrimEnd())") }
                        }
                    }
                    continue
                }
                $out.Add($line)
            }
            return $out -join "`n"
        }

        # Internal helper — inspects a failed audit event and returns a human-readable diagnosis
        function Get-ErrorDiagnosis {
            param($Event)
            $diagnoses = [System.Collections.Generic.List[string]]::new()
            $rawParams = ''
            if ($Event.RawAuditDataJson) {
                try {
                    $evtParsed = $Event.RawAuditDataJson | ConvertFrom-Json -ErrorAction Stop
                    if ($evtParsed.PSObject.Properties['Parameters']) { $rawParams = [string]$evtParsed.Parameters }
                } catch {}
            }

            # Extract individual named parameter values from the Parameters string
            $retDuration        = if ($rawParams -match '-RetentionDuration\s+"([^"]+)"')        { $Matches[1] } else { $null }
            $retType            = if ($rawParams -match '-RetentionType\s+"([^"]+)"')            { $Matches[1] } else { $null }
            $retAction          = if ($rawParams -match '-RetentionAction\s+"([^"]+)"')          { $Matches[1] } else { $null }
            $retComplianceAction= if ($rawParams -match '-RetentionComplianceAction\s+"([^"]+)"'){ $Matches[1] } else { $null }
            $expirationDateOpt  = if ($rawParams -match '-ExpirationDateOption\s+"([^"]+)"')     { $Matches[1] } else { $null }
            $pCleanup           = if ($rawParams -match '-PriorityCleanup\s+"([^"]+)"')          { $Matches[1] } else { $null }

            switch ($Event.Operation) {
                'New-ComplianceTag' {
                    # RetentionDuration: positive integer or 'unlimited'
                    # https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-compliancetag
                    if ($null -ne $retDuration) {
                        $durInt = 0
                        if ([int]::TryParse($retDuration, [ref]$durInt) -and $durInt -lt 0) {
                            $diagnoses.Add("RetentionDuration '$retDuration' is invalid. Valid values are a positive integer (number of days) or 'unlimited'.")
                        }
                    }
                    # RetentionAction: Delete, Keep, KeepAndDelete
                    if ($null -ne $retAction -and $retAction -notin @('Delete', 'Keep', 'KeepAndDelete')) {
                        $diagnoses.Add("RetentionAction '$retAction' is invalid. Valid values: Delete, Keep, KeepAndDelete.")
                    }
                    # RetentionType: CreationAgeInDays, EventAgeInDays, ModificationAgeInDays, TaggedAgeInDays
                    if ($null -ne $retType -and $retType -notin @('CreationAgeInDays', 'EventAgeInDays', 'ModificationAgeInDays', 'TaggedAgeInDays')) {
                        $diagnoses.Add("RetentionType '$retType' is invalid. Valid values: CreationAgeInDays, EventAgeInDays, ModificationAgeInDays, TaggedAgeInDays.")
                    }
                    # PriorityCleanup requires RetentionAction Delete
                    if ($pCleanup -eq 'True' -and $null -ne $retAction -and $retAction -ne 'Delete') {
                        $diagnoses.Add("PriorityCleanup=True requires RetentionAction 'Delete'. Actual value: '$retAction'.")
                    }
                }
                'Set-ComplianceTag' {
                    # Set-ComplianceTag only accepts RetentionDuration (no RetentionAction / RetentionType)
                    # https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/set-compliancetag
                    if ($null -ne $retDuration) {
                        $durInt = 0
                        if ([int]::TryParse($retDuration, [ref]$durInt) -and $durInt -lt 0) {
                            $diagnoses.Add("RetentionDuration '$retDuration' is invalid. Valid values are a positive integer (number of days) or 'unlimited'.")
                        }
                    }
                }
                'New-RetentionComplianceRule' {
                    # https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-retentioncompliancerule
                    # RetentionDuration: positive integer or 'unlimited'
                    if ($null -ne $retDuration) {
                        $durInt = 0
                        if ([int]::TryParse($retDuration, [ref]$durInt) -and $durInt -lt 0) {
                            $diagnoses.Add("RetentionDuration '$retDuration' is invalid. Valid values are a positive integer (number of days) or 'unlimited'.")
                        }
                    }
                    # RetentionComplianceAction: Delete, Keep, KeepAndDelete
                    if ($null -ne $retComplianceAction -and $retComplianceAction -notin @('Delete', 'Keep', 'KeepAndDelete')) {
                        $diagnoses.Add("RetentionComplianceAction '$retComplianceAction' is invalid. Valid values: Delete, Keep, KeepAndDelete.")
                    }
                    # ExpirationDateOption: CreationAgeInDays, ModificationAgeInDays (only two valid values)
                    if ($null -ne $expirationDateOpt -and $expirationDateOpt -notin @('CreationAgeInDays', 'ModificationAgeInDays')) {
                        $diagnoses.Add("ExpirationDateOption '$expirationDateOpt' is invalid. Valid values: CreationAgeInDays, ModificationAgeInDays.")
                    }
                }
                { $_ -in 'New-RetentionCompliancePolicy', 'Set-RetentionCompliancePolicy' } {
                    # These cmdlets manage scopes/locations only — no RetentionDuration, RetentionAction, or RetentionType parameters.
                    # https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/new-retentioncompliancepolicy
                    # https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/set-retentioncompliancepolicy
                    # No parameter-level retention validation is possible from audit data for these operations.
                }
            }

            if ($diagnoses.Count -gt 0) {
                return 'LIKELY CAUSE: ' + ($diagnoses -join ' | ')
            }
            return 'LIKELY CAUSE: Unknown — Microsoft does not write exception detail to the UAL for this operation type. Re-run the cmdlet interactively to see the live exception.'
        }

        # Ensure log directory exists
        if (-not (Test-Path -Path $LogDirectory)) {
            New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
        }

        $separator = "$(Get-TimeStamp) " + ("-" * 80)
        Write-ToLogFile -StringObject $separator -LogDirectory $LogDirectory
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Starting Get-PurviewPriorityPolicyAuditObjects" -LogDirectory $LogDirectory
        Write-ToLogFile -StringObject "$(Get-TimeStamp) StartDate      : $StartDate" -LogDirectory $LogDirectory
        Write-ToLogFile -StringObject "$(Get-TimeStamp) EndDate        : $EndDate" -LogDirectory $LogDirectory
        Write-ToLogFile -StringObject "$(Get-TimeStamp) DumpErrors              : $DumpErrors" -LogDirectory $LogDirectory
        Write-ToLogFile -StringObject "$(Get-TimeStamp) DisableBanner           : $DisableBanner" -LogDirectory $LogDirectory
        Write-ToLogFile -StringObject "$(Get-TimeStamp) LogDirectory            : $LogDirectory" -LogDirectory $LogDirectory

        if ($DumpErrors) {
            Write-ToErrorLog ("$(Get-TimeStamp) " + ("-" * 80))
            Write-ToErrorLog "$(Get-TimeStamp) Errors log opened — Get-PurviewPriorityPolicyAuditObjects run started"
            Write-ToErrorLog "$(Get-TimeStamp) StartDate : $StartDate | EndDate : $EndDate"
            Write-ToErrorLog ("$(Get-TimeStamp) " + ("-" * 80))
            Write-ToLogFile -StringObject "$(Get-TimeStamp) Error log    : $($script:_errFile)" -LogDirectory $LogDirectory
        }

        # Optional auto-connect
        if ($ConnectExchangeOnline) {
            Write-Verbose "Auto-connecting to Exchange Online"
            Write-ToLogFile -StringObject "$(Get-TimeStamp) Checking for ExchangeOnlineManagement module" -LogDirectory $LogDirectory

            $requiredEXOVersion = [version]'3.9.2'

            try {
                $installedEXO = Get-Module -ListAvailable -Name ExchangeOnlineManagement |
                    Sort-Object Version -Descending | Select-Object -First 1

                if (-not $installedEXO) {
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) ExchangeOnlineManagement not found. Installing from PSGallery..." -LogDirectory $LogDirectory
                    Install-Module -Name ExchangeOnlineManagement -MinimumVersion $requiredEXOVersion -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) ExchangeOnlineManagement $requiredEXOVersion installed successfully" -LogDirectory $LogDirectory
                }
                elseif ($installedEXO.Version -lt $requiredEXOVersion) {
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) ExchangeOnlineManagement $($installedEXO.Version) is below minimum $requiredEXOVersion. Updating..." -LogDirectory $LogDirectory
                    Update-Module -Name ExchangeOnlineManagement -Force -ErrorAction Stop
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) ExchangeOnlineManagement updated to minimum $requiredEXOVersion" -LogDirectory $LogDirectory
                }
                else {
                    Write-ToLogFile -StringObject "$(Get-TimeStamp) ExchangeOnlineManagement $($installedEXO.Version) found (>= $requiredEXOVersion)" -LogDirectory $LogDirectory
                }

                Import-Module ExchangeOnlineManagement -MinimumVersion $requiredEXOVersion -ErrorAction Stop
                Write-ToLogFile -StringObject "$(Get-TimeStamp) ExchangeOnlineManagement imported" -LogDirectory $LogDirectory

                $connectParams = @{ ErrorAction = 'Stop' }
                if ($DisableBanner)        { $connectParams['ShowBanner']        = $false }
                if ($UserPrincipalName)    { $connectParams['UserPrincipalName'] = $UserPrincipalName }
                Connect-ExchangeOnline @connectParams
                Write-Verbose "Successfully connected to Exchange Online"
                Write-ToLogFile -StringObject "$(Get-TimeStamp) Successfully connected to Exchange Online" -LogDirectory $LogDirectory

                # Resolve UPN for IPPS: prefer the explicit parameter; fall back to what
                # Get-ConnectionInformation reports from the just-established EXO session so
                # Connect-IPPSSession can do a silent MSAL token acquisition — no second prompt.
                $resolvedUPN = if ($UserPrincipalName) {
                    $UserPrincipalName
                } else {
                    (Get-ConnectionInformation | Select-Object -First 1).UserPrincipalName
                }

                # Connect to Security & Compliance Center (required for Search-UnifiedAuditLog)
                Write-ToLogFile -StringObject "$(Get-TimeStamp) Connecting to Security and Compliance Center" -LogDirectory $LogDirectory
                $ippsParams = @{ ErrorAction = 'Stop' }
                if ($DisableBanner)  { $ippsParams['ShowBanner']        = $false }
                if ($resolvedUPN)    { $ippsParams['UserPrincipalName'] = $resolvedUPN }
                Connect-IPPSSession @ippsParams
                Write-Verbose "Successfully connected to Security and Compliance Center"
                Write-ToLogFile -StringObject "$(Get-TimeStamp) Successfully connected to Security and Compliance Center" -LogDirectory $LogDirectory
            }
            catch {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Failed to connect: $($_.Exception.Message)" -LogDirectory $LogDirectory
                Write-Host "ERROR: Could not connect to Exchange Online or Security and Compliance Center." -ForegroundColor Red
                Write-Host "  Action required: Ensure you have the ExchangeOnlineManagement module installed and that your account" -ForegroundColor Yellow
                Write-Host "  has the 'Compliance Administrator' or 'Global Administrator' role, then retry with -ConnectExchangeOnline." -ForegroundColor Yellow
                $script:_abortRun = $true
                return
            }
        }

        # Validate that the required cmdlets are available
        Write-Verbose "Validating Exchange Online and Security & Compliance session..."
        if (-not (Get-Command -Name 'Search-UnifiedAuditLog' -ErrorAction SilentlyContinue)) {
            Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR: Search-UnifiedAuditLog cmdlet not found. No active Exchange Online / Security and Compliance session detected." -LogDirectory $LogDirectory
            Write-Host "ERROR: No active Exchange Online or Security and Compliance session was found." -ForegroundColor Red
            Write-Host "  Action required: Run 'Connect-ExchangeOnline' and 'Connect-IPPSSession' before calling this function, or re-run with the -ConnectExchangeOnline switch." -ForegroundColor Yellow
            $script:_abortRun = $true
            return
        }

        Write-Verbose "Exchange Online and Security and Compliance session validated successfully"
        Write-ToLogFile -StringObject "$(Get-TimeStamp) Exchange Online and Security and Compliance session validated" -LogDirectory $LogDirectory
    }

    process {
        if ($script:_abortRun) { return }

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
                    -FreeText 'priority cleanup' `
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
                    $logMsg = "$(Get-TimeStamp) ERROR: No active Exchange Online session detected. Run Connect-ExchangeOnline first, or re-run with -ConnectExchangeOnline. Detail: $errMsg"
                    Write-ToLogFile -StringObject $logMsg -LogDirectory $LogDirectory -ForegroundColor Red
                    Write-ToErrorLog $logMsg
                    Write-Host ""
                    Write-Host "ERROR: No active Exchange Online session was found." -ForegroundColor Red
                    Write-Host "  Action required: Run 'Connect-ExchangeOnline' before calling this function," -ForegroundColor Yellow
                    Write-Host "  or re-run with the -ConnectExchangeOnline switch to connect automatically." -ForegroundColor Yellow
                }
                else {
                    $logMsg = "$(Get-TimeStamp) ERROR: Search-UnifiedAuditLog failed: $errMsg"
                    Write-ToLogFile -StringObject $logMsg -LogDirectory $LogDirectory
                    Write-ToErrorLog $logMsg
                    Write-Host "ERROR: Audit log retrieval failed: $errMsg" -ForegroundColor Red
                }
                return
            }
        } while ($batch -and $batch.Count -gt 0)

        Write-Progress -Activity 'Get-PurviewPriorityPolicyAuditObjects' -Completed

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Audit log retrieval complete. Total records: $($rawResults.Count)" -LogDirectory $LogDirectory

        # Filter for priority cleanup-related events (server already pre-filtered via FreeText; this removes any false positives)
        $priority = $rawResults | Where-Object { $_.AuditData -match 'priority.?cleanup' }

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
                Parameters        = if ($json -and $json.PSObject.Properties['Parameters'] -and $json.Parameters) {
                                        if ($json.Parameters -is [string]) {
                                            Expand-EmbeddedParamJson ($json.Parameters -replace '" -', ('"' + "`n-"))
                                        } else {
                                            ($json.Parameters | ForEach-Object {
                                                $ev = if ($null -ne $_.Value) { [string]$_.Value } else { '' }
                                                if ($ev -match '^\s*-\w') {
                                                    "$($_.Name):`n" + ($ev -replace '" -', ('"' + "`n-"))
                                                } else { "$($_.Name): $ev" }
                                            }) -join "`n"
                                        }
                                    } else { '' }
                NonPIIParameters  = if ($json -and $json.PSObject.Properties['NonPIIParameters'] -and $json.NonPIIParameters) {
                                        if ($json.NonPIIParameters -is [string]) {
                                            Expand-EmbeddedParamJson ($json.NonPIIParameters -replace '" -', ('"' + "`n-"))
                                        } else {
                                            ($json.NonPIIParameters | ForEach-Object {
                                                $ev = if ($null -ne $_.Value) { [string]$_.Value } else { '' }
                                                if ($ev -match '^\s*-\w') {
                                                    "$($_.Name):`n" + ($ev -replace '" -', ('"' + "`n-"))
                                                } else { "$($_.Name): $ev" }
                                            }) -join "`n"
                                        }
                                    } else { '' }
                ExtendedProperties= if ($json -and $json.PSObject.Properties['ExtendedProperties'] -and $json.ExtendedProperties) {
                                        ($json.ExtendedProperties | ForEach-Object {
                                            $v = if ($_.Value -is [System.Management.Automation.PSCustomObject] -or $_.Value -is [System.Object[]]) {
                                                $_.Value | ConvertTo-Json -Depth 3 -Compress
                                            } else { $_.Value }
                                            "  $($_.Name): $v"
                                        }) -join "`n"
                                    } else { '' }
                RawAuditDataJson  = $r.AuditData
            }

            Write-ToLogFile -StringObject "$(Get-TimeStamp) MATCH: User='$($result.User)' | Operation='$($result.Operation)' | CompletionStatus='$($result.CompletionStatus)' | Workload='$($result.Workload)' | ObjectId='$($result.ObjectId)'" -LogDirectory $LogDirectory
            $result
        }

        $sorted = @($parsed | Sort-Object CreationTime)

        # Split into success and error buckets
        $errorEvents   = @($sorted | Where-Object { $_.CompletionStatus -eq 'Error' })
        $script:_errorEvents = $errorEvents   # make available to end{}
        $global:PurviewAuditErrors = $errorEvents   # expose for post-run inspection

        # Stamp a Diagnosis property on each error event now while Get-ErrorDiagnosis is in scope
        foreach ($evt in $errorEvents) {
            $evt | Add-Member -NotePropertyName 'Diagnosis' -NotePropertyValue (Get-ErrorDiagnosis -Event $evt) -Force
        }

        Write-ToLogFile -StringObject "$(Get-TimeStamp) Parsed and sorted $($sorted.Count) priority cleanup event(s). Errors: $($errorEvents.Count)" -LogDirectory $LogDirectory

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
                if ($evt.RawAuditDataJson) {
                    $showJson = $null
                    try { $showJson = $evt.RawAuditDataJson | ConvertFrom-Json -ErrorAction Stop } catch {}
                    if ($showJson) {
                        Write-Host ""
                        Write-Host "  -- AuditData fields --" -ForegroundColor DarkYellow
                        foreach ($prop in ($showJson.PSObject.Properties | Sort-Object Name)) {
                            $rawPropVal = $prop.Value

                            # ── Name/Value object arrays (ExtendedProperties, Parameters-as-array, etc.) ──
                            if ($rawPropVal -is [System.Object[]] -and $rawPropVal.Count -gt 0 -and
                                $rawPropVal[0] -is [System.Management.Automation.PSCustomObject] -and
                                $rawPropVal[0].PSObject.Properties['Name'] -and
                                $rawPropVal[0].PSObject.Properties['Value']) {
                                Write-Host ("  {0,-28}:" -f $prop.Name) -ForegroundColor DarkYellow
                                foreach ($entry in $rawPropVal) {
                                    $ev = if ($null -ne $entry.Value) { [string]$entry.Value } else { '' }
                                    if ($ev -match '^\s*-\w') {
                                        # Cmdlet-style string — split each parameter onto its own line
                                        $ev = $ev -replace '" -', ('"' + "`n-")
                                        Write-Host ("    {0,-24}:" -f $entry.Name) -ForegroundColor Cyan
                                        foreach ($ln in ($ev -split "`n")) {
                                            Write-Host "      $($ln.TrimEnd())" -ForegroundColor Gray
                                        }
                                    } else {
                                        Write-Host ("    {0,-24}: {1}" -f $entry.Name, $ev) -ForegroundColor Gray
                                    }
                                }
                                continue
                            }

                            $val = $rawPropVal
                            if ($null -ne $val -and ($val -is [System.Management.Automation.PSCustomObject] -or $val -is [System.Object[]])) {
                                $val = $val | ConvertTo-Json -Depth 5 -Compress
                            }
                            # Split parameter strings so each -Name "Value" pair is on its own line
                            if ($prop.Name -in 'Parameters', 'NonPIIParameters') {
                                $val = $val -replace '" -', ('"' + "`n-")
                                Write-Host ("  {0,-28}:" -f $prop.Name) -ForegroundColor DarkYellow
                                foreach ($line in ($val -split "`n")) {
                                    Write-Host "    $($line.TrimEnd())" -ForegroundColor Gray
                                }
                                continue
                            }
                            # Pretty-print any embedded JSON object value — each key on its own line
                            if ($val -is [string] -and $val.TrimStart().StartsWith('{')) {
                                $sfJson = $null
                                try { $sfJson = $val | ConvertFrom-Json -ErrorAction Stop } catch {}
                                if ($sfJson) {
                                    Write-Host ("  {0,-28}:" -f $prop.Name) -ForegroundColor DarkYellow
                                    foreach ($sfProp in $sfJson.PSObject.Properties) {
                                        $sfVal = $sfProp.Value
                                        if ($null -ne $sfVal -and ($sfVal -is [System.Management.Automation.PSCustomObject] -or $sfVal -is [System.Object[]])) {
                                            $sfVal = $sfVal | ConvertTo-Json -Depth 3 -Compress
                                        }
                                        Write-Host ("    {0,-30}: {1}" -f $sfProp.Name, $sfVal) -ForegroundColor Gray
                                    }
                                    continue
                                }
                            }
                            if ($prop.Name -in 'CompletionStatus', 'ResultStatus' -and [string]$val -eq 'Error') { $val = 'ERROR' }
                            Write-Host ("  {0,-28}: {1}" -f $prop.Name, $val) -ForegroundColor Gray
                        }
                    }
                }

                Write-Host "  $("-" * 78)" -ForegroundColor DarkGray

                # Write the complete result object to the per-run AuditResultObjects log
                $auditLines = [System.Text.StringBuilder]::new()
                $null = $auditLines.AppendLine("$(Get-TimeStamp) [$counter / $($sorted.Count)] ---- AUDIT RESULT ----")
                foreach ($p in $evt.PSObject.Properties) {
                    if ($p.Name -eq 'PSTypeName') { continue }
                    $pv = $p.Value
                    if ($null -eq $pv -or $pv -eq '') { continue }

                    # RawAuditDataJson: parse and write field-by-field so Parameters/NonPIIParameters
                    # inside the raw JSON get the same " -" splitting and embedded-JSON expansion
                    if ($p.Name -eq 'RawAuditDataJson') {
                        $null = $auditLines.AppendLine("  RawAuditDataJson:")
                        $rawParsed = $null
                        try { $rawParsed = $pv | ConvertFrom-Json -ErrorAction Stop } catch {}
                        if ($rawParsed) {
                            foreach ($rp in ($rawParsed.PSObject.Properties | Sort-Object Name)) {
                                $rv = $rp.Value
                                if ($null -eq $rv) { continue }
                                $rvStr = if ($rv -is [System.Management.Automation.PSCustomObject] -or
                                             ($rv -is [System.Collections.IEnumerable] -and $rv -isnot [string])) {
                                    $rv | ConvertTo-Json -Depth 10 -Compress
                                } else { [string]$rv }
                                if ($rp.Name -in 'Parameters', 'NonPIIParameters' -and $rvStr) {
                                    $rvStr = Expand-EmbeddedParamJson ($rvStr -replace '" -', ('"' + "`n-")) -Indent '  '
                                }
                                if ($rvStr -match "`n") {
                                    $null = $auditLines.AppendLine("    $($rp.Name):")
                                    foreach ($rvLine in ($rvStr -split "`n")) {
                                        $null = $auditLines.AppendLine("      $($rvLine.TrimEnd())")
                                    }
                                } else {
                                    $null = $auditLines.AppendLine("    $("{0,-30}: {1}" -f $rp.Name, $rvStr)")
                                }
                            }
                        } else {
                            # JSON parse failed — write raw line-by-line as fallback
                            foreach ($pvLine in (([string]$pv) -split "`n")) {
                                $null = $auditLines.AppendLine("    $($pvLine.TrimEnd())")
                            }
                        }
                        continue
                    }

                    $pvStr = [string]$pv
                    if ($pvStr -match "`n") {
                        $null = $auditLines.AppendLine("  $($p.Name):")
                        foreach ($pvLine in ($pvStr -split "`n")) {
                            $null = $auditLines.AppendLine("    $($pvLine.TrimEnd())")
                        }
                    } else {
                        $null = $auditLines.AppendLine("  $($p.Name): $pvStr")
                    }
                }
                $null = $auditLines.AppendLine("  $('-' * 78)")
                Write-ToAuditLog $auditLines.ToString()
            }
        }

        Write-Host ""
        Write-Host "Scan complete. Priority cleanup events found: $($sorted.Count)" -ForegroundColor Cyan

        # Write all error events silently to the Errors log — console output deferred to end{}
        if ($errorEvents.Count -gt 0) {
            Write-ToLogFile -StringObject "$(Get-TimeStamp) ERROR SUMMARY: $($errorEvents.Count) failed operation(s) — see $($script:_errFile) for details" -LogDirectory $LogDirectory

            $errCounter = 0
            foreach ($evt in $errorEvents) {
                $errCounter++
                Write-ToErrorLog ("$(Get-TimeStamp) " + ("-" * 78))
                Write-ToErrorLog "$(Get-TimeStamp) [$errCounter / $($errorEvents.Count)] FAILED OPERATION"
                Write-ToErrorLog "$(Get-TimeStamp)   CreationTime   : $($evt.CreationTime)"
                Write-ToErrorLog "$(Get-TimeStamp)   Operation      : $($evt.Operation)"
                Write-ToErrorLog "$(Get-TimeStamp)   User           : $($evt.User)"
                Write-ToErrorLog "$(Get-TimeStamp)   RecordType     : $($evt.RecordType)"
                Write-ToErrorLog "$(Get-TimeStamp)   OrganizationId : $($evt.OrganizationId)"
                Write-ToErrorLog "$(Get-TimeStamp)   ObjectId       : $($evt.ObjectId)"
                Write-ToErrorLog "$(Get-TimeStamp)   $($evt.Diagnosis)"

                if ($evt.RawAuditDataJson) {
                    $evtJson = $null
                    try { $evtJson = $evt.RawAuditDataJson | ConvertFrom-Json -ErrorAction Stop } catch {}
                    if ($evtJson) {
                        Write-ToErrorLog "$(Get-TimeStamp)   -- AuditData (all fields) --"
                        foreach ($prop in ($evtJson.PSObject.Properties | Sort-Object Name)) {
                            $rawPropVal = $prop.Value
                            if ($null -eq $rawPropVal) { continue }

                            # ── Name/Value object arrays (ExtendedProperties, Parameters-as-array, etc.) ──
                            if ($rawPropVal -is [System.Object[]] -and $rawPropVal.Count -gt 0 -and
                                $rawPropVal[0] -is [System.Management.Automation.PSCustomObject] -and
                                $rawPropVal[0].PSObject.Properties['Name'] -and
                                $rawPropVal[0].PSObject.Properties['Value']) {
                                Write-ToErrorLog ("$(Get-TimeStamp)   {0,-28}:" -f $prop.Name)
                                foreach ($entry in $rawPropVal) {
                                    $ev = if ($null -ne $entry.Value) { [string]$entry.Value } else { '' }
                                    if ($ev -match '^\s*-\w') {
                                        $ev = $ev -replace '" -', ('"' + "`n-")
                                        Write-ToErrorLog "$(Get-TimeStamp)     $($entry.Name):"
                                        foreach ($ln in ($ev -split "`n")) {
                                            Write-ToErrorLog "$(Get-TimeStamp)       $($ln.TrimEnd())"
                                        }
                                    } else {
                                        Write-ToErrorLog "$(Get-TimeStamp)     $("{0,-24}: {1}" -f $entry.Name, $ev)"
                                    }
                                }
                                continue
                            }

                            $val = $rawPropVal
                            if ($val -eq '') { continue }
                            if ($val -is [System.Management.Automation.PSCustomObject] -or
                                ($val -is [System.Collections.IEnumerable] -and $val -isnot [string])) {
                                $val = $val | ConvertTo-Json -Depth 20
                            }
                            else { $val = [string]$val }
                            # Split parameter strings so each -Name "Value" pair is on its own line;
                            # also expand any -ParamName "{JSON}" values into pretty-printed JSON
                            if ($prop.Name -in 'Parameters', 'NonPIIParameters') {
                                $val = Expand-EmbeddedParamJson ($val -replace '" -', ('"' + "`n-")) -Indent '    '
                            }
                            # Pretty-print any embedded JSON object value — each key on its own line
                            if ($val -is [string] -and $val.TrimStart().StartsWith('{')) {
                                $sfJson = $null
                                try { $sfJson = $val | ConvertFrom-Json -ErrorAction Stop } catch {}
                                if ($sfJson) {
                                    Write-ToErrorLog ("$(Get-TimeStamp)   {0,-28}:" -f $prop.Name)
                                    foreach ($sfProp in $sfJson.PSObject.Properties) {
                                        $sfVal = $sfProp.Value
                                        if ($null -ne $sfVal -and ($sfVal -is [System.Management.Automation.PSCustomObject] -or $sfVal -is [System.Object[]])) {
                                            $sfVal = $sfVal | ConvertTo-Json -Depth 3 -Compress
                                        }
                                        Write-ToErrorLog "$(Get-TimeStamp)     $("{0,-30}: {1}" -f $sfProp.Name, $sfVal)"
                                    }
                                    continue
                                }
                            }
                            if ($prop.Name -in 'CompletionStatus', 'ResultStatus' -and $val -eq 'Error') { $val = 'ERROR' }
                            if ($val -match "`n") {
                                Write-ToErrorLog ("$(Get-TimeStamp)   {0,-28}:" -f $prop.Name)
                                foreach ($line in ($val -split "`n")) {
                                    Write-ToErrorLog "$(Get-TimeStamp)     $($line.TrimEnd())"
                                }
                            } else {
                                Write-ToErrorLog ("$(Get-TimeStamp)   {0,-28}: {1}" -f $prop.Name, $val)
                            }
                        }
                    }
                }
            }
            Write-ToErrorLog ("$(Get-TimeStamp) " + ("-" * 78))
            Write-ToErrorLog "$(Get-TimeStamp) ERROR SUMMARY: $($errorEvents.Count) failed operation(s)"
        }

        Write-Host ""
        Write-Host "Log file   : $($script:_logFile)" -ForegroundColor Cyan
        if ($ShowDetails) {
            Write-Host "Audit log  : $($script:_auditFile)" -ForegroundColor Cyan
        }
        if ($DumpErrors) {
            Write-Host "Error log  : $($script:_errFile)" -ForegroundColor Cyan
        }

        $sorted | ForEach-Object { $_ }
    }

    end {
        # Disconnect if this function established the session.
        # Disconnect-ExchangeOnline handles both the EXO and IPPS (SCC) sessions established
        # by Connect-ExchangeOnline and Connect-IPPSSession respectively.
        if ($ConnectExchangeOnline -and -not $StayConnected) {
            try {
                Disconnect-ExchangeOnline -Confirm:$false -ErrorAction Stop
                Write-Verbose "Disconnected from Exchange Online and Security and Compliance Center"
                Write-ToLogFile -StringObject "$(Get-TimeStamp) Disconnected from Exchange Online and Security and Compliance Center" -LogDirectory $LogDirectory
            }
            catch {
                Write-ToLogFile -StringObject "$(Get-TimeStamp) WARNING: Could not disconnect: $($_.Exception.Message)" -LogDirectory $LogDirectory
            }
        }

        # Print error summary after disconnect — show table + log path
        $errorEvents = $script:_errorEvents
        if ($null -ne $errorEvents -and $errorEvents.Count -gt 0) {
            Write-Host ""
            Write-Host "$(Get-TimeStamp) WARNING: $($errorEvents.Count) failed operation(s) were found:" -ForegroundColor Yellow
            Write-Host ""
            $errorEvents | Format-Table CreationTime, Operation, User, CompletionStatus, RecordType, OrganizationId, ObjectId -AutoSize | Out-Host

            # Print per-error diagnosis
            $diagCounter = 0
            foreach ($evt in $errorEvents) {
                $diagCounter++
                Write-Host "  [$diagCounter] $($evt.CreationTime) | $($evt.Operation)" -ForegroundColor DarkGray
                Write-Host "      $($evt.Diagnosis)" -ForegroundColor Yellow
            }
            Write-Host ""
            if ($DumpErrors) {
                Write-Host "$(Get-TimeStamp) Full error details written to: $($script:_errFile)" -ForegroundColor Yellow
            }
            else {
                Write-Host "$(Get-TimeStamp) Re-run with -DumpErrors to capture full error details to a timestamped Errors_<stamp>.log in: $LogDirectory" -ForegroundColor Yellow
            }
        }
    }
}
