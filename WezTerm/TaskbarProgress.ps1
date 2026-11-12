param(
    [int] $GuiPid,
    [string] $StateFile,
    [string] $Token
)

$ErrorActionPreference = 'Stop'

function ConvertFrom-TaskbarRecord {
    <#
    .SYNOPSIS
    Parses a complete taskbar state record.
    .DESCRIPTION
    Accepts only an exact record for the expected token and a nonnegative Int64 sequence.
    .PARAMETER Content
    The complete record content.
    .PARAMETER ExpectedToken
    The lowercase hexadecimal token assigned to this helper.
    .EXAMPLE
    ConvertFrom-TaskbarRecord -Content '0123456789abcdef0123456789abcdef|0000000000000000001|busy____|END' -ExpectedToken '0123456789abcdef0123456789abcdef'
    .OUTPUTS
    System.Management.Automation.PSCustomObject or no output for an invalid record.
    .NOTES
    Whitespace, newlines, and additional content are not permitted.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Content,
        [AllowNull()]
        [AllowEmptyString()]
        [string] $ExpectedToken
    )

    if ($ExpectedToken -cnotmatch '\A[0-9a-f]{32}\z' -or $null -eq $Content) {
        return $null
    }

    $match = [regex]::Match($Content, '\A([0-9a-f]{32})\|([0-9]{19})\|(busy____|idle____|disabled)\|END\z')
    if (-not $match.Success -or $match.Groups[1].Value -cne $ExpectedToken) {
        return $null
    }

    [long] $sequence = 0
    if (-not [long]::TryParse($match.Groups[2].Value, [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref] $sequence)) {
        return $null
    }

    [PSCustomObject]@{
        Sequence = $sequence
        State = $match.Groups[3].Value.TrimEnd('_')
    }
}

function Test-TaskbarParentProcess {
    <#
    .SYNOPSIS
    Checks whether the helper was started by the expected process.
    .DESCRIPTION
    Compares the helper's recorded parent process ID with the expected GUI process ID.
    .PARAMETER GuiPid
    The process ID expected to be the helper's parent.
    .EXAMPLE
    Test-TaskbarParentProcess -GuiPid 1234
    .OUTPUTS
    System.Boolean.
    .NOTES
    The caller must independently verify process identity and creation time.
    #>
    [CmdletBinding()]
    param([int] $GuiPid)

    $current = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop
    return $null -ne $current -and $current.ParentProcessId -eq $GuiPid
}

function New-TaskbarClock {
    <#
    .SYNOPSIS
    Creates a monotonic clock for tracking status freshness.
    .DESCRIPTION
    Provides elapsed time without relying on changes to the system clock.
    .EXAMPLE
    New-TaskbarClock
    .OUTPUTS
    System.Diagnostics.Stopwatch.
    .NOTES
    The clock starts when its Restart method is called.
    #>
    [CmdletBinding()]
    param()

    return [System.Diagnostics.Stopwatch]::new()
}

