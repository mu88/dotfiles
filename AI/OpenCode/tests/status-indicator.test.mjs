// Offline cache contract checks. No timers, agents, credentials or network calls run.
// AI-assisted with OpenCode.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { test } from 'node:test';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const sourcePath = process.argv[2] ?? fileURLToPath(new URL('../plugins/status-indicator/tui.ts', import.meta.url));
const source = stripTypeScriptTypes(readFileSync(sourcePath, 'utf8')
  .replace('import { Plugin } from "@opencode/plugin/tui";', '')
  .replace('export default Plugin.define(', 'globalThis.definition = Plugin.define('));
const osc = value => `\x1b]9;4;${value}\x07`;
const makeSessions = () => new Map([
  ['alpha', { info: { title: 'Alpha conversation' }, status: 'idle' }],
  ['beta', { info: { title: 'Beta conversation' }, status: 'idle' }],
]);

function createClient({ sessionID = 'alpha', sessions = makeSessions(), platform = 'win32', environment = { WT_SESSION: 'fixture' }, isTTY = true } = {}) {
  const handlers = new Map();
  const timers = new Map();
  const titles = [];
  const progress = [];
  const controls = { rendererDisposed: false, stdoutFailed: false, routerUnavailable: false, serverCalls: 0 };
  let route = sessionID ? { type: 'session', sessionID } : { type: 'home' };
  let nextTimer = 1;
  // Mirror the documented cached hierarchy; no server metadata is fabricated by the plugin.
  function rootOf(id) {
    let current = id;
    const seen = new Set([id]);
    while (sessions.get(current)?.info?.parentID) {
      const parent = sessions.get(current).info.parentID;
      if (seen.has(parent)) break;
      seen.add(parent);
      current = parent;
    }
    return current;
  }
  function unexpectedServerCall() { controls.serverCalls++; throw new Error('No server polling expected'); }
  const sandbox = {
    process: { platform, env: environment, stdout: {
      isTTY,
      write(sequence) { if (controls.stdoutFailed) throw new Error('Console closed'); progress.push(sequence); },
    } },
    Plugin: { define: definition => definition },
    setInterval(callback, interval) { const id = nextTimer++; timers.set(id, { callback, interval }); return id; },
    clearInterval(id) { timers.delete(id); },
  };
  vm.runInNewContext(source, sandbox);
  assert.equal(sandbox.definition.id, 'opencode-tui-status-indicator');
  const cleanup = sandbox.definition.setup({
    renderer: { setTerminalTitle(title) {
      if (controls.rendererDisposed) throw new Error('NativeSession is closing or disposed');
      titles.push(title);
    } },
    ui: { router: { current() { if (controls.routerUnavailable) throw new Error('Router not ready'); return route; } } },
    client: { session: { get: unexpectedServerCall, list: unexpectedServerCall } },
    data: {
      session: {
        get(id) { return sessions.get(id)?.info; },
        root: rootOf,
        family(id) { return [...sessions.keys()].filter(candidate => sessions.get(candidate)?.info && rootOf(candidate) === rootOf(id)); },
        status(id) { return sessions.get(id)?.status ?? 'idle'; },
        permission: { list(id) { return sessions.get(id)?.permissions ?? []; } },
        form: { list(id) { return sessions.get(id)?.forms ?? []; } },
        pending: { list(id) { return sessions.get(id)?.pending ?? []; } },
        sync: unexpectedServerCall,
      },
      on(name, callback) { handlers.set(name, callback); return () => handlers.delete(name); },
    },
  });
  return {
    sessions, controls, titles, progress, timers, handlers, cleanup,
    navigate(next) { route = next; },
    tick() { for (const timer of timers.values()) timer.callback(); },
  };
}

test('IdleMainWithRunningChildShowsBusy', () => {
  const sessions = makeSessions();
  sessions.set('worker', { info: { title: 'Worker title', parentID: 'alpha' }, status: 'running' });
  const client = createClient({ sessions });
  assert.equal(client.titles.at(-1), 'Alpha conversation');
  assert.equal(client.progress.at(-1), osc('3;0'));
  client.cleanup();
});

