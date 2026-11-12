import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const binary = process.env.WEZTERM_TEST_EXECUTABLE;
const loader = fileURLToPath(new URL('../json-profile-loader.lua', import.meta.url)).replaceAll('\\', '/');
const quote = value => JSON.stringify(value.replaceAll('\\', '/'));

function runLoader({ sources, environment = {}, assertions }) {
  const directory = mkdtempSync(join(tmpdir(), 'wezterm-json-test-'));
  try {
    const files = sources?.map((content, index) => {
      const path = join(directory, `source ${index}.json`);
      if (content !== null) writeFileSync(path, typeof content === 'string' ? content : JSON.stringify(content));
      return path;
    });
    const runner = join(directory, 'runner.lua');
    writeFileSync(runner, [
      "local wezterm = require 'wezterm'",
      "local real_getenv = os.getenv",
      "os.getenv = function(name) if name == 'WEZTERM_JSON_PROFILE_SOURCES' then return real_getenv('WEZTERM_TEST_JSON_SOURCES') end; return real_getenv(name) end",
      `local load_ok, loader = pcall(dofile, ${quote(loader)})`,
      `if not load_ok then local failure = assert(io.open(${quote(join(directory, 'passed'))}, 'wb')); failure:write(tostring(loader)); failure:close(); return wezterm.config_builder() end`,
      assertions,
      `local marker = assert(io.open(${quote(join(directory, 'passed'))}, 'wb')); marker:write('PASS'); marker:close()`,
      'return wezterm.config_builder()',
    ].join('\n'));
    const env = { ...process.env, ...environment };
    if (files === undefined) delete env.WEZTERM_TEST_JSON_SOURCES;
    else env.WEZTERM_TEST_JSON_SOURCES = files.join(';');
    const result = spawnSync(binary, ['--config-file', runner, 'show-keys'], { env, encoding: 'utf8', timeout: 30000 });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stderr);
    assert.ok(existsSync(join(directory, 'passed')), result.stderr);
    assert.equal(readFileSync(join(directory, 'passed'), 'utf8'), 'PASS');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test('UnsetSourcesLoadNoProfiles', { skip: !binary }, () => {
  runLoader({ assertions: 'local profiles = loader.load(wezterm); assert(#profiles == 0)' });
});

test('SourcesPreserveOrderArgumentsAndEnvironmentAndExpandCwd', { skip: !binary }, () => {
  runLoader({
    sources: [
      [{ name: '🧪 First', args: ['program', 'with spaces', '$(LITERAL)', 'quoted "null"'], cwd: '$(WEZTERM_TEST_ROOT)/GitHub', env: { EXAMPLE: '$(LITERAL)' } }],
      [{ name: 'Second', args: ['other'] }],
    ],
    environment: { WEZTERM_TEST_ROOT: 'C:/Fixture Root' },
    assertions: [
      'local profiles = loader.load(wezterm)',
      "assert(#profiles == 2 and profiles[1].name == '🧪 First' and profiles[2].name == 'Second')",
      "assert(profiles[1].cwd == 'C:/Fixture Root/GitHub')",
      "assert(profiles[1].args[2] == 'with spaces' and profiles[1].args[3] == '$(LITERAL)')",
      `assert(profiles[1].args[4] == ${quote('quoted "null"')})`,
      "assert(profiles[1].env.EXAMPLE == '$(LITERAL)')",
    ].join('\n'),
  });
});

test('LaterSourceReplacesCompleteProfileAndKeepsMenuOrder', { skip: !binary }, () => {
  runLoader({
    sources: [
      [{ name: 'AI', args: ['common'], cwd: 'old-cwd', env: { OLD: 'value' } }, { name: 'Shell', args: ['pwsh'] }],
      [{ name: 'AI', args: ['work'], env: { PROXY: 'work-proxy' } }, { name: 'Extra', args: ['extra'] }],
      [{ name: 'AI', args: ['latest'], env: { FINAL: 'value' } }],
    ],
    assertions: [
      'local profiles = loader.load(wezterm)',
      "assert(#profiles == 3 and profiles[1].name == 'AI' and profiles[2].name == 'Shell' and profiles[3].name == 'Extra')",
      "assert(profiles[1].args[1] == 'latest' and profiles[1].env.FINAL == 'value')",
      'assert(profiles[1].env.OLD == nil and profiles[1].env.PROXY == nil and profiles[1].cwd == nil)',
    ].join('\n'),
  });
});

for (const [name, sources, expected] of [
  ['MissingSource', [null], 'Could not open profile source'],
  ['MalformedJson', ['not-json'], 'Invalid JSON profile source'],
  ['NotAList', [{ wrong: true }], 'Invalid JSON profile source'],
  ['MissingName', [[{ args: ['cmd'] }]], 'A profile requires a name'],
  ['MissingArgs', [[{ name: 'Fixture' }]], 'A profile requires a command'],
  ['EmptyArgs', [[{ name: 'Fixture', args: [] }]], 'A profile requires a command'],
  ['EmptyExecutable', [[{ name: 'Fixture', args: [''] }]], 'A profile requires a command'],
  ['NonStringArgument', [[{ name: 'Fixture', args: ['cmd', 5] }]], 'Profile arguments must be strings'],
  ['NullArgument', [[{ name: 'Fixture', args: ['cmd', null, 'extra'] }]], 'Invalid JSON profile source'],
  ['InvalidCwd', [[{ name: 'Fixture', args: ['cmd'], cwd: false }]], 'Profile cwd must be a string'],
  ['InvalidEnvironment', [[{ name: 'Fixture', args: ['cmd'], env: false }]], 'Profile env must be an object'],
  ['InvalidEnvironmentValue', [[{ name: 'Fixture', args: ['cmd'], env: { EXAMPLE: 4 } }]], 'Profile environment values must be strings'],
  ['DuplicateNameWithinSource', [[{ name: 'Same', args: ['first'] }, { name: 'Same', args: ['second'] }]], 'Profile names must be unique within a source'],
  ['InvalidReplacement', [[{ name: 'Same', args: ['first'] }], [{ name: 'Same' }]], 'A profile requires a command'],
  ['MissingCwdVariable', [[{ name: 'Fixture', args: ['cmd'], cwd: '$(WEZTERM_MISSING_FIXTURE)/path' }]], 'Missing environment variable'],
]) test(`Rejects${name}`, { skip: !binary }, () => {
  runLoader({ sources, environment: { WEZTERM_MISSING_FIXTURE: '' }, assertions: [
    'local ok, failure = pcall(loader.load, wezterm)',
    `assert(not ok and tostring(failure):find(${quote(expected)}, 1, true))`,
  ].join('\n') });
});