function Start-TaskbarProgress {
    <#
    .SYNOPSIS
    Watches one WezTerm GUI process and its taskbar state record.
    .DESCRIPTION
    Applies state only to a uniquely identified visible window while the GUI process remains alive.
    .PARAMETER GuiPid
    The process ID of the long-lived WezTerm GUI process.
    .PARAMETER StateFile
    An absolute state file path under the current temporary directory.
    .PARAMETER Token
    The lowercase hexadecimal token expected in each state record.
    .EXAMPLE
    Start-TaskbarProgress -GuiPid 1234 -StateFile "$([System.IO.Path]::GetTempPath())wezterm-state" -Token '0123456789abcdef0123456789abcdef'
    .OUTPUTS
    None.
    .NOTES
    The state file is created exclusively, initialized once, and never deleted by this helper.
    #>
    [CmdletBinding()]
    param(
        [int] $GuiPid,
        [string] $StateFile,
        [string] $Token
    )

    $ErrorActionPreference = 'Stop'
    if (-not $IsWindows) {
        throw 'Taskbar progress is supported only on Windows.'
    }
    if ($GuiPid -le 0 -or $Token -cnotmatch '\A[0-9a-f]{32}\z' -or [string]::IsNullOrEmpty($StateFile) -or -not [System.IO.Path]::IsPathFullyQualified($StateFile)) {
        throw 'A GUI process ID, an absolute temporary state path, and a valid token are required.'
    }
    $statePath = [System.IO.Path]::GetFullPath($StateFile)
    $tempPath = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $statePath.StartsWith($tempPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The state file must be under the current temporary directory.'
    }
    if (-not (Test-TaskbarParentProcess -GuiPid $GuiPid)) {
        throw 'The helper was not started by the requested GUI process.'
    }

    $guiProcess = [System.Diagnostics.Process]::GetProcessById($GuiPid)
    $helperProcess = [System.Diagnostics.Process]::GetCurrentProcess()
    $taskbar = $null
    $mutex = $null
    $mutexOwned = $false
    try {
        $guiHandle = $guiProcess.Handle
        if ($guiProcess.HasExited) {
            return
        }

        if ($null -eq ('WezTermTaskbar.SafeTaskbar' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace WezTermTaskbar
{
    [ComImport, Guid("EA1AFB91-9E28-4B86-90E9-9E9F8A5EEFAF"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface ITaskbarList3
    {
        [PreserveSig] int HrInit();
        [PreserveSig] int AddTab(IntPtr window);
        [PreserveSig] int DeleteTab(IntPtr window);
        [PreserveSig] int ActivateTab(IntPtr window);
        [PreserveSig] int SetActiveAlt(IntPtr window);
        [PreserveSig] int MarkFullscreenWindow(IntPtr window, [MarshalAs(UnmanagedType.Bool)] bool fullscreen);
        [PreserveSig] int SetProgressValue(IntPtr window, ulong completed, ulong total);
        [PreserveSig] int SetProgressState(IntPtr window, int state);
    }

    [ComImport, Guid("56FDF344-FD6D-11D0-958A-006097C9A090")]
    internal class TaskbarList { }

    public sealed class SafeTaskbar : IDisposable
    {
        [return: MarshalAs(UnmanagedType.Bool)]
        private delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);
        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowVisible(IntPtr window);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindow(IntPtr window);
        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll", EntryPoint = "QueryFullProcessImageNameW", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryFullProcessImageName(IntPtr processHandle, uint flags, [Out] char[] imageName, ref uint size);
        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetProcessTimes(IntPtr processHandle, out long creation, out long exit, out long kernel, out long user);

        private ITaskbarList3 taskbar;

        public static bool IsProcessAlive(IntPtr processHandle)
        {
            return WaitForSingleObject(processHandle, 0) == 0x00000102;
        }

        public static bool MatchesProcess(IntPtr processHandle, long helperStartTicks)
        {
            if (!IsProcessAlive(processHandle)) return false;
            var imageName = new char[32768];
            uint size = (uint)imageName.Length;
            long creation, exit, kernel, user;
            if (!QueryFullProcessImageName(processHandle, 0, imageName, ref size) ||
                !GetProcessTimes(processHandle, out creation, out exit, out kernel, out user)) return false;
            return String.Equals(System.IO.Path.GetFileName(new string(imageName, 0, (int)size)), "wezterm-gui.exe", StringComparison.OrdinalIgnoreCase) &&
                DateTime.FromFileTimeUtc(creation).Ticks < helperStartTicks && IsProcessAlive(processHandle);
        }

        public bool Initialize(IntPtr processHandle)
        {
            if (!IsProcessAlive(processHandle)) return false;
            taskbar = (ITaskbarList3)new TaskbarList();
            if (!IsProcessAlive(processHandle)) return false;
            Marshal.ThrowExceptionForHR(taskbar.HrInit());
            return true;
        }

        public static IntPtr FindUniqueWindow(IntPtr processHandle, uint processId)
        {
            if (!IsProcessAlive(processHandle)) return IntPtr.Zero;
            IntPtr match = IntPtr.Zero;
            int count = 0;
            bool completed = EnumWindows((window, parameter) =>
            {
                uint owner;
                if (IsWindowVisible(window) && GetWindowThreadProcessId(window, out owner) != 0 && owner == processId)
                {
                    match = window;
                    count++;
                    if (count > 1) return false;
                }
                return true;
            }, IntPtr.Zero);
            return completed && count == 1 && IsProcessAlive(processHandle) ? match : IntPtr.Zero;
        }

        public bool SetState(IntPtr processHandle, uint processId, IntPtr window, int state)
        {
            if (window == IntPtr.Zero || FindUniqueWindow(processHandle, processId) != window) return false;
            uint owner;
            if (!IsWindow(window) || !IsWindowVisible(window) || GetWindowThreadProcessId(window, out owner) == 0 || owner != processId || !IsProcessAlive(processHandle)) return false;
            Marshal.ThrowExceptionForHR(taskbar.SetProgressState(window, state));
            return true;
        }

        public bool ClearKnownWindow(IntPtr processHandle, uint processId, IntPtr window)
        {
            uint owner;
            if (window == IntPtr.Zero || !IsWindow(window) || GetWindowThreadProcessId(window, out owner) == 0 || owner != processId || !IsProcessAlive(processHandle)) return false;
            Marshal.ThrowExceptionForHR(taskbar.SetProgressState(window, 0));
            return true;
        }

        public void Dispose()
        {
            if (taskbar != null)
            {
                Marshal.FinalReleaseComObject(taskbar);
                taskbar = null;
            }
        }
    }
}
'@
        }

        if (-not [WezTermTaskbar.SafeTaskbar]::MatchesProcess($guiHandle, $helperProcess.StartTime.ToUniversalTime().Ticks)) {
            throw 'The GUI process identity or start time is invalid.'
        }

        $created = $false
        $mutex = [System.Threading.Mutex]::new($true, "Local\wezterm-taskbar-$GuiPid", [ref] $created)
        if (-not $created) { return }
        $mutexOwned = $true

        $taskbar = [WezTermTaskbar.SafeTaskbar]::new()
        if (-not $taskbar.Initialize($guiHandle)) {
            return
        }

        if (-not [WezTermTaskbar.SafeTaskbar]::IsProcessAlive($guiHandle)) {
            return
        }
        $readyBytes = [System.Text.Encoding]::ASCII.GetBytes("$Token|0000000000000000000|disabled|END")
        $readyStream = [System.IO.FileStream]::new($statePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
        try {
            $readyStream.Write($readyBytes, 0, $readyBytes.Length)
            $readyStream.Flush()
        }
        finally {
            $readyStream.Dispose()
        }

        [long] $lastSequence = -1
        $lastUpdate = New-TaskbarClock
        $desiredState = $null
        $boundWindow = [IntPtr]::Zero
        $bindingInvalidated = $false
        $appliedWindow = [IntPtr]::Zero
        $appliedState = $null
        while ([WezTermTaskbar.SafeTaskbar]::IsProcessAlive($guiHandle)) {
            $content = $null
            try {
                $stream = [System.IO.FileStream]::new($statePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
                try {
                    $buffer = [byte[]]::new(129)
                    $length = 0
                    while ($length -lt $buffer.Length) {
                        $read = $stream.Read($buffer, $length, $buffer.Length - $length)
                        if ($read -eq 0) { break }
                        $length += $read
                    }
                    if ($length -lt $buffer.Length) {
                        $content = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $length)
                    }
                }
                finally {
                    $stream.Dispose()
                }
            }
            catch [System.IO.IOException] { }
            catch [System.UnauthorizedAccessException] { }

            $freshRecord = $false
            $record = ConvertFrom-TaskbarRecord -Content $content -ExpectedToken $Token
            if ($null -ne $record -and $record.Sequence -gt $lastSequence) {
                $lastSequence = $record.Sequence
                $desiredState = $record.State
                $lastUpdate.Restart()
                $freshRecord = $true
            }

            if ($null -ne $desiredState -and -not $bindingInvalidated) {
                $effectiveState = if ($lastUpdate.Elapsed -gt [TimeSpan]::FromSeconds(10)) { 'disabled' } else { $desiredState }
                if ($effectiveState -ceq 'disabled') {
                    if ($appliedState -eq 1 -and $appliedWindow -ne [IntPtr]::Zero) {
                        if ($taskbar.ClearKnownWindow($guiHandle, [uint32] $GuiPid, $appliedWindow)) {
                            $appliedWindow = [IntPtr]::Zero
                            $appliedState = 0
                        }
                    }
                } elseif ($effectiveState -ceq 'busy' -or $boundWindow -ne [IntPtr]::Zero) {
                    $state = if ($effectiveState -ceq 'busy') { 1 } else { 0 }
                    $window = [WezTermTaskbar.SafeTaskbar]::FindUniqueWindow($guiHandle, [uint32] $GuiPid)
                    if ($window -ne [IntPtr]::Zero -and $boundWindow -ne [IntPtr]::Zero -and $window -ne $boundWindow) {
                        if ($appliedState -eq 1 -and $appliedWindow -ne [IntPtr]::Zero) {
                            [void] $taskbar.ClearKnownWindow($guiHandle, [uint32] $GuiPid, $appliedWindow)
                        }
                        $bindingInvalidated = $true
                    }
                    elseif ($window -eq [IntPtr]::Zero -and $appliedState -eq 1 -and $appliedWindow -ne [IntPtr]::Zero) {
                        if ($taskbar.ClearKnownWindow($guiHandle, [uint32] $GuiPid, $appliedWindow)) {
                            $appliedWindow = [IntPtr]::Zero
                            $appliedState = 0
                        }
                    }
                    elseif ($window -ne [IntPtr]::Zero -and ($window -ne $appliedWindow -or $state -ne $appliedState -or ($state -eq 1 -and $freshRecord))) {
                        if ($boundWindow -eq [IntPtr]::Zero) { $boundWindow = $window }
                        if ($taskbar.SetState($guiHandle, [uint32] $GuiPid, $window, $state)) {
                            $appliedWindow = $window
                            $appliedState = $state
                        }
                    }
                }
            }
            Start-Sleep -Milliseconds 250
        }
    }
    finally {
        try { if ($null -ne $taskbar) { $taskbar.Dispose() } }
        finally {
            try {
                if ($mutexOwned) { $mutex.ReleaseMutex() }
            }
            finally {
                if ($null -ne $mutex) { $mutex.Dispose() }
                $helperProcess.Dispose()
                $guiProcess.Dispose()
            }
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-TaskbarProgress -GuiPid $GuiPid -StateFile $StateFile -Token $Token
}
