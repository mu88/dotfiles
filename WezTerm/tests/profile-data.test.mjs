import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const readProfiles = name => JSON.parse(readFileSync(fileURLToPath(new URL(`../Profiles/${name}.wezterm-profiles.json`, import.meta.url)), 'utf8'));

test('SharedAiProfilesUsePortableCommandsWithoutCorporateProxy', () => {
  const profiles = readProfiles('shared');
  const copilot = profiles.find(profile => profile.name === '🤖 GitHub Copilot CLI');
  const opencode = profiles.find(profile => profile.name === '🤖 OpenCode CLI');
  assert.deepEqual(copilot.args, ['copilot', '--no-auto-update']);
  assert.deepEqual(opencode.args, ['opencode']);
  for (const profile of [copilot, opencode]) {
    assert.equal(profile.cwd, '$(LOCAL_DEV_DIR)');
    assert.equal(profile.env.EDITOR, 'code --wait');
    assert.equal(profile.env.VISUAL, 'code --wait');
    assert.equal(profile.env.HTTP_PROXY, undefined);
    assert.equal(profile.env.HTTPS_PROXY, undefined);
  }
});

test('PsmuxProfilesAreInWindowsSourceOnly', () => {
  const shared = readProfiles('shared');
  const windows = readProfiles('windows');
  assert.equal(shared.some(profile => profile.name.includes('psmux')), false);
  assert.ok(windows.some(profile => profile.name === '🤖 GitHub Copilot CLI (psmux)'));
  assert.ok(windows.some(profile => profile.name === '🔄 psmux Sessions'));
  for (const profiles of [shared, windows]) assert.equal(new Set(profiles.map(profile => profile.name)).size, profiles.length);
});

test('PowerShellAndGitBashUseSelectedEmoji', () => {
  const shared = readProfiles('shared');
  const windows = readProfiles('windows');
  assert.ok(shared.some(profile => profile.name === '⚡ PS Core'));
  assert.ok(shared.some(profile => profile.name === '⚡ PS Core / GitHub'));
  assert.ok(windows.some(profile => profile.name === '⚡ Windows PowerShell'));
  assert.ok(windows.some(profile => profile.name === '📟 Git Bash'));
  assert.equal([...shared, ...windows].some(profile => profile.name.startsWith('🟦 ')), false);
});
