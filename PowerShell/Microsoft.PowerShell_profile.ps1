Push-Location $PSScriptRoot

# Run only in Windows Terminal as other terminals might not properly support other PowerShell modules and screw up the formatting
if (!$env:WT_SESSION) {
    return
}

Import-Module posh-git
Import-Module -Name Terminal-Icons
oh-my-posh init pwsh --config "OhMyPosh.json" | Invoke-Expression

# See https://www.hanselman.com/blog/adding-predictive-intellisense-to-my-windows-terminal-powershell-prompt-with-psreadline
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows

# PowerShell parameter completion shim for the dotnet CLI
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($commandName, $wordToComplete, $cursorPosition)
        dotnet complete --position $cursorPosition "$wordToComplete" | ForEach-Object {
           [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

Pop-Location
