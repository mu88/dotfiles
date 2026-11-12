[CmdletBinding()]
param(
    [AllowEmptyCollection()] [string[]] $ProfileId = @(),
    [string] $Cwd,
    [Parameter(Mandatory)] [string] $WezTermPath,
    [switch] $AppendDefault
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
. (Join-Path $PSScriptRoot 'ProfileStart.ps1')
$result = Invoke-ProfileStart @PSBoundParameters
switch ($result.Status) {
    'GuiStartRequested' { Write-Output 'GUI start requested; profile results are unconfirmed.' }
    'Completed' { Write-Output "Profile spawn requests acknowledged: $($result.AcknowledgedSpawns)." }
    default {
        Write-Error -ErrorAction Continue "$($result.Message) Operation status: $($result.OperationStatus). Acknowledged requests: $($result.AcknowledgedSpawns). Outcome uncertain: $($result.OutcomeUncertain). Cleanup failed: $($result.CleanupFailed)."
        exit 1
    }
}
