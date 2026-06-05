---
applyTo: '**/*.ps1,**/*.psm1'
description: 'PowerShell cmdlet and scripting best practices based on Microsoft guidelines'
---

# PowerShell Cmdlet Development Guidelines

## Naming Conventions

- **Verb-Noun Format:**
  - Use approved PowerShell verbs (Get-Verb)
  - Use singular nouns
  - PascalCase for both verb and noun
  - Avoid special characters and spaces

- **Parameter Names:**
  - Use PascalCase
  - Choose clear, descriptive names
  - Use singular form unless always multiple
  - Follow PowerShell standard names

- **Variable Names:**
  - Use PascalCase for public variables
  - Use camelCase for private variables
  - Avoid abbreviations
  - Use meaningful names

- **Alias Avoidance:**
  - Use full cmdlet names
  - Avoid using aliases in scripts (e.g., use Get-ChildItem instead of gci)
  - Document any custom aliases
  - Use full parameter names

### Example

```powershell
function Get-UserProfile {
    param([Parameter(Mandatory)] [string]$Username)
    # Logic
}
```

## Parameter Design

- **Standard Parameters:**
  - Use common parameter names (`Path`, `Name`, `Force`)
  - Follow built-in cmdlet conventions
  - Use [Alias()] attributes on parameters only when a well-known domain-specific name exists (e.g., `[Alias('ComputerName')]`). Never use cmdlet aliases in script bodies.
  - Document parameter purpose

- **Parameter Names:**
  - Use singular form unless always multiple
  - Choose clear, descriptive names
  - Follow PowerShell conventions
  - Use PascalCase formatting

- **Type Selection:**
  - Use common .NET types
  - Implement proper validation
  - Consider ValidateSet for limited options
  - Enable tab completion where possible

- **Switch Parameters:**
  - Use [switch] for boolean flags
  - Avoid $true/$false parameters
  - Default to $false when omitted
  - Use clear action names

### Example

```powershell
function Set-ResourceConfiguration {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [ValidateSet('Dev', 'Prod')] [string]$Env = 'Dev',
        [switch]$Force
    )
    # Logic
}
```

## Pipeline and Output

- **Pipeline Input:**
  - Use `ValueFromPipeline` for direct object input
  - Use `ValueFromPipelineByPropertyName` for property mapping
  - Implement Begin/Process/End blocks for pipeline handling
  - Document pipeline input requirements

- **Output Objects:**
  - Return rich objects, not formatted text
  - Use PSCustomObject for structured data
  - Avoid Write-Host for data output
  - Enable downstream cmdlet processing

- **Pipeline Streaming:**
  - Output one object at a time
  - Use process block for streaming
  - Avoid collecting large arrays
  - Enable immediate processing

- **PassThru Pattern:**
  - Default to no output for action cmdlets
  - Implement `-PassThru` switch for object return
  - Return modified/created object with `-PassThru`
  - Use verbose/warning for status updates

### Example

```powershell
function Update-ResourceStatus {
    param([Parameter(Mandatory, ValueFromPipeline)] [string]$Name, [string]$Status)
    begin { $timestamp = Get-Date }
    process {
        $resource = [PSCustomObject]@{ Name = $Name; Status = $Status; Updated = $timestamp }
        Write-Output $resource
    }
    end { }
}
```

## Error Handling and Safety

- **ShouldProcess Implementation:**
  - Use `[CmdletBinding(SupportsShouldProcess = $true)]`
  - Set appropriate `ConfirmImpact` level
  - Call `$PSCmdlet.ShouldProcess()` for system changes
  - Use `ShouldContinue()` for additional confirmations

- **Message Streams:**
  - `Write-Verbose` for operational details with `-Verbose`
  - `Write-Warning` for warning conditions
  - `Write-Error` for non-terminating errors
  - `throw` for terminating errors
  - Avoid `Write-Host` except for user interface text

