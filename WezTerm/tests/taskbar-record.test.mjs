import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const helper = fileURLToPath(new URL('../TaskbarProgress.ps1', import.meta.url));
const quote = value => `'${value.replaceAll("'", "''")}'`;
const token = '0123456789abcdef0123456789abcdef';
const record = (sequence, state) => `${token}|${String(sequence).padStart(19, '0')}|${state.padEnd(8, '_')}|END`;

function runPowerShell(assertions) {
  const directory = mkdtempSync(join(tmpdir(), 'wezterm-taskbar-record-test-'));
  try {
    const runner = join(directory, 'runner.ps1');
    writeFileSync(runner, [
      "$ErrorActionPreference = 'Stop'",
      `. ${quote(helper)}`,
      assertions,
    ].join('\n'));
    const result = spawnSync('pwsh', ['-NoLogo', '-NoProfile', '-File', runner], { encoding: 'utf8', timeout: 30000 });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stderr);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test('ParsesValidStateAndSequence', () => {
  runPowerShell([
    `foreach ($state in @('busy', 'idle', 'disabled')) {`,
    `  $record = ConvertFrom-TaskbarRecord -Content (${quote(token)} + '|0000000000000000042|' + $state.PadRight(8, '_') + '|END') -ExpectedToken ${quote(token)}`,
    "  if ($null -eq $record -or $record.State -cne $state -or $record.Sequence -ne 42) { throw 'Incorrect record' }",
    '}',
  ].join('\n'));
});

test('RejectsWrongTokenAndIncompleteRecord', () => {
  runPowerShell([
    `if ($null -ne (ConvertFrom-TaskbarRecord -Content ${quote(record(1, 'busy'))} -ExpectedToken ${quote('ffffffffffffffffffffffffffffffff')})) { throw 'Wrong token accepted' }`,
    `if ($null -ne (ConvertFrom-TaskbarRecord -Content ${quote(record(1, 'busy').slice(0, -1))} -ExpectedToken ${quote(token)})) { throw 'Incomplete record accepted' }`,
  ].join('\n'));
});

test('RejectsInvalidSequenceAndState', () => {
  runPowerShell([
    `foreach ($bad in @(${quote(token + '|-000000000000000001|busy____|END')}, ${quote(token + '|9223372036854775808|busy____|END')}, ${quote(record(1, 'BUSY'))}, ${quote(record(1, 'other'))})) {`,
    `  if ($null -ne (ConvertFrom-TaskbarRecord -Content $bad -ExpectedToken ${quote(token)})) { throw 'Invalid record accepted' }`,
    '}',
  ].join('\n'));
});

test('RejectsUnexpectedPrefixSuffixAndWhitespace', () => {
  runPowerShell([
    `foreach ($bad in @(${quote('x' + record(1, 'busy'))}, ${quote(record(1, 'busy') + 'x')}, ${quote(token + '|0000000000000000001|busy   _|END')}, ${quote(record(1, 'busy') + '\n')})) {`,
    `  if ($null -ne (ConvertFrom-TaskbarRecord -Content $bad -ExpectedToken ${quote(token)})) { throw 'Malformed record accepted' }`,
    '}',
  ].join('\n'));
});

test('RejectsTheHelperProcessAsItsOwnGuiParent', { skip: process.platform !== 'win32' }, () => {
  runPowerShell("if (Test-TaskbarParentProcess -GuiPid $PID) { throw 'A process was accepted as its own parent' }");
});

test('RecognizesTheActualHelperParent', { skip: process.platform !== 'win32' }, () => {
  runPowerShell([
    '$parentId = (Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop).ParentProcessId',
    "if ($parentId -le 0 -or -not (Test-TaskbarParentProcess -GuiPid $parentId)) { throw 'Actual parent was not recognized' }",
  ].join('\n'));
});

test('RejectsAnUnrelatedGuiPidBeforeCreatingState', { skip: process.platform !== 'win32' }, () => {
  runPowerShell([
    "$path = Join-Path ([System.IO.Path]::GetTempPath()) ('wezterm-parent-test-' + [guid]::NewGuid().ToString('N'))",
    '$failure = $null',
    `try { Start-TaskbarProgress -GuiPid $PID -StateFile $path -Token ${quote(token)} } catch { $failure = $_.Exception.Message }`,
    "if ($failure -cne 'The helper was not started by the requested GUI process.') { throw 'Unexpected result for an unrelated GUI process' }",
    "if ([System.IO.File]::Exists($path)) { throw 'State file was created for an unrelated GUI process' }",
  ].join('\n'));
});
