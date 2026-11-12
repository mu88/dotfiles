import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const helper = fileURLToPath(new URL('../TaskbarProgress.ps1', import.meta.url));
const token = '0123456789abcdef0123456789abcdef';
const quote = value => `'${value.replaceAll("'", "''")}'`;
const record = (sequence, state) => `${token}|${String(sequence).padStart(19, '0')}|${state.padEnd(8, '_')}|END`;

const stub = `
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

namespace WezTermTaskbar
{
    public sealed class FixtureClock
    {
        public TimeSpan Elapsed { get; private set; }
        public void Restart() { Elapsed = TimeSpan.Zero; }
        public void Expire() { Elapsed = TimeSpan.FromSeconds(11); }
    }

    public sealed class SafeTaskbar : IDisposable
    {
        private sealed class Frame
        {
            public string Content;
            public int Candidates;
            public bool KnownWindowValid;
            public long WindowHandle;
        }

        private static readonly List<Frame> Frames = new List<Frame>();
        private static int aliveChecks;
        private static int frameIndex = -1;
        public static string StatePath;
        public static string ReadyContent;
        public static int FindCalls;
        public static int ClearCalls;
        public static int DisposeCalls;
        public static readonly List<string> Calls = new List<string>();

        public static void AddFrame(string content, int candidates, bool knownWindowValid, long windowHandle)
        {
            Frames.Add(new Frame { Content = content, Candidates = candidates, KnownWindowValid = knownWindowValid, WindowHandle = windowHandle });
        }

        public static bool MatchesProcess(IntPtr handle, long startTicks) => true;
        public bool Initialize(IntPtr handle) => true;

        public static bool IsProcessAlive(IntPtr handle)
        {
            if (aliveChecks++ == 0) return true;
            frameIndex++;
            if (frameIndex >= Frames.Count) return false;
            if (frameIndex == 0) ReadyContent = File.ReadAllText(StatePath);
            File.WriteAllText(StatePath, Frames[frameIndex].Content, Encoding.ASCII);
            return true;
        }

        public static IntPtr FindUniqueWindow(IntPtr handle, uint processId)
        {
            FindCalls++;
            return Frames[frameIndex].Candidates == 1 ? new IntPtr(Frames[frameIndex].WindowHandle) : IntPtr.Zero;
        }

        public bool SetState(IntPtr handle, uint processId, IntPtr window, int state)
        {
            Calls.Add(frameIndex + ":" + window.ToInt64() + ":" + state);
            return true;
        }

        public bool ClearKnownWindow(IntPtr handle, uint processId, IntPtr window)
        {
            ClearCalls++;
            if (!Frames[frameIndex].KnownWindowValid) return false;
            Calls.Add(frameIndex + ":" + window.ToInt64() + ":0:known");
            return true;
        }

        public void Dispose() => DisposeCalls++;
    }
}`;