test('ParallelChildrenKeepBusyUntilLastCompletion', () => {
  const client = createClient();
  for (const id of ['worker-one', 'worker-two']) client.sessions.set(id, { info: { parentID: 'alpha' }, status: 'running' });
  client.tick();
  assert.equal(client.progress.at(-1), osc('3;0'));
  const writes = client.progress.length;
  client.sessions.get('worker-one').status = 'idle';
  client.tick();
  assert.equal(client.progress.at(-1), osc('3;0'));
  assert.equal(client.progress.length, writes);
  client.sessions.get('worker-two').status = 'idle';
  client.tick();
  assert.equal(client.progress.at(-1), osc('0;0'));
  assert.equal(client.titles.at(-1), '✓ Alpha conversation');
  client.cleanup();
});

test('TwoClientsKeepIndependentFamilies', () => {
  const sessions = makeSessions();
  const alpha = createClient({ sessions });
  const beta = createClient({ sessionID: 'beta', sessions });
  sessions.set('beta-worker', { info: { parentID: 'beta' }, status: 'running' });
  alpha.tick(); beta.tick();
  assert.equal(alpha.titles.at(-1), '✓ Alpha conversation');
  assert.equal(alpha.progress.at(-1), osc('0;0'));
  assert.equal(beta.titles.at(-1), 'Beta conversation');
  assert.equal(beta.progress.at(-1), osc('3;0'));
  sessions.set('alpha-worker', { info: { parentID: 'alpha' }, status: 'running' });
  sessions.get('beta-worker').status = 'idle';
  alpha.tick(); beta.tick();
  assert.equal(alpha.progress.at(-1), osc('3;0'));
  assert.equal(beta.titles.at(-1), '✓ Beta conversation');
  assert.equal(beta.progress.at(-1), osc('0;0'));
  alpha.cleanup(); beta.cleanup();
});

test('ChildTitlesNeverReplaceConversationTitle', () => {
  const client = createClient();
  client.sessions.set('worker', { info: { title: 'Child', parentID: 'alpha' }, status: 'running' });
  client.tick();
  client.sessions.get('worker').info.title = 'Renamed child';
  client.tick();
  assert.equal(client.titles.at(-1), 'Alpha conversation');
  client.navigate({ type: 'session', sessionID: 'worker' });
  client.tick();
  assert.equal(client.titles.at(-1), 'Alpha conversation');
  client.cleanup();
});

test('NestedChildrenAndDelayedParentMetadataJoinTheRightFamily', () => {
  const client = createClient();
  client.sessions.set('grandchild', { info: { parentID: 'worker' }, status: 'running' });
  client.tick();
  assert.equal(client.progress.at(-1), osc('0;0'));
  client.sessions.set('worker', { info: { parentID: 'alpha' }, status: 'idle' });
  client.tick();
  assert.equal(client.progress.at(-1), osc('3;0'));
  assert.equal(client.titles.at(-1), 'Alpha conversation');
  client.cleanup();
});

test('DelayedChildMetadataDoesNotRequireAnotherEvent', () => {
  const client = createClient();
  client.sessions.set('worker', { status: 'running' });
  client.tick();
  assert.equal(client.progress.at(-1), osc('0;0'));
  client.sessions.get('worker').info = { parentID: 'alpha' };
  client.tick();
  assert.equal(client.progress.at(-1), osc('3;0'));
  assert.equal(client.controls.serverCalls, 0);
  client.cleanup();
});

test('LateSessionMetadataSeedsTitleAndRunningStatus', () => {
  const client = createClient({ sessionID: 'late', sessions: new Map() });
  assert.equal(client.titles.at(-1), '✓ opencode');
  client.sessions.set('late', { info: { title: 'Loaded conversation' }, status: 'running' });
  client.tick();
  assert.equal(client.titles.at(-1), 'Loaded conversation');
  assert.equal(client.progress.at(-1), osc('3;0'));
  client.cleanup();
});

