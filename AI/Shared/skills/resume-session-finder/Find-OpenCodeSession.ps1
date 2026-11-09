<#
.SYNOPSIS
    Searches local OpenCode V2 session content without printing transcripts.
.DESCRIPTION
    Uses the local managed OpenCode service and its authenticated API discovery.
    All keywords must occur within one session. The current session is excluded.
.PARAMETER Keywords
    Literal, case-insensitive search terms.
.PARAMETER OpenCodePath
    Optional path to an OpenCode V2 executable.
.EXAMPLE
    ./Find-OpenCodeSession.ps1 -Keywords 'payment', 'configuration'
.OUTPUTS
    System.Management.Automation.PSCustomObject
.NOTES
    The local managed service must already be running. No session is modified.
#>
[CmdletBinding()]
param(
    [string[]]$Keywords,
    [string]$OpenCodePath
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Invoke-OpenCodeApiCommand {
    param([string]$Path, [string]$OutputPath)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.UseShellExecute = $false
    $startInfo.FileName = '/bin/sh'
    foreach ($argument in @('-c', 'exec "$1" api get "$2" > "$3"', 'opencode-api', $executable, $Path, $OutputPath)) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "OpenCode API request failed with exit code $($process.ExitCode)."
        }
    } finally {
        $process.Dispose()
    }
}

function Invoke-OpenCodeApi {
    param([string]$Path)

    if ($IsWindows) {
        & $executable api get $Path | ConvertFrom-Json
        return
    }

    $temporaryDirectory = [System.IO.Directory]::CreateTempSubdirectory('opencode-session-finder-')
    $outputPath = Join-Path $temporaryDirectory.FullName 'response.json'
    try {
        Invoke-OpenCodeApiCommand -Path $Path -OutputPath $outputPath
        [System.IO.File]::ReadAllText($outputPath) | ConvertFrom-Json
    } finally {
        [System.IO.File]::Delete($outputPath)
        $temporaryDirectory.Delete()
    }
}

function Get-SessionPage {
    param([string]$Path, [string]$NextPath)

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    while ($true) {
        $page = Invoke-OpenCodeApi $Path
        if ($null -eq $page -or $null -eq $page.PSObject.Properties['data'] -or $null -eq $page.cursor) {
            throw 'OpenCode returned an invalid paginated response.'
        }
        foreach ($item in $page.data) { $item }
        $cursor = [string]$page.cursor.next
        if ([string]::IsNullOrWhiteSpace($cursor)) { break }
        if (-not $seen.Add($cursor)) { throw 'OpenCode returned a repeated pagination cursor.' }
        $Path = $NextPath + [uri]::EscapeDataString($cursor)
    }
}

function Get-TextValue {
    param($Value)

    if ($null -eq $Value) { return }
    if ($Value -is [string]) { $Value; return }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($entry in $Value.Values) { Get-TextValue $entry }
        return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($entry in $Value) { Get-TextValue $entry }
        return
    }
    if ($Value -is [PSCustomObject]) {
        foreach ($property in $Value.PSObject.Properties) { Get-TextValue $property.Value }
    }
}

function Get-MessageSearchText {
    param($Message)

    switch ($Message.type) {
        'user' { [PSCustomObject]@{ Source = 'User'; Text = $Message.text } }
        'assistant' {
            foreach ($part in $Message.content) {
                switch ($part.type) {
                    'text' { [PSCustomObject]@{ Source = 'Assistant'; Text = $part.text } }
                    'tool' {
                        $toolText = @(Get-TextValue $part.state.input)
                        foreach ($output in $part.state.content) {
                            if ($output.type -eq 'text') { $toolText += $output.text }
                            if ($output.type -eq 'file') { $toolText += @($output.name, $output.uri) }
                        }
                        $toolText += @($part.state.error.message, $part.state.error.response.body)
                        foreach ($text in $toolText) {
                            [PSCustomObject]@{ Source = 'Tool'; Text = $text }
                        }
                    }
                }
            }
        }
        'shell' {
            foreach ($text in @($Message.command, $Message.output.output)) {
                [PSCustomObject]@{ Source = 'Shell'; Text = $text }
            }
        }
    }
}

