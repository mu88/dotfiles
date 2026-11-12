import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, unlinkSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const binary = process.env.WEZTERM_TEST_EXECUTABLE;
const guiBinary = process.env.WEZTERM_TEST_GUI_EXECUTABLE;
const enabled = process.platform === 'win32' && process.env.WEZTERM_TEST_LIVE_GUI === '1' && binary && guiBinary;
const dotfiles = fileURLToPath(new URL('../..', import.meta.url)).replaceAll('\\', '/');
const quote = value => JSON.stringify(value.replaceAll('\\', '/'));

async function waitFor(probe, message) {
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    const result = probe();
    if (result) return result;
    await delay(100);
  }
  throw new Error(message);
}

test('LiveStartupAndTabShortcutUseOnlyFixtureProcesses', { skip: !enabled, timeout: 60000 }, async () => {
  const directory = mkdtempSync(join(tmpdir(), 'wezterm-live-startup-test-'));
  const runtime = join(homedir(), '.local', 'share', 'wezterm');
  let guiPid;
  try {
    const signalTab = [...Buffer.from(']1337;SetUserVar=TEST_CLOSE_TAB=MQ==')];
    const progress = [...Buffer.from(']9;4;3;0')];
    const progressProbe = [...Buffer.from(']1337;SetUserVar=TEST_PROGRESS=MQ==')];
    const statefulCode = (ready, signal) => `console.log('${ready}');console.log(process.env.WEZTERM_STARTUP_PROFILES?'ENV_LEAK':'ENV_CLEAR');process.stdin.on('data',()=>process.stdout.write(Buffer.from([27,${signal.join(',')},7])));setInterval(()=>process.stdout.write(Buffer.from([27,${[...Buffer.from(']0;Session Alpha')].join(',')},7,27,${progress.join(',')},7,27,${progressProbe.join(',')},7])),500)`;
    const shellCode = name => `Write-Output '${name}'; Write-Output ('TERM:' + $env:TERM_PROGRAM); if ($env:WEZTERM_STARTUP_PROFILES) { Write-Output 'ENV_LEAK' } else { Write-Output 'ENV_CLEAR' }; if ($env:WEZTERM_TEST_FIXTURE_VALUE) { Write-Output ('VALUE:' + $env:WEZTERM_TEST_FIXTURE_VALUE) }`;
    const source = join(directory, 'profiles.json');
    writeFileSync(source, JSON.stringify([
      { name: 'First', args: ['pwsh', '-NoLogo', '-NoProfile', '-NoExit', '-Command', shellCode('FIRST_READY')], env: { WEZTERM_TEST_FIXTURE_VALUE: 'first', WEZTERM_STARTUP_PROFILES: 'must-clear' } },
      { name: 'Second', args: [process.execPath, '-e', statefulCode('SECOND_READY', signalTab)] },
    ]));
    const config = join(directory, 'wezterm.lua');
    const progressMarker = paneId => join(directory, `progress-${paneId}`);
    writeFileSync(config, [
      "local wezterm = require 'wezterm'",
      "local real_getenv = os.getenv",
      "os.getenv = function(name) if name == 'WEZTERM_JSON_PROFILE_SOURCES' then return real_getenv('WEZTERM_TEST_FIXTURE_SOURCE') end; return real_getenv(name) end",
      `local config = dofile(${quote(join(dotfiles, 'WezTerm', 'wezterm.lua'))})`,
      'os.getenv = real_getenv',
      `config.default_prog = {'pwsh.exe', '-NoLogo', '-NoProfile', '-NoExit', '-Command', ${quote(shellCode('DEFAULT_READY'))}}`,
      "wezterm.on('user-var-changed', function(window, pane, name)",
      "  if name == 'TEST_CLOSE_TAB' then window:perform_action(wezterm.action.CloseCurrentTab {confirm=false}, pane) end",
      `  if name == 'TEST_PROGRESS' and pane:get_progress() == 'Indeterminate' then local file = assert(io.open(${quote(join(directory, 'progress-'))} .. pane:pane_id(), 'wb')); file:write('PASS'); file:close() end`,
      'end)',
      'return config',
    ].join('\n'));
    const starter = join(directory, 'start-fixture.ps1');
    writeFileSync(starter, [
      "$ErrorActionPreference = 'Stop'",
      '$PSNativeCommandUseErrorActionPreference = $true',
      "$env:WEZTERM_STARTUP_PROFILES = 'parent-marker'",
      "$arguments = @('--config-file', ('\"{0}\"' -f $env:WEZTERM_TEST_CONFIG_FILE), 'start', '--always-new-process', '--class', 'wezterm-startup-test')",
      '$process = Start-Process -FilePath $env:WEZTERM_TEST_GUI_EXECUTABLE -ArgumentList $arguments -Environment @{ WEZTERM_STARTUP_PROFILES = $env:WEZTERM_TEST_LAYOUT } -PassThru',
      "if ($env:WEZTERM_STARTUP_PROFILES -ne 'parent-marker') { throw 'Parent environment changed.' }",
      '[IO.File]::WriteAllText($env:WEZTERM_TEST_PID_FILE, [string]$process.Id)',
    ].join('\n'));
    const pidFile = join(directory, 'pid.txt');
    const environment = { ...process.env, MU88_DOTFILES: dotfiles, WEZTERM_TEST_FIXTURE_SOURCE: source, WEZTERM_TEST_CONFIG_FILE: config, WEZTERM_TEST_PID_FILE: pidFile, WEZTERM_TEST_LAYOUT: JSON.stringify(['First', 'Second']) };
    for (const name of ['WEZTERM_UNIX_SOCKET', 'WEZTERM_PANE', 'WT_SESSION', 'OPENCODE_SESSION_ID']) delete environment[name];
    const started = spawnSync('pwsh.exe', ['-NoLogo', '-NoProfile', '-File', starter], { env: environment, stdio: 'ignore', timeout: 30000 });
    if (existsSync(pidFile)) guiPid = Number(readFileSync(pidFile, 'utf8').trim());
    assert.equal(started.error, undefined);
    assert.equal(started.status, 0, 'Fixture starter failed');
    assert.ok(Number.isInteger(guiPid) && guiPid > 0);
    const running = () => { try { process.kill(guiPid, 0); return true; } catch { return false; } };
    const socketName = `gui-sock-${guiPid}`;
    await waitFor(() => running() && readdirSync(runtime).includes(socketName), 'Fixture GUI socket did not appear');
    const cliEnvironment = { ...environment, WEZTERM_UNIX_SOCKET: join(runtime, socketName) };
    const cli = (argumentsToPass, input) => {
      assert.ok(running(), 'Fixture GUI exited unexpectedly');
      const result = spawnSync(binary, ['cli', ...argumentsToPass], { env: cliEnvironment, encoding: 'utf8', input, timeout: 5000 });
      assert.equal(result.error, undefined);
      assert.equal(result.status, 0, 'Fixture CLI failed');
      return result.stdout;
    };
    const list = () => JSON.parse(cli(['list', '--format', 'json']));
    const text = paneId => cli(['get-text', '--pane-id', String(paneId)]);
    const panes = await waitFor(() => {
      const current = list();
      if (current.length !== 3) return null;
      return current.every(pane => text(pane.pane_id).includes('READY')) ? current : null;
    }, 'Expected fixture startup tabs did not appear');
    assert.deepEqual(panes.map(pane => {
      const content = text(pane.pane_id);
      assert.ok(content.includes('ENV_CLEAR'));
      assert.ok(!content.includes('ENV_LEAK'));
      return content.match(/(?:FIRST|SECOND|DEFAULT)_READY/)?.[0];
    }), ['FIRST_READY', 'SECOND_READY', 'DEFAULT_READY']);
    assert.ok(text(panes[0].pane_id).includes('VALUE:first'));
    assert.ok(text(panes[0].pane_id).includes('TERM:WezTerm'));
    await waitFor(() => list().some(pane => pane.pane_id === panes[1].pane_id && pane.title?.includes('Session Alpha')), 'Fixture session title was not received');
    await waitFor(() => existsSync(progressMarker(panes[1].pane_id)) && readFileSync(progressMarker(panes[1].pane_id), 'utf8') === 'PASS', 'Fixture progress was not received');

    const first = panes[0];
    const splitId = Number(cli(['split-pane', '--pane-id', String(first.pane_id), '--right', '--', process.execPath, '-e', statefulCode('SPLIT_READY', signalTab)]).trim());
    assert.ok(Number.isInteger(splitId));
    await waitFor(() => text(splitId).includes('SPLIT_READY') && existsSync(progressMarker(splitId)), 'Fixture split did not report progress');
    cli(['activate-pane', '--pane-id', String(first.pane_id)]);
    assert.ok(list().some(pane => pane.pane_id === splitId && pane.tab_id === first.tab_id));
    cli(['kill-pane', '--pane-id', String(splitId)]);
    await waitFor(() => list().every(pane => pane.pane_id !== splitId), 'Fixture split did not close');

    const second = panes[1];
    cli(['activate-tab', '--tab-id', String(second.tab_id)]);
    cli(['send-text', '--pane-id', String(second.pane_id), '--no-paste'], 'close\r');
    const remaining = await waitFor(() => {
      const current = list();
      return current.length === 2 && current.every(pane => pane.pane_id !== second.pane_id) ? current : null;
    }, 'Tab action showed a prompt or did not close');
    assert.ok(remaining.some(pane => pane.pane_id === panes[0].pane_id));
  } finally {
    const cleanup = "$processes = Get-CimInstance Win32_Process -Filter \"Name='wezterm-gui.exe'\"; $processes | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($env:WEZTERM_TEST_CONFIG_FILE) -and $_.CommandLine.Contains('wezterm-startup-test') } | ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }";
    spawnSync('pwsh.exe', ['-NoLogo', '-NoProfile', '-Command', cleanup], {
      env: { ...process.env, WEZTERM_TEST_CONFIG_FILE: join(directory, 'wezterm.lua') }, stdio: 'ignore', timeout: 15000,
    });
    if (guiPid) {
      const log = join(runtime, `wezterm-gui.exe-log-${guiPid}.txt`);
      try { unlinkSync(log); } catch {}
    }
    rmSync(directory, { recursive: true, force: true });
  }
});
