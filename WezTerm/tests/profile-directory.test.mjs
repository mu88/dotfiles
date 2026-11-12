import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const binary = process.env.WEZTERM_TEST_EXECUTABLE;
const guiBinary = process.env.WEZTERM_TEST_GUI_EXECUTABLE;
const live = process.platform === 'win32' && process.env.WEZTERM_TEST_LIVE_GUI === '1' && binary && guiBinary;
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

test('ProfileDispatchPreservesArgumentsEnvironmentAndExplicitDirectories', { skip: !binary }, () => {
  const directory = mkdtempSync(join(tmpdir(), 'wezterm-profile-dispatch-'));
  try {
    const runner = join(directory, 'runner.lua');
    const marker = join(directory, 'passed');
    writeFileSync(runner, [
      "local wezterm = require 'wezterm'",
      `local dispatch = dofile(${quote(join(dotfiles, 'WezTerm', 'lib', 'profile-dispatch.lua'))})`,
      "local id = '{aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa}'",
      "local profile = {guid=id, args={'fixture', 'argument'}, startingDirectory='C:/expected', environment={PROXY='profile'}}",
      'local profiles, metadata, domains = {[id]=profile}, {}, {}',
      'dispatch.domains({exec_domain=function(name, fixup) domains[name] = fixup; return {} end}, profiles, metadata, {defaultProfile=id})',
      'local command = dispatch.spawn_command_for(profile)',
      'assert(command.domain.DomainName == dispatch.configured_domain and command.args[2] == id)',
      "local fixed = domains[command.domain.DomainName]({args=command.args, cwd='C:/inherited', set_environment_variables={WEZTERM_PANE='1', PROXY='incoming', OTHER='retained', WEZTERM_STARTUP_PROFILES='ignored'}})",
      "assert(fixed.args[1] == 'fixture' and fixed.args[2] == 'argument' and fixed.cwd == 'C:/expected')",
      "assert(fixed.set_environment_variables.PROXY == 'profile' and fixed.set_environment_variables.OTHER == 'retained' and fixed.set_environment_variables.WEZTERM_STARTUP_PROFILES == '')",
      "assert(metadata.wezterm_profile_pane_1 == id)",
      "local fixed_repeated = domains[command.domain.DomainName]({args=command.args, cwd='C:/inherited', set_environment_variables={WEZTERM_PANE='2'}})",
      "assert(fixed_repeated.args[1] == 'fixture' and fixed_repeated.cwd == 'C:/expected' and metadata.wezterm_profile_pane_2 == id)",
      "local existing = domains[dispatch.default_domain]({args={dispatch.sentinel}, cwd='C:/override', set_environment_variables={WEZTERM_PANE='3'}})",
      "assert(existing.args[1] == 'fixture' and existing.cwd == 'C:/override' and metadata.wezterm_profile_pane_3 == id)",
      "local specific = domains[dispatch.domain_name(id)]({args={dispatch.sentinel}, cwd='C:/override', set_environment_variables={WEZTERM_PANE='4'}})",
      "assert(specific.args[1] == 'fixture' and specific.cwd == 'C:/override' and metadata.wezterm_profile_pane_4 == id)",
      "profiles[id] = {guid=id, args={'fixture'}}",
      "local without_directory = domains[dispatch.configured_domain]({args=command.args, cwd='C:/inherited', set_environment_variables={WEZTERM_PANE='5'}})",
      "assert(without_directory.cwd == nil and metadata.wezterm_profile_pane_5 == id)",
      'profiles[id] = profile',
      "assert(not pcall(domains[dispatch.configured_domain], {args={dispatch.sentinel, '{bad}'}, set_environment_variables={WEZTERM_PANE='4'}}))",
      "assert(not pcall(domains[dispatch.configured_domain], {args={dispatch.sentinel, id, 'extra'}, set_environment_variables={WEZTERM_PANE='4'}}))",
      "assert(not pcall(domains[dispatch.domain_name(id)], {args={'unexpected'}, set_environment_variables={WEZTERM_PANE='4'}}))",
      "assert(not pcall(domains[dispatch.domain_name(id)], {args={dispatch.sentinel}, set_environment_variables={WEZTERM_PANE='invalid'}}))",
      `local file = assert(io.open(${quote(marker)}, 'wb')); file:write('PASS'); file:close()`,
      'return wezterm.config_builder()',
    ].join('\n'));
    const environment = { ...process.env };
    for (const name of ['WEZTERM_UNIX_SOCKET', 'WEZTERM_PANE', 'WEZTERM_CONFIG_FILE']) delete environment[name];
    const result = spawnSync(binary, ['--config-file', runner, 'show-keys'], { env: environment, encoding: 'utf8', timeout: 30000 });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, 'Headless profile dispatch check failed');
    assert.equal(readFileSync(marker, 'utf8'), 'PASS');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('ProfileSelectorUsesTheSelectedProfilesDirectory', { skip: !binary }, () => {
  const directory = mkdtempSync(join(tmpdir(), 'wezterm-profile-selector-'));
  try {
    const source = join(directory, 'profiles.json');
    const marker = join(directory, 'passed');
    const runner = join(directory, 'runner.lua');
    const firstId = '{aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa}';
    const secondId = '{bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb}';
    writeFileSync(source, JSON.stringify({
      globals: { defaultProfile: firstId },
      profiles: { list: [
        { guid: firstId, name: 'first', args: ['first'], startingDirectory: 'C:/first' },
        { guid: secondId, name: 'second', args: ['second'], startingDirectory: 'C:/second' },
      ] },
    }));
    writeFileSync(runner, [
      "local actual = require 'wezterm'",
      'local real_getenv = os.getenv',
      `os.getenv = function(name) if name == 'WEZTERM_JSON_PROFILE_SOURCES' then return ${quote(source)} end; return real_getenv(name) end`,
      'local callbacks, calls, metadata = {}, {}, {}',
      "local fake = setmetatable({target_triple='x86_64-unknown-linux-gnu', GLOBAL=metadata}, {__index=actual})",
      'fake.config_builder = function() return {} end',
      'fake.action_callback = function(callback) return callback end',
      'fake.action = {InputSelector=function(value) return value end, CloseCurrentTab=function(value) return value end}',
      'fake.exec_domain = function(name, fixup) return {name=name, fixup=fixup} end',
      'fake.on = function(name, callback) callbacks[name] = callback end',
      'fake.add_to_config_reload_watch_list = function() end',
      'package.loaded.wezterm = fake',
      `local config = dofile(${quote(join(dotfiles, 'WezTerm', 'wezterm.lua'))})`,
      `local active = {get_domain_name=function() return 'profile-${secondId}' end}`,
      'local opened = {pane_id=function() return 99 end}',
      'local tab = {active_pane=function() return active end}',
      'local mux = {active_tab=function() return tab end, spawn_tab=function(_, command) calls[#calls+1]=command; return {}, opened end}',
      'local window = {mux_window=function() return mux end}',
      "config.keys[1].action.action(window, active, 'second')",
      'assert(#calls == 1)',
      `assert(calls[1].domain.DomainName == 'profile-configured' and calls[1].args[2] == '${secondId}')`,
      `assert(config.launch_menu[2].domain.DomainName == 'profile-configured' and config.launch_menu[2].args[2] == '${secondId}')`,
      `assert(metadata.wezterm_profile_pane_99 == '${secondId}')`,
      `local file = assert(io.open(${quote(marker)}, 'wb')); file:write('PASS'); file:close()`,
      'package.loaded.wezterm = actual',
      'return actual.config_builder()',
    ].join('\n'));
    const environment = { ...process.env, MU88_DOTFILES: dotfiles };
    for (const name of ['WEZTERM_UNIX_SOCKET', 'WEZTERM_PANE', 'WEZTERM_CONFIG_FILE', 'WEZTERM_STARTUP_PROFILES']) delete environment[name];
    const result = spawnSync(binary, ['--config-file', runner, 'show-keys'], { env: environment, encoding: 'utf8', timeout: 30000 });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, 'Headless profile selector check failed');
    assert.equal(readFileSync(marker, 'utf8'), 'PASS');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('ProfileTabsAndSplitsPreserveConfiguredDirectories', { skip: !live, timeout: 60000 }, async () => {
  const directory = mkdtempSync(join(tmpdir(), 'wezterm-profile-directory-'));
  const firstDirectory = join(directory, 'first');
  const defaultDirectory = join(directory, 'default');
  const launcherDirectory = join(directory, 'launcher');
  for (const path of [firstDirectory, defaultDirectory, launcherDirectory]) mkdirSync(path);
  const firstId = '{aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa}';
  const secondId = '{bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb}';
  const defaultId = '{cccccccc-cccc-cccc-cccc-cccccccccccc}';
  const fixture = String.raw`
    const fs = require('node:fs');
    const path = require('node:path');
    const directory = process.env.FIXTURE_DIRECTORY;
    const marker = path.join(directory, process.pid + '.json');
    fs.writeFileSync(marker + '.tmp', JSON.stringify({name: process.env.FIXTURE_NAME, cwd: process.cwd(), pane: process.env.WEZTERM_PANE, pid: process.pid, global: process.env.FIXTURE_GLOBAL, startup: process.env.WEZTERM_STARTUP_PROFILES}));
    fs.renameSync(marker + '.tmp', marker);
    process.stdin.on('data', data => {
      const action = data.toString().trim();
      if (action === 'm') {
        process.chdir(process.env.FIXTURE_OTHER_DIRECTORY);
        fs.writeFileSync(path.join(directory, 'moved-' + process.pid), 'done');
      } else if (action === 'd' || action === 's' || action === 'n') {
        fs.writeFileSync(path.join(directory, 'signal-' + process.pid), action);
        process.stdout.write('\x1b]1337;SetUserVar=FIXTURE_ACTION=' + Buffer.from(action).toString('base64') + '\x07');
      }
    });
    setTimeout(() => process.exit(0), 45000);
  `;
  const profile = (guid, name, cwd) => ({ guid, name, args: [process.execPath, '-e', fixture], ...(cwd ? { startingDirectory: cwd } : {}), environment: { FIXTURE_NAME: name, FIXTURE_DIRECTORY: directory, FIXTURE_OTHER_DIRECTORY: name === 'first' ? defaultDirectory : firstDirectory, ...(name === 'second' ? { FIXTURE_GLOBAL: 'profile' } : {}) } });
  const source = join(directory, 'profiles.json');
  writeFileSync(source, JSON.stringify({
    globals: { defaultProfile: defaultId, environment: { FIXTURE_GLOBAL: 'global' } },
    profiles: { defaults: { startingDirectory: defaultDirectory }, list: [profile(firstId, 'first', firstDirectory), profile(secondId, 'second'), profile(defaultId, 'default')] },
  }));
  const config = join(directory, 'wezterm.lua');
  writeFileSync(config, [
    "local actual = require 'wezterm'",
    'local real_getenv = os.getenv',
    "os.getenv = function(name) if name == 'WEZTERM_JSON_PROFILE_SOURCES' then return real_getenv 'WEZTERM_TEST_FIXTURE_SOURCE' end; if name == 'WEZTERM_STARTUP_PROFILES' then return real_getenv 'WEZTERM_TEST_FIXTURE_LAYOUT' end; return real_getenv(name) end",
    "local fake = setmetatable({target_triple='x86_64-unknown-linux-gnu'}, {__index=actual})",
    'package.loaded.wezterm = fake',
    `local config = dofile(${quote(join(dotfiles, 'WezTerm', 'wezterm.lua'))})`,
    "actual.on('user-var-changed', function(window, pane, name, value)",
    "  if name ~= 'FIXTURE_ACTION' then return end",
    `  local marker = assert(io.open(${quote(join(directory, 'event-'))} .. pane:pane_id(), 'wb')); marker:write(value); marker:close()`,
    "  if value == 'n' then window:perform_action(actual.action.SpawnCommandInNewTab(config.launch_menu[2]), pane); return end",
    "  local key = value == 'd' and 't' or value == 's' and 'd' or nil",
    "  for _, binding in ipairs(config.keys) do if key and binding.key == key then window:perform_action(binding.action, pane); return end end",
    'end)',
    'package.loaded.wezterm = actual',
    'return config',
  ].join('\n'));
  const environment = { ...process.env, MU88_DOTFILES: dotfiles, WEZTERM_TEST_FIXTURE_SOURCE: source, WEZTERM_TEST_FIXTURE_LAYOUT: JSON.stringify([firstId, secondId, secondId]) };
  for (const name of ['WEZTERM_UNIX_SOCKET', 'WEZTERM_PANE', 'WEZTERM_CONFIG_FILE', 'WEZTERM_STARTUP_PROFILES']) delete environment[name];
  let gui;
  let cliEnvironment;
  try {
    gui = spawn(guiBinary, ['--config-file', config, 'start', '--always-new-process'], { cwd: launcherDirectory, env: environment, stdio: 'ignore' });
    assert.ok(gui.pid, 'Fixture GUI did not start');
    const socket = join(homedir(), '.local', 'share', 'wezterm', `gui-sock-${gui.pid}`);
    cliEnvironment = { ...environment, WEZTERM_UNIX_SOCKET: socket };
    await waitFor(() => {
      const runtime = join(homedir(), '.local', 'share', 'wezterm');
      return existsSync(runtime) && readdirSync(runtime).includes(`gui-sock-${gui.pid}`);
    }, 'Fixture GUI socket did not appear');
    const readRecords = () => {
      const files = readdirSync(directory).filter(name => /^\d+\.json$/.test(name));
      return files.map(name => JSON.parse(readFileSync(join(directory, name), 'utf8')));
    };
    const records = await waitFor(() => {
      const current = readRecords();
      return current.length === 4 ? current : null;
    }, 'Expected fixture processes did not start');
    assert.deepEqual(records.map(record => record.name).sort(), ['default', 'first', 'second', 'second']);
    for (const record of records) {
      assert.equal(record.cwd.toLowerCase(), (record.name === 'first' ? firstDirectory : defaultDirectory).toLowerCase(), `${record.name} started in the wrong directory`);
      assert.equal(record.global, record.name === 'second' ? 'profile' : 'global', `${record.name} received the wrong environment`);
      assert.ok(!record.startup, `${record.name} inherited the startup layout`);
    }
    const cli = args => {
      const result = spawnSync(binary, ['cli', '--no-auto-start', ...args], { env: cliEnvironment, encoding: 'utf8', timeout: 5000 });
      assert.equal(result.status, 0, 'Fixture CLI request failed');
    };
    const signal = (record, action) => {
      assert.match(record.pane, /^\d+$/);
      cli(['activate-pane', '--pane-id', record.pane]);
      cli(['send-text', '--pane-id', record.pane, '--no-paste', `${action}\r`]);
    };
    const nextRecord = async (before, name) => waitFor(() => {
      const newRecords = readRecords().filter(record => !before.has(record.pane));
      return newRecords.length === 1 && newRecords[0].name === name ? newRecords[0] : null;
    }, `Expected ${name} fixture process did not start`);
    const knownPanes = () => new Set(readRecords().map(record => record.pane));
    const move = async record => {
      signal(record, 'm');
      await waitFor(() => existsSync(join(directory, `moved-${record.pid}`)), 'Fixture process did not change directory');
    };
    const first = records.find(record => record.name === 'first');
    let before = knownPanes();
    signal(first, 'd');
    await waitFor(() => existsSync(join(directory, `signal-${first.pid}`)), 'Fixture process did not receive the action');
    await waitFor(() => existsSync(join(directory, `event-${first.pane}`)), 'Fixture action was not received by WezTerm');
    const openedDefault = await nextRecord(before, 'default');
    assert.equal(openedDefault.cwd.toLowerCase(), defaultDirectory.toLowerCase(), 'Manual default tab started in the wrong directory');
    await move(openedDefault);
    before = knownPanes();
    signal(openedDefault, 'd');
    const repeatedDefault = await nextRecord(before, 'default');
    assert.equal(repeatedDefault.cwd.toLowerCase(), defaultDirectory.toLowerCase(), 'Repeated default tab inherited the active directory');
    before = knownPanes();
    signal(openedDefault, 'n');
    const nativeLaunch = await nextRecord(before, 'second');
    assert.equal(nativeLaunch.cwd.toLowerCase(), defaultDirectory.toLowerCase(), 'Native launcher inherited the active directory');
    await move(nativeLaunch);
    before = knownPanes();
    signal(nativeLaunch, 's');
    const nativeSplit = await nextRecord(before, 'second');
    assert.equal(nativeSplit.cwd.toLowerCase(), defaultDirectory.toLowerCase(), 'Native launcher split inherited the active directory');
    await move(first);
    before = knownPanes();
    signal(first, 's');
    const firstSplit = await nextRecord(before, 'first');
    assert.equal(firstSplit.cwd.toLowerCase(), firstDirectory.toLowerCase(), 'Split inherited the active directory');
    await move(firstSplit);
    before = knownPanes();
    signal(firstSplit, 's');
    const repeatedSplit = await nextRecord(before, 'first');
    assert.equal(repeatedSplit.cwd.toLowerCase(), firstDirectory.toLowerCase(), 'Repeated split inherited the active directory');
  } finally {
    try {
      if (cliEnvironment && gui?.exitCode === null && gui.signalCode === null) {
        const list = spawnSync(binary, ['cli', '--no-auto-start', 'list', '--format', 'json'], { env: cliEnvironment, encoding: 'utf8', timeout: 5000 });
        if (list.status === 0) {
          for (const pane of JSON.parse(list.stdout)) spawnSync(binary, ['cli', '--no-auto-start', 'kill-pane', '--pane-id', String(pane.pane_id)], { env: cliEnvironment, stdio: 'ignore', timeout: 5000 });
        }
      }
    } finally {
      if (gui?.exitCode === null && gui.signalCode === null) gui.kill();
      if (gui && gui.exitCode === null && gui.signalCode === null) await Promise.race([new Promise(resolve => gui.once('exit', resolve)), delay(3000)]);
      rmSync(directory, { recursive: true, force: true });
    }
  }
});