- **Error Handling Pattern:**
  - Use try/catch blocks for error management
  - Set appropriate ErrorAction preferences
  - Return meaningful error messages
  - Use ErrorVariable when needed
  - Include proper terminating vs non-terminating error handling
  - In advanced functions with `[CmdletBinding()]`, prefer `$PSCmdlet.WriteError()` over `Write-Error`
  - In advanced functions with `[CmdletBinding()]`, prefer `$PSCmdlet.ThrowTerminatingError()` over `throw`
  - Construct proper ErrorRecord objects with category, target, and exception details

- **Non-Interactive Design:**
  - Accept input via parameters
  - Avoid `Read-Host` in scripts
  - Support automation scenarios
  - Document all required inputs

### Example

```powershell
function Remove-UserAccount {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)] [string]$Username, [switch]$Force)
    process {
        try {
            if ($Force -or $PSCmdlet.ShouldProcess($Username, 'Remove account')) {
                Remove-ADUser -Identity $Username -ErrorAction Stop
            }
        } catch {
            $err = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception, 'RemovalFailed', 'NotSpecified', $Username
            )
            $PSCmdlet.ThrowTerminatingError($err)
        }
    }
}
```

## Documentation and Style

- **Comment-Based Help:** Include comment-based help for any public-facing function or cmdlet. Inside the function, add a `<# ... #>` help comment with at least:
  - `.SYNOPSIS` Brief description
  - `.DESCRIPTION` Detailed explanation
  - `.EXAMPLE` sections with practical usage
  - `.PARAMETER` descriptions
  - `.OUTPUTS` Type of output returned
  - `.NOTES` Additional information

- **Consistent Formatting:**
  - Follow consistent PowerShell style
  - Use proper indentation (4 spaces recommended)
  - Opening braces on same line as statement
  - Closing braces on new line
  - Use line breaks after pipeline operators
  - PascalCase for function and parameter names
  - Avoid unnecessary whitespace
  - Always add a newline at the end of the file.

- **Pipeline Support:**
  - Implement Begin/Process/End blocks for pipeline functions
  - Use ValueFromPipeline where appropriate
  - Support pipeline input by property name
  - Return proper objects, not formatted text

- **Avoid Aliases:** Use full cmdlet names and parameters
  - Avoid using aliases in scripts (e.g., use Get-ChildItem instead of gci); aliases are acceptable for interactive shell use.
  - Use `Where-Object` instead of `?` or `where`
  - Use `ForEach-Object` instead of `%`
  - Use `Get-ChildItem` instead of `ls` or `dir`

## Others

- Use English for all names and comments.
- Use GitHub CLI for GitHub resources; retrieve token via `gh auth token`.
- Set `$ErrorActionPreference = "Stop"` at script start.
- If the script invokes any external executables (non-PowerShell binaries, e.g. git, curl, dotnet): set `$PSNativeCommandUseErrorActionPreference = $true` immediately after `$ErrorActionPreference = "Stop"`.
- **Never use `Set-StrictMode -Version Latest` in scripts that process JSON API responses or external data.** It throws `PropertyNotFoundException` when accessing absent properties on `PSCustomObject` — which is common with optional JSON fields. `$ErrorActionPreference = 'Stop'` alone is sufficient.
- **Backtick escape sequences in double-quoted strings:** In `"..."`, backtick is the escape character. Several combinations produce invisible control characters: `` `a `` (BEL/bell), `` `b `` (backspace), `` `f `` (form feed), `` `v `` (vertical tab). This is a silent bug — the string appears correct in source but outputs a control character at runtime. Rule: use single-quoted strings `'...'` whenever the string contains literal backticks (e.g. Markdown code spans). If variable interpolation is required, use ` `` ` (two backticks) for a literal backtick, and avoid placing a backtick immediately before any of the letters `a b f n r t u v 0`.
- Apply all standards to **every code change**, including refactorings and partial edits – not only to new scripts.