test('MixedActivityAndQuestionsKeepSpinnerAndShowAttention', () => {
  const client = createClient();
  client.sessions.set('working', { info: { parentID: 'alpha' }, status: 'running' });
  client.sessions.set('waiting', { info: { parentID: 'alpha' }, status: 'running', forms: [{ id: 'question' }] });
  client.tick();
  assert.equal(client.progress.at(-1), osc('3;0'));
  assert.equal(client.titles.at(-1), '◉ Alpha conversation');
  const progressWrites = client.progress.length;
  client.sessions.get('waiting').forms = [];
  client.tick();
  assert.equal(client.titles.at(-1), 'Alpha conversation');
  assert.equal(client.progress.length, progressWrites, 'Attention-only changes do not resend native progress');
  client.sessions.get('waiting').forms = [{ id: 'question' }];
  client.tick();
  client.sessions.get('working').status = 'idle';
  client.tick();
  assert.equal(client.progress.at(-1), osc('4;50'));
  client.sessions.get('waiting').forms = [];
  client.tick();
  assert.equal(client.progress.at(-1), osc('3;0'));
  assert.equal(client.titles.at(-1), 'Alpha conversation');
  client.cleanup();
});

test('ParentIdleDoesNotStopChildAndChildIdleDoesNotStopParent', () => {
  const client = createClient();
  client.sessions.get('alpha').status = 'running';
  client.sessions.set('worker', { info: { parentID: 'alpha' }, status: 'running' });
  client.tick();
  client.sessions.get('alpha').status = 'idle';
  client.tick();
  assert.equal(client.progress.at(-1), osc('3;0'));
  client.sessions.get('alpha').status = 'running';
  client.sessions.get('worker').status = 'idle';
  client.tick();
  assert.equal(client.progress.at(-1), osc('3;0'));
  client.cleanup();
});

test('RealQueuedWorkCountsButSyntheticRemindersDoNot', () => {
  const client = createClient();
  client.sessions.set('worker', { info: { parentID: 'alpha' }, pending: [{ type: 'synthetic' }] });
  client.tick();
  assert.equal(client.progress.at(-1), osc('0;0'));
  for (const type of ['user', 'compaction']) {
    client.sessions.get('worker').pending = [{ type }];
    client.tick();
    assert.equal(client.progress.at(-1), osc('3;0'));
  }
  client.cleanup();
});

test('HistoricalChildFailureDoesNotLatchAnError', () => {
  const client = createClient();
  client.sessions.set('old-worker', { info: { parentID: 'alpha', outcome: 'failed' }, status: 'idle' });
  client.tick();
  assert.equal(client.titles.at(-1), '✓ Alpha conversation');
  assert.equal(client.progress.at(-1), osc('0;0'));
  client.cleanup();
});

test('RouteSwitchAndHomeClearPreviousFamilyActivity', () => {
  const client = createClient();
  client.sessions.set('worker', { info: { parentID: 'alpha' }, status: 'running' });
  client.tick();
  client.navigate({ type: 'session', sessionID: 'beta' });
  client.tick();
  assert.equal(client.titles.at(-1), '✓ Beta conversation');
  assert.equal(client.progress.at(-1), osc('0;0'));
  client.sessions.get('alpha').info.title = 'Unrelated rename';
  client.tick();
  assert.equal(client.titles.at(-1), '✓ Beta conversation');
  client.navigate({ type: 'home' });
  client.tick();
  assert.equal(client.titles.at(-1), '✓ opencode');
  assert.equal(client.progress.at(-1), osc('0;0'));
  client.cleanup();
});

test('RootFailureAndCancellationClearActivityCorrectly', () => {
  const client = createClient();
  client.sessions.get('alpha').info.outcome = 'failed';
  client.tick();
  assert.equal(client.titles.at(-1), '✗ Alpha conversation');
  assert.equal(client.progress.at(-1), osc('2;100'));
  client.sessions.get('alpha').status = 'running';
  client.tick();
  assert.equal(client.progress.at(-1), osc('3;0'));
  client.sessions.get('alpha').status = 'idle';
  client.sessions.get('alpha').info.outcome = 'interrupted';
  client.tick();
  assert.equal(client.progress.at(-1), osc('0;0'));
  client.cleanup();
});

