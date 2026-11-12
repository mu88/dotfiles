import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const binary = process.env.WEZTERM_TEST_EXECUTABLE;
const modulePath = fileURLToPath(new URL('../lib/taskbar-progress.lua', import.meta.url)).replaceAll('\\', '/');
const dotfiles = fileURLToPath(new URL('../..', import.meta.url)).replaceAll('\\', '/');
const quote = value => JSON.stringify(value.replaceAll('\\', '/'));

function runLua(assertions) {
  assert.ok(binary, 'WEZTERM_TEST_EXECUTABLE must identify an installed WezTerm executable');
  const directory = mkdtempSync(join(tmpdir(), 'wezterm-taskbar-producer-test-'));
  try {
    const runner = join(directory, 'runner.lua');
    const marker = join(directory, 'result');
    writeFileSync(runner, [
      "local wezterm = require 'wezterm'",
      'local ok, failure = pcall(function()',
      `  local producer = dofile(${quote(modulePath)})`,
      `  local dotfiles = ${quote(dotfiles)}`,
      `  local temp = ${quote(directory)}`,
      "  local getenv = os.getenv; os.getenv = function(name) if name == 'TEMP' or name == 'TMP' then return temp end; return getenv(name) end",
      '  local now = 100; os.time = function() return now end',
      '  math.random = function() return 1 end',
      '  local calls = {}',
      "  local fake = {target_triple='x86_64-pc-windows-msvc', GLOBAL={}, procinfo={pid=function() return 1234 end}, background_child_process=function(args) table.insert(calls, args) end, log_error=function() end}",
      "  local function record(token, sequence, state) local value = state == 'busy' and 'busy____' or state == 'idle' and 'idle____' or state; return string.format('%s|%019d|%s|END', token, sequence, value) end",
      '  local function read(path) local file = assert(io.open(path, "rb")); local value = file:read("*a"); file:close(); return value end',
      '  local function write(path, value) local file = assert(io.open(path, "wb")); file:write(value); file:close() end',
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

test('StartsOneHelperAndKeepsControlAcrossReload', () => {
  runLua([
    'assert(producer.start(fake, dotfiles, 17)); assert(producer.start(fake, dotfiles, 17)); assert(#calls == 1)',
    'local control = assert(fake.GLOBAL.taskbar_progress); assert(control.pid == 1234 and control.window_id == 17 and #control.token == 32)',
    "assert(control.token:match('^[0-9a-f]+$') and control.path:find(temp, 1, true) == 1)",
    "assert(calls[1][1] == 'pwsh' and calls[1][4] == '-File' and calls[1][5] == dotfiles .. '/WezTerm/TaskbarProgress.ps1')",
  ].join('\n'));
});

test('DoesNotStartHelperOnLinuxOrWhenSpawningFails', () => {
  runLua([
    "fake.target_triple = 'x86_64-unknown-linux-gnu'; assert(not producer.start(fake, dotfiles, 17) and #calls == 0)",
    "fake.target_triple = 'x86_64-pc-windows-msvc'; fake.background_child_process = function() error('failed') end",
    'assert(not producer.start(fake, dotfiles, 17) and fake.GLOBAL.taskbar_progress == nil)',
  ].join('\n'));
});

test('UsesTmpBeforeTempOnWindows', () => {
  runLua([
    "os.getenv = function(name) if name == 'TMP' then return temp elseif name == 'TEMP' then return temp .. '/different' end; return getenv(name) end",
    'assert(producer.start(fake, dotfiles, 17)); local control = fake.GLOBAL.taskbar_progress',
    "assert(control.path:find(temp .. '/wezterm-taskbar-', 1, true) == 1)",
  ].join('\n'));
});

test('PublishesOnlyAfterMatchingHelperReadyAndPreservesUnknownFiles', () => {
  runLua([
    'assert(producer.start(fake, dotfiles, 17)); local control = fake.GLOBAL.taskbar_progress',
    "write(control.path, 'foreign'); assert(not producer.update(fake, 17, 1, true, true)); assert(read(control.path) == 'foreign')",
    "write(control.path, record(control.token, 0, 'disabled')); assert(producer.update(fake, 17, 1, true, true))",
    "assert(read(control.path) == record(control.token, 1, 'busy'))",
  ].join('\n'));
});

test('PublishesTransitionsAndHeartbeatWithoutDuplicateWrites', () => {
  runLua([
    'assert(producer.start(fake, dotfiles, 17)); local control = fake.GLOBAL.taskbar_progress',
    "write(control.path, record(control.token, 0, 'disabled'))",
    "assert(producer.update(fake, 17, 1, true, true)); assert(not producer.update(fake, 17, 1, true, true)); assert(read(control.path) == record(control.token, 1, 'busy'))",
    "now = 102; assert(producer.update(fake, 17, 1, true, true)); assert(read(control.path) == record(control.token, 2, 'busy'))",
    "assert(producer.update(fake, 17, 1, false, true)); assert(read(control.path) == record(control.token, 3, 'idle'))",
    "assert(producer.update(fake, 17, 2, true, true)); assert(read(control.path) == record(control.token, 4, 'disabled'))",
  ].join('\n'));
});

test('KeepsFailuresFromEscapingToTheStatusCallback', () => {
  runLua([
    'assert(producer.start(fake, dotfiles, 17)); local control = fake.GLOBAL.taskbar_progress',
    "write(control.path, record(control.token, 0, 'disabled'))",
    "local open = io.open; io.open = function(path, mode) if mode == 'r+b' then error('fixture write failure') end; return open(path, mode) end",
    'local updated = producer.update(fake, 17, 1, true, true); io.open = open; assert(not updated)',
  ].join('\n'));
});

test('DoesNotCreateAStateFileThatDisappearedAfterHandshake', () => {
  runLua([
    'assert(producer.start(fake, dotfiles, 17)); local control = fake.GLOBAL.taskbar_progress',
    "write(control.path, record(control.token, 0, 'disabled')); assert(producer.update(fake, 17, 1, false, true))",
    "assert(os.remove(control.path)); assert(not producer.update(fake, 17, 1, true, true)); assert(io.open(control.path, 'rb') == nil)",
  ].join('\n'));
});

test('DoesNotOverwriteAReplacedOrCorruptedStateFile', () => {
  runLua([
    'assert(producer.start(fake, dotfiles, 17)); local control = fake.GLOBAL.taskbar_progress',
    "write(control.path, record(control.token, 0, 'disabled')); assert(producer.update(fake, 17, 1, false, true))",
    "write(control.path, 'foreign'); assert(not producer.update(fake, 17, 1, true, true)); assert(read(control.path) == 'foreign')",
  ].join('\n'));
});

test('RetriesAfterAReadWriteSharingConflict', () => {
  runLua([
    'assert(producer.start(fake, dotfiles, 17)); local control = fake.GLOBAL.taskbar_progress',
    "write(control.path, record(control.token, 0, 'disabled'))",
    "local open = io.open; io.open = function(path, mode) if mode == 'r+b' then return nil end; return open(path, mode) end",
    'local updated = producer.update(fake, 17, 1, true, true); io.open = open; assert(not updated)',
    "assert(read(control.path) == record(control.token, 0, 'disabled'))",
    "assert(producer.update(fake, 17, 1, true, true)); assert(read(control.path) == record(control.token, 1, 'busy'))",
  ].join('\n'));
});

test('StopsIfCloseFailsAfterARecordWasWritten', () => {
  runLua([
    'assert(producer.start(fake, dotfiles, 17)); local control = fake.GLOBAL.taskbar_progress',
    "write(control.path, record(control.token, 0, 'disabled'))",
    "local open = io.open; io.open = function(path, mode)",
    "  local file = open(path, mode); if mode ~= 'r+b' then return file end",
    '  return {read=function(_, ...) return file:read(...) end, seek=function(_, ...) return file:seek(...) end, write=function(_, ...) return file:write(...) end, close=function() file:close(); return nil end}',
    'end',
    'local updated = producer.update(fake, 17, 1, true, true); io.open = open; assert(not updated)',
    "assert(read(control.path) == record(control.token, 1, 'busy'))",
    "assert(not producer.update(fake, 17, 1, false, true)); assert(read(control.path) == record(control.token, 1, 'busy'))",
  ].join('\n'));
});

test('PreservesSequenceAndHelperAcrossModuleReloadWithCopiedGlobal', () => {
  runLua([
    'local stored = {}',
    'local function copy(value) if type(value) ~= "table" then return value end; local result = {}; for key, item in pairs(value) do result[key] = copy(item) end; return result end',
    'fake.GLOBAL = setmetatable({}, {__index=function(_, key) return copy(stored[key]) end, __newindex=function(_, key, value) stored[key] = copy(value) end})',
    'assert(producer.start(fake, dotfiles, 17)); local control = fake.GLOBAL.taskbar_progress',
    "write(control.path, record(control.token, 0, 'disabled')); assert(producer.update(fake, 17, 1, true, true))",
    `local reloaded = dofile(${quote(modulePath)}); assert(reloaded.start(fake, dotfiles, 17) and #calls == 1)`,
    "now = 102; assert(reloaded.update(fake, 17, 1, true, true)); assert(read(control.path) == record(control.token, 2, 'busy'))",
  ].join('\n'));
});

test('DoesNotSpawnWhenTheGeneratedStatePathAlreadyExists', () => {
  runLua([
    "local token = string.format('%08x%08x%08x%08x', 1234, 100, 1, 1)",
    "local path = temp .. '/wezterm-taskbar-' .. token .. '.txt'",
    "write(path, 'foreign'); assert(not producer.start(fake, dotfiles, 17)); assert(#calls == 0 and read(path) == 'foreign')",
  ].join('\n'));
});

test('IgnoresUpdatesFromAnyOtherWindow', () => {
  runLua([
    'assert(producer.start(fake, dotfiles, 17)); local control = fake.GLOBAL.taskbar_progress',
    "write(control.path, record(control.token, 0, 'disabled'))",
    "assert(not producer.update(fake, 18, 1, true, true)); assert(read(control.path) == record(control.token, 0, 'disabled'))",
  ].join('\n'));
});

test('RejectsInvalidOwnerWindowIdentity', () => {
  runLua('assert(not producer.start(fake, dotfiles, nil)); assert(not producer.start(fake, dotfiles, "17")); assert(#calls == 0)');
});
