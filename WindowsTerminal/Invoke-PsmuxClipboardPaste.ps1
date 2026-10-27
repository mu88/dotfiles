#!/usr/bin/pwsh

<#
.SYNOPSIS
Pastes clipboard text or an image into a psmux pane with the same shortcut.
.DESCRIPTION
Sends Ctrl+V for clipboard images so the application reads the image directly.
Transfers text through a temporary UTF-8 file and a named bracketed-paste buffer.
.PARAMETER Target
The psmux session:window.pane target captured when the shortcut is pressed.
.EXAMPLE
pwsh -NoProfile -STA -File ./Invoke-PsmuxClipboardPaste.ps1 -Target 'work:0.0'
.OUTPUTS
None.
.NOTES
Requires Windows, psmux, and an STA PowerShell process. Image paste requires
an application that reads clipboard images on Ctrl+V, such as OpenCode or Copilot CLI.
#>
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Target
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Add-Type -AssemblyName System.Windows.Forms

if ([System.Windows.Forms.Clipboard]::ContainsImage()) {
    psmux send-keys -t $Target C-v
    exit
}

$text = [System.Windows.Forms.Clipboard]::GetText()
if ([string]::IsNullOrEmpty($text)) {
    exit
}

$bufferName = 'unified-paste-' + [Guid]::NewGuid().ToString('N')
$temporaryPath = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($temporaryPath, $text, [System.Text.UTF8Encoding]::new($false))
    psmux load-buffer -t $Target -b $bufferName $temporaryPath
    psmux paste-buffer -t $Target -b $bufferName -p -d
}
finally {
    Remove-Item -LiteralPath $temporaryPath -ErrorAction SilentlyContinue
}