function Find-OpenCodeSessions {
    <#
    .SYNOPSIS
        Finds sessions containing every literal keyword.
    .DESCRIPTION
        Searches paginated titles, user and assistant messages, tool data and shell output.
    .PARAMETER Keywords
        Literal, case-insensitive terms that must all occur in the same session.
    .PARAMETER ExcludeSessionId
        Session to exclude, normally the session running the search.
    .EXAMPLE
        Find-OpenCodeSessions -Keywords @('payment')
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Results never include matching transcript text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Keywords,
        [string]$ExcludeSessionId
    )

    if (@($Keywords | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw 'Search keywords must not be empty.'
    }
    $results = [System.Collections.Generic.List[object]]::new()
    foreach ($archived in @('false', 'true')) {
        $firstPath = "/api/session?limit=100&order=desc&archived=$archived"
        $nextPath = "/api/session?limit=100&archived=$archived&cursor="
        $sessions = @(Get-SessionPage -Path $firstPath -NextPath $nextPath)
        foreach ($session in $sessions) {
            if ($session.id -eq $ExcludeSessionId) { continue }
            $matched = [System.Collections.Generic.HashSet[int]]::new()
            $sources = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            $id = [uri]::EscapeDataString([string]$session.id)
            $title = [string]$session.title
            $missingFromTitle = @($Keywords | Where-Object { $title.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -lt 0 })
            & {
                [PSCustomObject]@{ Source = 'Title'; Text = $title }
                if ($missingFromTitle.Count -gt 0) {
                    Get-SessionPage -Path "/api/session/$id/message?limit=100&order=asc" -NextPath "/api/session/$id/message?limit=100&cursor=" |
                        ForEach-Object { Get-MessageSearchText $_ }
                }
            } | ForEach-Object {
                $text = $_
                if ($null -eq $text.Text) { return }
                for ($index = 0; $index -lt $Keywords.Count; $index++) {
                    if (([string]$text.Text).IndexOf($Keywords[$index], [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        [void]$matched.Add($index)
                        [void]$sources.Add($text.Source)
                    }
                }
            }
            if ($matched.Count -eq $Keywords.Count) {
                $results.Add([PSCustomObject]@{
                    SessionId = $session.id
                    ParentId = $session.parentID
                    Archived = $null -ne $session.time.archived
                    Directory = $session.location.directory
                    Created = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$session.time.created)
                    Updated = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$session.time.updated)
                    MatchedSources = @($sources | Sort-Object)
                })
            }
        }
    }
    $results | Sort-Object Updated -Descending
}

function Resolve-OpenCodeV2 {
    param([string]$Path)

    $candidates = if ($Path) { @($Path) } else {
        @(
            Get-Command opencode2 -All -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
            Get-Command opencode -All -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
        )
    }
    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        try {
            $version = & $candidate --version
            if (($version -join ' ') -match '(?i)^(opencode\s+v?)?2\.\d+\.\d+') { return (Resolve-Path -LiteralPath $candidate).Path }
        } catch { continue }
    }
    throw 'OpenCode V2 was not found. Specify its executable with -OpenCodePath.'
}

function Assert-LoopbackServiceUrl {
    param([string]$ServiceUrl)

    $serviceUri = $null
    if (-not [uri]::TryCreate($ServiceUrl, [UriKind]::Absolute, [ref]$serviceUri) -or
        $serviceUri.Scheme -notin @('http', 'https') -or
        $serviceUri.Host -notin @('localhost', '127.0.0.1', '[::1]', '::1') -or
        -not [string]::IsNullOrEmpty($serviceUri.UserInfo)) {
        throw 'The managed OpenCode service is not running on a verified local loopback address.'
    }
}

function Assert-OpenCodeServiceIdentity {
    param($Info, [string]$ServiceUrl, [string]$ProcessName)

    if ($Info.version -notmatch '^2\.' -or $ProcessName -notmatch '^opencode(?:[-.]|$)' -or $ServiceUrl -notin @($Info.urls)) {
        throw 'The discovered service is not a local OpenCode V2 process.'
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $Keywords -or @($Keywords | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { throw 'Supply non-empty -Keywords.' }
    $executable = Resolve-OpenCodeV2 -Path $OpenCodePath
    $service = (& $executable service status | Select-Object -First 1).Trim()
    Assert-LoopbackServiceUrl $service
    $info = Invoke-OpenCodeApi '/api/info'
    $serverProcess = Get-Process -Id $info.pid -ErrorAction Stop
    Assert-OpenCodeServiceIdentity -Info $info -ServiceUrl $service -ProcessName $serverProcess.ProcessName
    if ($env:OPENCODE_SESSION_ID) {
        $current = Invoke-OpenCodeApi ("/api/session/" + [uri]::EscapeDataString($env:OPENCODE_SESSION_ID))
        if ($current.data.id -ne $env:OPENCODE_SESSION_ID) { throw 'The current session is not available on the local managed service.' }
    }
    Find-OpenCodeSessions -Keywords $Keywords -ExcludeSessionId $env:OPENCODE_SESSION_ID
}
