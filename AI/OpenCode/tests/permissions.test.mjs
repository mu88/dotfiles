// Policy checks using unchanged matching/evaluation functions from OpenCode V2.2.1.
// These tests classify strings only; none of the sample commands is executed.
// AI-assisted with OpenCode.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import vm from 'node:vm';

const config = JSON.parse(readFileSync(new URL('../opencode-v2.json', import.meta.url), 'utf8'));
assert.ok(Array.isArray(config.permissions), 'An explicit default-ask policy is required');
const fixture = readFileSync(new URL('./fixtures/opencode-permissions-v2.2.1/evaluate.ts', import.meta.url), 'utf8');
const sandbox = { process: { platform: 'win32' } };
vm.runInNewContext(stripTypeScriptTypes(fixture).replaceAll('export function ', 'function ') + '\nglobalThis.evaluate = evaluate;', sandbox);
const effect = (action, resource) => sandbox.evaluate(action, resource, config.permissions).effect;
const commands = [
  'git --version',
  'git status',
  'git status --short',
  'git status --short --branch',
  'git branch --show-current',
  'git rev-parse --show-toplevel',
  'git rev-parse --abbrev-ref HEAD',
  'git diff --no-ext-diff --no-textconv',
  'git diff --no-ext-diff --no-textconv --stat',
  'git diff --no-ext-diff --no-textconv --check',
  'git diff --no-ext-diff --no-textconv --cached',
  'dotnet --version',
  'dotnet --info',
  'node --version',
  'rtk --version',
];
for (const command of commands) assert.equal(effect('shell', command), 'allow', command);
console.log('PASS: ExactReadOnlyCommandsAllowed');
for (const command of commands.filter(command => command.startsWith('git status') || command.startsWith('git branch') || command.startsWith('git diff'))) {
  assert.equal(effect('shell', `rtk ${command}`), 'allow', `RTK equivalent: ${command}`);
}
console.log('PASS: ExactRtkEquivalentsAllowed');
for (const command of [
  'git push origin main', 'git push --force origin main', 'git commit -am change',
  'git reset --hard', 'git rebase -i HEAD~2', 'git stash', 'git checkout main',
  'git branch -D feature/work', 'git worktree remove ../work',
  'gh api -X DELETE repos/example/repository', 'gh issue create',
  'dotnet test', 'dotnet build', 'npm install', 'terraform apply',
  'docker compose up -d', 'Remove-Item -Recurse project', 'Stop-Process -Name opencode',
  'pwsh -Command git status', 'rtk bypass git push origin main', 'rtk git push origin main',
]) assert.equal(effect('shell', command), 'ask', command);
console.log('PASS: MutationsInstallationsAndExecutionStillAsk');
for (const command of [
  'git status --short > result.txt', 'git status --short; Remove-Item project',
  'git status --short\nRemove-Item project', 'git status --short | Invoke-Expression',
  'git diff --no-ext-diff --no-textconv --output=result.txt',
  'rtk git diff --no-ext-diff --no-textconv --output=result.txt',
  'git -c alias.inspect=!dangerous inspect', 'git diff', 'git show HEAD:.env',
]) assert.equal(effect('shell', command), 'ask', command);
console.log('PASS: ExtraFlagsRedirectionAndRawCompoundResourcesAreNotAllowlisted');
for (const action of ['read', 'glob', 'grep', 'question', 'skill', 'todowrite']) {
  assert.equal(effect(action, 'src/Example.cs'), 'allow', action);
}
assert.equal(effect('read', '.env.example'), 'allow');
console.log('PASS: RoutineSourceToolsAllowed');
for (const resource of [
  '.env', 'src/.env.local', 'TLS/server.key', 'TLS/server.pem', 'TLS/server.pfx',
  'C:\\Users\\example\\.ssh\\id_ed25519', 'C:/Users/example/.aws/credentials',
  '.npmrc', 'appsettings.Production.json', 'auth.json', 'mcp-auth.json',
]) assert.equal(effect('read', resource), 'ask', resource);
console.log('PASS: RecognizableSensitiveReadsStillAsk');
for (const action of ['external_directory', 'edit', 'subagent', 'execute', 'webfetch', 'websearch', 'GitHub_Swiss_Post_issue_write', 'Atlassian_Swiss_Post_editJiraIssue', 'unrecognized_tool']) {
  assert.equal(effect(action, '*'), 'ask', action);
}
console.log('PASS: ExternalAccessWritesNetworkAndUnknownToolsStillAsk');
assert.equal(effect('shell', 'GIT STATUS --SHORT'), 'allow', 'Use actual Windows case-insensitive semantics');
assert.equal(effect('read', 'src\\.ENV.local'), 'ask', 'Use actual slash normalization');
assert.equal(sandbox.evaluate('shell', 'git status --short', config.permissions, [{ action: 'shell', resource: '*', effect: 'deny' }]).effect, 'deny');
console.log('PASS: UpstreamWindowsMatchingAndOrderedOverrides');