test('PermissionRequestsPauseAndResumeWithoutAnotherSessionTakingOver', () => {
  const client = createClient();
  client.sessions.get('alpha').status = 'running';
  client.sessions.get('alpha').permissions = [{ id: 'permission' }];
  client.tick();
  assert.equal(client.titles.at(-1), '◉ Alpha conversation');
  assert.equal(client.progress.at(-1), osc('4;50'));
  client.sessions.get('alpha').permissions = [];
  client.tick();
  assert.equal(client.progress.at(-1), osc('3;0'));
  client.cleanup();
});

test('CacheChangesAreObservedWithoutEventSubscriptions', () => {
  const client = createClient();
  assert.equal(client.handlers.size, 0, 'Cache reconciliation does not depend on event delivery order');
  client.sessions.get('alpha').status = 'running';
  client.sessions.get('alpha').info.title = 'Renamed conversation';
  client.tick();
  assert.equal(client.titles.at(-1), 'Renamed conversation');
  assert.equal(client.progress.at(-1), osc('3;0'));
  client.cleanup();
});

test('UnchangedSnapshotsDoNotRewriteTitleOrProgressOrPollServer', () => {
  const client = createClient();
  const before = { titles: client.titles.length, progress: client.progress.length };
  for (let tick = 0; tick < 10; tick++) client.tick();
  assert.equal(client.titles.length, before.titles);
  assert.equal(client.progress.length, before.progress);
  assert.equal(client.controls.serverCalls, 0);
  assert.equal(client.timers.size, 1);
  assert.equal([...client.timers.values()][0].interval, 500);
  client.cleanup();
});

for (const [label, platform, environment, isTTY] of [
  ['NonWindows', 'linux', { WT_SESSION: 'fixture' }, true],
  ['OtherTerminal', 'win32', {}, true],
  ['RedirectedOutput', 'win32', { WT_SESSION: 'fixture' }, false],
]) test(`NativeProgressSkippedFor${label}`, () => {
  const client = createClient({ platform, environment, isTTY });
  client.sessions.get('alpha').status = 'running';
  client.tick();
  assert.equal(client.titles.at(-1), 'Alpha conversation');
  assert.equal(client.progress.length, 0);
  client.cleanup();
});

test('ConsoleOutputFailureDoesNotBreakTitleUpdates', () => {
  const client = createClient();
  client.controls.stdoutFailed = true;
  client.sessions.get('alpha').status = 'running';
  assert.doesNotThrow(() => client.tick());
  assert.equal(client.titles.at(-1), 'Alpha conversation');
  client.cleanup();
});

test('DisposalToleratesClosedRendererAndStopsQueuedCallbacks', () => {
  const client = createClient();
  const queued = [...client.timers.values()][0].callback;
  client.controls.rendererDisposed = true;
  assert.doesNotThrow(client.cleanup);
  assert.equal(client.timers.size, 0);
  assert.equal(client.handlers.size, 0);
  assert.equal(client.progress.at(-1), osc('0;0'));
  const writes = client.progress.length;
  client.sessions.get('alpha').status = 'running';
  assert.doesNotThrow(queued);
  assert.equal(client.progress.length, writes);
});

test('NormalDisposalResetsTitleAndProgress', () => {
  const client = createClient();
  client.cleanup();
  assert.equal(client.titles.at(-1), '');
  assert.equal(client.progress.at(-1), osc('0;0'));
  assert.equal(client.timers.size, 0);
});

test('RouterUnavailabilityAndLongTitlesAreHandled', () => {
  const client = createClient();
  client.controls.routerUnavailable = true;
  assert.doesNotThrow(() => client.tick());
  assert.equal(client.progress.at(-1), osc('0;0'));
  client.controls.routerUnavailable = false;
  client.sessions.get('alpha').info.title = 'A'.repeat(60);
  client.tick();
  assert.equal(client.titles.at(-1), '✓ ' + 'A'.repeat(37) + '...');
  client.cleanup();
});
