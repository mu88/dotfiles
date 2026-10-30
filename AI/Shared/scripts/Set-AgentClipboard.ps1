<#
.SYNOPSIS
    Puts a command into the Windows clipboard without leaking it into clipboard history or clipboard managers.

.DESCRIPTION
    AI agents use this script to hand long commands to the user instead of printing them, because terminal UIs wrap long lines and insert border characters.
    The clipboard content is marked so that Windows clipboard history, Windows cloud clipboard and Ditto skip it.
    The script rejects multi-line text and text that looks like it contains secrets.

.PARAMETER Value
    The command to put into the clipboard.

.EXAMPLE
    'docker compose up -d' | & "$env:MU88_DOTFILES/AI/Shared/scripts/Set-AgentClipboard.ps1"

.OUTPUTS
    None.

.NOTES
    Windows only.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [string]$Value
)

$ErrorActionPreference = 'Stop'

$command = $Value.Trim()

if ($command -match '[\r\n]') {
    throw 'The value spans multiple lines; pasting it into a shell would execute each line separately.'
}

$secretPatterns = @{
    'PEM private key'    = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    'GitHub token'       = '\b(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})\b'
    'JSON Web Token'     = '\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.'
    '256-bit base64 key' = '(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{43}=(?![A-Za-z0-9+/=])'
}
foreach ($secretPattern in $secretPatterns.GetEnumerator()) {
    if ($command -cmatch $secretPattern.Value) {
        throw "The value seems to contain a secret ($($secretPattern.Key)); never put secrets into the clipboard."
    }
}

if (-not $IsWindows) {
    throw 'Only Windows is supported.'
}
if (-not ('AgentClipboard' -as [type])) {
    # Raw Win32 instead of WinForms/OLE: Ditto still recorded OLE clipboard content despite the ignore formats
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class AgentClipboard
{
    private const uint UnicodeTextFormat = 13;
    private const uint MoveableMemory = 0x0002;

    [DllImport("user32.dll", SetLastError = true)] private static extern bool OpenClipboard(IntPtr owner);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool CloseClipboard();
    [DllImport("user32.dll", SetLastError = true)] private static extern bool EmptyClipboard();
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetClipboardData(uint format, IntPtr data);
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)] private static extern uint RegisterClipboardFormat(string name);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GlobalAlloc(uint flags, UIntPtr bytes);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GlobalLock(IntPtr memory);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool GlobalUnlock(IntPtr memory);
    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr GlobalFree(IntPtr memory);

    public static void SetText(string text)
    {
        for (var attempt = 1; !OpenClipboard(IntPtr.Zero); attempt++)
        {
            if (attempt == 10)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "The clipboard is locked by another process.");
            }
            Thread.Sleep(100);
        }

        try
        {
            if (!EmptyClipboard())
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }

            var zero = BitConverter.GetBytes(0);
            // Honored by Ditto unconditionally
            SetData(RegisterClipboardFormat("Clipboard Viewer Ignore"), zero);
            // Honored by Ditto only if "enforce clipboard ignore formats" is enabled, and by other clipboard monitors
            SetData(RegisterClipboardFormat("ExcludeClipboardContentFromMonitorProcessing"), zero);
            SetData(RegisterClipboardFormat("CanIncludeInClipboardHistory"), zero);
            SetData(RegisterClipboardFormat("CanUploadToCloudClipboard"), zero);
            SetData(UnicodeTextFormat, Encoding.Unicode.GetBytes(text + "\0"));
        }
        finally
        {
            CloseClipboard();
        }
    }

    private static void SetData(uint format, byte[] bytes)
    {
        var memory = GlobalAlloc(MoveableMemory, (UIntPtr)bytes.Length);
        if (memory == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        Marshal.Copy(bytes, 0, GlobalLock(memory), bytes.Length);
        GlobalUnlock(memory);

        if (SetClipboardData(format, memory) == IntPtr.Zero)
        {
            var error = Marshal.GetLastWin32Error();
            GlobalFree(memory);
            throw new Win32Exception(error);
        }
    }
}
'@
}

[AgentClipboard]::SetText($command)
