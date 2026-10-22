#!/usr/bin/pwsh

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

try {
    $principal = git config --get user.email
} catch {
    throw "Git user.email is not configured."
}

if ([string]::IsNullOrWhiteSpace($principal)) {
    throw "Git user.email is not configured."
}

$allowedSignersFile = Join-Path $PSScriptRoot ".ssh" "allowedSigners"
$signerEntries = @(
    Get-Content -LiteralPath $allowedSignersFile |
        Where-Object { $_ -and -not $_.TrimStart().StartsWith("#") } |
        ForEach-Object {
            $parts = $_ -split "\s+"
            if ($parts.Count -ge 3 -and ($parts[0] -split ",") -contains $principal) {
                [PSCustomObject]@{
                    KeyType = $parts[1]
                    KeyData = $parts[2]
                }
            }
        }
)

if ($signerEntries.Count -ne 1) {
    throw "Expected exactly one allowed signer for principal '$principal', found $($signerEntries.Count)."
}

Write-Output "key::$($signerEntries[0].KeyType) $($signerEntries[0].KeyData)"
