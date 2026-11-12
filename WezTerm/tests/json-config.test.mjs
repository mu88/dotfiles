import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const binary = process.env.WEZTERM_TEST_EXECUTABLE;
const config = fileURLToPath(new URL('../wezterm.lua', import.meta.url)).replaceAll('\\', '/');
const dotfiles = fileURLToPath(new URL('../..', import.meta.url)).replaceAll('\\', '/');
const quote = value => JSON.stringify(value.replaceAll('\\', '/'));

function runConfiguration({ profiles, rawSource, requested, assertions, platform }) {
  const directory = mkdtempSync(join(tmpdir(), 'wezterm-json-config-test-'));
  try {
    const source = join(directory, 'profiles.json');
    if (rawSource !== undefined) writeFileSync(source, rawSource);
    else if (profiles) writeFileSync(source, JSON.stringify(profiles));
    const runner = join(directory, 'runner.lua');
    writeFileSync(runner, [
      "local actual = require 'wezterm'",
      "os.exit = function(code) error('FIXTURE_EXIT:' .. code) end",
      "local real_getenv = os.getenv",
      "os.getenv = function(name) if name == 'WEZTERM_JSON_PROFILE_SOURCES' then return real_getenv('WEZTERM_TEST_JSON_SOURCES') end; return real_getenv(name) end",
      'local callbacks, calls, maximized = {}, {}, false',
      'local window = {}',
      "window.spawn_tab = function(_, spec) table.insert(calls, {kind='tab', spec=spec}) end",
      'window.gui_window = function() return {maximize=function() maximized = true end} end',
      "local mux = {spawn_window=function(spec) table.insert(calls, {kind='window', spec=spec}); return {}, {}, window end}",
      `local fake = setmetatable({mux=mux${platform ? `,target_triple=${quote(platform)}` : ''}}, {__index=actual})`,
      'fake.on = function(name, callback) callbacks[name] = callback end',
      'package.loaded.wezterm = fake',
      `local config = dofile(${quote(config)})`,
      assertions,
      `local marker = assert(io.open(${quote(join(directory, 'passed'))}, 'wb')); marker:write('PASS'); marker:close()`,
      "package.loaded.wezterm = actual; return actual.config_builder()",
    ].join('\n'));
    const env = { ...process.env, MU88_DOTFILES: dotfiles };
    if (profiles || rawSource !== undefined) env.WEZTERM_TEST_JSON_SOURCES = source;
    else delete env.WEZTERM_TEST_JSON_SOURCES;
    if (requested === undefined) delete env.WEZTERM_STARTUP_PROFILES;
    else env.WEZTERM_STARTUP_PROFILES = requested;
    const result = spawnSync(binary, ['--config-file', runner, 'show-keys'], { env, encoding: 'utf8', timeout: 30000 });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(readFileSync(join(directory, 'passed'), 'utf8'), 'PASS');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

const profiles = [
  { name: '🧪 First', args: ['first', 'argument with spaces'], cwd: 'fixture-cwd', env: { FIXTURE_VALUE: 'first' } },
  { name: 'Second', args: ['second'], env: { FIXTURE_VALUE: 'second', WEZTERM_STARTUP_PROFILES: 'must-clear' } },
];

test('NamedStartupUsesDirectCommandsInOrderThenDefault', { skip: !binary }, () => {
  runConfiguration({ profiles, requested: JSON.stringify(['Second', '🧪 First']), assertions: [
    "callbacks['gui-startup'](nil)",
    "assert(#calls == 3 and calls[1].spec.args[1] == 'second' and calls[2].spec.args[1] == 'first')",
    "assert(calls[3].kind == 'tab' and config.default_prog[1] == 'pwsh' and maximized)",
    "assert(calls[1].spec.set_environment_variables.WEZTERM_STARTUP_PROFILES == '')",
    "assert(calls[2].spec.cwd == 'fixture-cwd' and calls[2].spec.args[2] == 'argument with spaces')",
    "assert(config.launch_menu[1].label == '🧪 First' and config.launch_menu[1].args[1] == 'first')",
  ].join('\n') });
});

test('NoSourcesUsesLuaDefaultWithoutProfiles', { skip: !binary }, () => {
  runConfiguration({ assertions: [
    "assert(#config.launch_menu == 0 and config.default_prog[1] == 'pwsh')",
    "callbacks['gui-startup'](nil); assert(#calls == 1 and maximized)",
  ].join('\n') });
});

test('LinuxConfigurationStartsProfileCommandsDirectly', { skip: !binary }, () => {
  runConfiguration({ profiles, platform: 'x86_64-unknown-linux-gnu', assertions: [
    "assert(config.default_prog[1] == 'pwsh' and config.launch_menu[1].args[1] == 'first')",
    "assert(config.launch_menu[1].args[2] == 'argument with spaces' and config.set_environment_variables.EDITOR == nil)",
  ].join('\n') });
});

test('ExplicitCommandTakesPrecedence', { skip: !binary }, () => {
  runConfiguration({ profiles, requested: JSON.stringify(['Second']), assertions: [
    "callbacks['gui-startup']({args={'explicit'}})",
    "assert(#calls == 1 and calls[1].spec.args[1] == 'explicit')",
  ].join('\n') });
});

test('EmptyStartupListOpensOnlyDefault', { skip: !binary }, () => {
  runConfiguration({ profiles, requested: '[]', assertions: [
    "callbacks['gui-startup'](nil)",
    "assert(#calls == 1 and calls[1].kind == 'window' and config.default_prog[1] == 'pwsh' and maximized)",
  ].join('\n') });
});

for (const [name, requested] of [['Unknown', '["Missing"]'], ['Malformed', '{invalid'], ['NonArray', '{"invalid":true}'], ['NonString', '[5]'], ['NullName', '[null]']]) {
  test(`RejectsStartup${name}`, { skip: !binary }, () => {
    runConfiguration({ profiles, requested, assertions: "local ok, failure = pcall(callbacks['gui-startup'], nil); assert(not ok and tostring(failure):find('FIXTURE_EXIT:1', 1, true) and #calls == 0)" });
  });
}

test('InvalidProfileSourceAbortsOnlyNewGuiStartup', { skip: !binary }, () => {
  runConfiguration({ rawSource: 'invalid-json', requested: '["Missing"]', assertions: [
    "assert(#config.launch_menu == 0)",
    "local ok, failure = pcall(callbacks['gui-startup'], nil)",
    "assert(not ok and tostring(failure):find('FIXTURE_EXIT:1', 1, true) and #calls == 0)",
  ].join('\n') });
});

test('PaneTitleAndBusySpinnerRemainVisible', { skip: !binary }, () => {
  runConfiguration({ profiles, assertions: [
    "local active = {title='Session Alpha', progress='None'}",
    "local idle = callbacks['format-tab-title']({active_pane=active, panes={active}})",
    "local busy = callbacks['format-tab-title']({active_pane=active, panes={active, {progress='Indeterminate'}}})",
    "assert(idle == 'Session Alpha' and busy:find('Session Alpha', 1, true) and busy ~= idle)",
    "assert(callbacks['format-tab-title']({tab_title='Pinned', active_pane=active, panes={active}}) == 'Pinned')",
    "local status; local other = {get_progress=function() return 'Indeterminate' end}",
    "local tab = {panes=function() return {other} end}; local mux_window = {tabs=function() return {tab} end}",
    "local window = {mux_window=function() return mux_window end, set_right_status=function(_, value) status = value end}",
    "callbacks['update-status'](window); assert(status ~= '')",
    "tab.panes = function() return {{get_progress=function() error('unsupported') end}} end",
    "callbacks['update-status'](window); assert(status == '')",
    "assert(callbacks['mux-is-process-stateful'] == nil and config.window_close_confirmation == nil)",
  ].join('\n') });
});
