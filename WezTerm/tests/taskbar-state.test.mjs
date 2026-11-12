import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const binary = process.env.WEZTERM_TEST_EXECUTABLE;
const modulePath = fileURLToPath(new URL('../lib/taskbar-state.lua', import.meta.url)).replaceAll('\\', '/');
const quote = value => JSON.stringify(value.replaceAll('\\', '/'));

function runLua(assertions) {
  assert.ok(binary, 'WEZTERM_TEST_EXECUTABLE must identify an installed WezTerm executable');
  const directory = mkdtempSync(join(tmpdir(), 'wezterm-taskbar-state-test-'));
  try {
    const runner = join(directory, 'runner.lua');
    const marker = join(directory, 'result');
    writeFileSync(runner, [
      "local wezterm = require 'wezterm'",
      'local ok, failure = pcall(function()',
      `  local state = dofile(${quote(modulePath)})`,
      assertions,
      'end)',
      `local file = assert(io.open(${quote(marker)}, 'wb'))`,
      "file:write(ok and 'PASS' or tostring(failure)); file:close()",
      'return wezterm.config_builder()',
    ].join('\n'));
    const env = { ...process.env };
    for (const name of ['WEZTERM_UNIX_SOCKET', 'WEZTERM_PANE', 'WEZTERM_STARTUP_PROFILES', 'WEZTERM_JSON_PROFILE_SOURCES']) delete env[name];
    const result = spawnSync(binary, ['--config-file', runner, 'show-keys'], { env, encoding: 'utf8', timeout: 30000 });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(marker, 'utf8'), 'PASS');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test('ClassifiesOneWindowActivity', () => {
  runLua("assert(state.classify(1, true, true) == 'busy'); assert(state.classify(1, false, true) == 'idle')");
});

test('DisablesMissingOrMultipleWindowsAndUnsupportedProgress', () => {
  runLua("assert(state.classify(0, true, true) == 'disabled'); assert(state.classify(2, true, true) == 'disabled'); assert(state.classify(1, true, false) == 'disabled')");
});

test('DisablesInvalidActivityInputs', () => {
  runLua("assert(state.classify(1, nil, true) == 'disabled'); assert(state.classify(1, true, nil) == 'disabled'); assert(state.classify('1', true, true) == 'disabled')");
});

test('PublishesInitialStateAndEveryStateTransition', () => {
  runLua("assert(state.should_publish('idle', nil, 100, nil)); assert(state.should_publish('busy', 'idle', 100, 100)); assert(state.should_publish('disabled', 'busy', 100, 100))");
});

test('PublishesHeartbeatOnlyAtIntervalOrAfterClockReversal', () => {
  runLua("assert(not state.should_publish('busy', 'busy', 101, 100)); assert(state.should_publish('busy', 'busy', 102, 100)); assert(state.should_publish('busy', 'busy', 99, 100))");
});