function runHelper({ frames = [], existing, expireAfterFirstFrame = false, existingMutex = false }) {
  const directory = mkdtempSync(join(tmpdir(), 'wezterm-taskbar-runtime-'));
  try {
    const statePath = join(directory, 'state');
    const runner = join(directory, 'runner.ps1');
    if (existing !== undefined) writeFileSync(statePath, existing, 'ascii');
    const frameSetup = frames.map(({ content, candidates = 1, knownWindowValid = true, windowHandle = 42 }) =>
      `[WezTermTaskbar.SafeTaskbar]::AddFrame(${quote(content)}, ${candidates}, ${knownWindowValid ? '$true' : '$false'}, ${windowHandle})`).join('\n');
    writeFileSync(runner, `
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
${stub}
'@
. ${quote(helper)}
function Test-TaskbarParentProcess { param([int] $GuiPid) return $true }
function New-TaskbarClock { return [WezTermTaskbar.FixtureClock]::new() }
[WezTermTaskbar.SafeTaskbar]::StatePath = ${quote(statePath)}
${frameSetup}
$script:sleepCount = 0
function Start-Sleep {
    param([int] $Milliseconds)
    $script:sleepCount++
    if (${expireAfterFirstFrame ? '$true' : '$false'} -and $script:sleepCount -eq 1) {
        $lastUpdate.Expire()
    }
}
$failure = $null
$existingMutex = $null
if (${existingMutex ? '$true' : '$false'}) {
    $created = $false
    $existingMutex = [System.Threading.Mutex]::new($true, ('Local' + [char] 92 + 'wezterm-taskbar-' + $PID), [ref] $created)
    if (-not $created) { throw 'Fixture mutex was not created' }
}
try {
    Start-TaskbarProgress -GuiPid $PID -StateFile ${quote(statePath)} -Token ${quote(token)}
} catch {
    $failure = $_.Exception.ToString()
} finally {
    if ($existingMutex) { $existingMutex.ReleaseMutex(); $existingMutex.Dispose() }
}
[PSCustomObject]@{
    Failure = $failure
    ReadyContent = [WezTermTaskbar.SafeTaskbar]::ReadyContent
    FinalContent = if ([System.IO.File]::Exists(${quote(statePath)})) { [System.IO.File]::ReadAllText(${quote(statePath)}) } else { $null }
    Calls = @([WezTermTaskbar.SafeTaskbar]::Calls)
    FindCalls = [WezTermTaskbar.SafeTaskbar]::FindCalls
    ClearCalls = [WezTermTaskbar.SafeTaskbar]::ClearCalls
    DisposeCalls = [WezTermTaskbar.SafeTaskbar]::DisposeCalls
    SleepCount = $script:sleepCount
} | ConvertTo-Json -Compress
`);
    const result = spawnSync('pwsh', ['-NoLogo', '-NoProfile', '-File', runner], {
      encoding: 'utf8', timeout: 30000,
    });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(result.stdout);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test('CreateNew preserves an existing state file and exits before applying', () => {
  const result = runHelper({ existing: 'foreign content', frames: [{ content: record(1, 'busy') }] });
  assert.match(result.Failure, /(?:IOException|already exists)/i);
  assert.equal(result.FinalContent, 'foreign content');
  assert.deepEqual(result.Calls, []);
  assert.equal(result.FindCalls, 0);
  assert.equal(result.SleepCount, 0);
  assert.equal(result.DisposeCalls, 1);
});

test('A second helper exits without touching the state file or taskbar', () => {
  const result = runHelper({ existingMutex: true, frames: [{ content: record(1, 'busy') }] });
  assert.equal(result.Failure, null);
  assert.equal(result.FinalContent, null);
  assert.deepEqual(result.Calls, []);
  assert.equal(result.FindCalls, 0);
});

test('Fresh busy and idle records apply their respective states', () => {
  const result = runHelper({ frames: [
    { content: record(1, 'busy') },
    { content: record(2, 'idle') },
    { content: record(3, 'disabled') },
  ] });
  assert.equal(result.Failure, null);
  assert.equal(result.ReadyContent, record(0, 'disabled'));
  assert.deepEqual(result.Calls, ['0:42:1', '1:42:0']);
  assert.equal(result.FindCalls, 2);
  assert.equal(result.SleepCount, 3);
  assert.equal(result.DisposeCalls, 1);
});

test('A fresh busy heartbeat reapplies progress without repeating idle', () => {
  const result = runHelper({ frames: [
    { content: record(1, 'busy') },
    { content: record(2, 'busy') },
    { content: record(3, 'idle') },
    { content: record(4, 'idle') },
  ] });
  assert.equal(result.Failure, null);
  assert.deepEqual(result.Calls, ['0:42:1', '1:42:1', '2:42:0']);
});

test('A repeated sequence does not renew freshness and stale busy clears', () => {
  const result = runHelper({ expireAfterFirstFrame: true, frames: [
    { content: record(7, 'busy') },
    { content: record(7, 'busy') },
    { content: record(8, 'busy') },
  ] });
  assert.equal(result.Failure, null);
  assert.deepEqual(result.Calls, ['0:42:1', '1:42:0:known', '2:42:1']);
  assert.equal(result.SleepCount, 3);
});

test('Ready or disabled records never bind or update an unknown window', () => {
  const result = runHelper({ frames: [
    { content: record(0, 'disabled') },
    { content: record(1, 'disabled') },
    { content: record(2, 'idle') },
  ] });
  assert.equal(result.Failure, null);
  assert.deepEqual(result.Calls, []);
  assert.equal(result.FindCalls, 0);
});

test('Repeated or older sequences cannot change the desired state', () => {
  const result = runHelper({ frames: [
    { content: record(7, 'busy') },
    { content: record(7, 'idle') },
    { content: record(6, 'idle') },
    { content: record(8, 'idle') },
  ] });
  assert.equal(result.Failure, null);
  assert.deepEqual(result.Calls, ['0:42:1', '3:42:0']);
  assert.equal(result.SleepCount, 4);
});

test('Invalid records do not trigger window lookup or state changes', () => {
  const result = runHelper({ frames: [
    { content: '' },
    { content: record(1, 'busy').slice(0, -1) },
    { content: record(2, 'busy').replace(token, 'ffffffffffffffffffffffffffffffff') },
    { content: record(3, 'BUSY') },
    { content: 'x'.repeat(129) },
  ] });
  assert.equal(result.Failure, null);
  assert.deepEqual(result.Calls, []);
  assert.equal(result.FindCalls, 0);
  assert.equal(result.SleepCount, 5);
});

test('Ambiguity clears only a previously identified busy window', () => {
  const result = runHelper({ frames: [
    { content: record(1, 'busy'), candidates: 0 },
    { content: record(2, 'idle'), candidates: 2 },
    { content: record(3, 'busy'), candidates: 1 },
    { content: record(4, 'idle'), candidates: 2 },
    { content: record(5, 'idle'), candidates: 0 },
  ] });
  assert.equal(result.Failure, null);
  assert.deepEqual(result.Calls, ['2:42:1', '3:42:0:known']);
  assert.equal(result.ClearCalls, 1);
  assert.equal(result.FindCalls, 4);
  assert.equal(result.SleepCount, 5);
});

test('Ambiguity does not clear a previously identified window that is no longer valid', () => {
  const result = runHelper({ frames: [
    { content: record(1, 'busy'), candidates: 1 },
    { content: record(2, 'disabled'), candidates: 2, knownWindowValid: false },
  ] });
  assert.equal(result.Failure, null);
  assert.deepEqual(result.Calls, ['0:42:1']);
  assert.equal(result.ClearCalls, 1);
});

test('A replacement window is never updated with the previous window state', () => {
  const result = runHelper({ frames: [
    { content: record(1, 'busy'), windowHandle: 42 },
    { content: record(2, 'busy'), windowHandle: 99 },
    { content: record(3, 'idle'), windowHandle: 99 },
  ] });
  assert.equal(result.Failure, null);
  assert.deepEqual(result.Calls, ['0:42:1', '1:42:0:known']);
});
