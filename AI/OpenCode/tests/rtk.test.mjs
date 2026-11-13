import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { posix, win32 } from 'node:path';
import { test } from 'node:test';
import vm from 'node:vm';

const source = stripTypeScriptTypes(readFileSync(new URL('../plugins/rtk/index.ts', import.meta.url), 'utf8'))
    .replace(/^import .+$/gm, '')
    .replace(/^export default .+$/gm, '')
    .replace(/^export \{.+$/gm, '')
    .replace(/^export /gm, '');

function createPlugin({ platform = 'linux', environment = { PATH: '/tools' }, files = ['/tools/rtk'], directories = [], responses = [] } = {}) {
    const calls = [];
    const hooks = [];
    const warnings = [];
    const availableFiles = new Set(files);
    const availableDirectories = new Set(directories);
    const paths = platform === 'win32' ? win32 : posix;
    const sandbox = {
        process: { platform, env: { ...environment } },
        delimiter: paths.delimiter,
        join: paths.join,
        existsSync: path => availableFiles.has(path) || availableDirectories.has(path),
        statSync: path => ({ isDirectory: () => availableDirectories.has(path) }),
        console: { warn: message => warnings.push(message) },
        execFile(binary, args, options, callback) {
            calls.push({ binary, args: [...args], options });
            const response = responses[calls.length - 1] ?? { stdout: '{"command":"rtk git status"}' };
            queueMicrotask(() => callback(response.error ?? null, response.stdout ?? ''));
        },
    };
    vm.runInNewContext(source + '\nglobalThis.api = { resolveRtkPath, probeRtkHookOpencode, runHookOpencode, tryRewriteCommand, plugin: RtkOpenCodePlugin };', sandbox);
    return {
        ...sandbox.api, calls, hooks, warnings, environment: sandbox.process.env, files: availableFiles,
        context: { tool: { async hook(name, callback) { hooks.push({ name, callback }); } } },
    };
}

test('RewritePassesCommandAndAgentAsSeparateArguments', async () => {
    const plugin = createPlugin({ responses: [{ stdout: '{"command":"  rtk git status  "}' }] });
    const command = 'git status; echo "literal argument"';
    assert.equal(await plugin.runHookOpencode('/tools/rtk', command, 'reviewer', 1250), 'rtk git status');
    assert.equal(plugin.calls[0].binary, '/tools/rtk');
    assert.deepEqual(plugin.calls[0].args, ['hook', 'opencode', '--agent', 'reviewer', command]);
    assert.equal(plugin.calls[0].options.timeout, 1250);
});

test('RewriteWithoutAgentOmitsAgentSwitch', async () => {
    const plugin = createPlugin();
    assert.equal(await plugin.runHookOpencode('/tools/rtk', 'git status'), 'rtk git status');
    assert.deepEqual(plugin.calls[0].args, ['hook', 'opencode', 'git status']);
});

for (const [label, stdout] of [
    ['InvalidJson', 'not json'],
    ['EmptyOutput', ''],
    ['MissingCommand', '{}'],
    ['NullResponse', 'null'],
    ['NonStringCommand', '{"command":42}'],
    ['BlankCommand', '{"command":"  "}'],
    ['UnchangedCommand', '{"command":"git status"}'],
]) test(`UnusableRewriteReturnsNullFor${label}`, async () => {
    const plugin = createPlugin({ responses: [{ stdout }] });
    assert.equal(await plugin.runHookOpencode('/tools/rtk', 'git status'), null);
});

for (const label of ['ProcessFailure', 'Timeout']) test(`RewriteReturnsNullOn${label}`, async () => {
    const error = Object.assign(new Error(label), { code: label === 'Timeout' ? 'ETIMEDOUT' : 1 });
    const plugin = createPlugin({ responses: [{ error, stdout: '{"command":"rtk git status"}' }] });
    assert.equal(await plugin.runHookOpencode('/tools/rtk', 'git status'), null);
});

test('NonShellAndInvalidInputsDoNotInvokeRtk', async () => {
    const plugin = createPlugin();
    for (const [tool, command] of [['read', 'git status'], ['shell', ''], ['shell', '  '], ['shell', null], ['shell', 42]]) {
        assert.equal(await plugin.tryRewriteCommand(tool, command), null);
    }
    assert.equal(plugin.calls.length, 0);
});

test('DisabledRtkDoesNotInvokeProcess', async () => {
    const plugin = createPlugin({ environment: { PATH: '/tools', RTK_DISABLED: '1' } });
    assert.equal(await plugin.tryRewriteCommand('shell', 'git status'), null);
    assert.equal(plugin.calls.length, 0);
});

test('MissingRtkLeavesCommandUnchanged', async () => {
    const plugin = createPlugin({ files: [] });
    assert.equal(await plugin.tryRewriteCommand('shell', 'git status'), null);
    assert.equal(plugin.calls.length, 0);
});

test('PathDiscoverySkipsDirectoriesAndRecoversAfterCachedFileDisappears', () => {
    const plugin = createPlugin({
        environment: { PATH: '/directory:/first:/second' },
        files: ['/first/rtk', '/second/rtk'], directories: ['/directory/rtk'],
    });
    assert.equal(plugin.resolveRtkPath(), '/first/rtk');
    plugin.files.delete('/first/rtk');
    assert.equal(plugin.resolveRtkPath(), '/second/rtk');
});

test('WindowsPathFallbackAndExecutableExtensionsAreUsed', () => {
    const plugin = createPlugin({
        platform: 'win32', environment: { Path: 'C:\\tools;C:\\fallback', PATHEXT: '.EXE;.CMD' },
        files: ['C:\\tools\\rtk.CMD', 'C:\\fallback\\rtk.EXE'],
    });
    assert.equal(plugin.resolveRtkPath(), 'C:\\tools\\rtk.CMD');
});

test('SuccessfulCapabilityProbeIsCached', async () => {
    const plugin = createPlugin();
    assert.equal(await plugin.probeRtkHookOpencode('/tools/rtk'), true);
    assert.equal(await plugin.probeRtkHookOpencode('/tools/rtk'), true);
    assert.equal(plugin.calls.length, 1);
    assert.deepEqual(plugin.calls[0].args, ['hook', 'opencode', '--help']);
});

test('FailedCapabilityProbeCanBeRetried', async () => {
    const plugin = createPlugin({ responses: [{ error: new Error('unavailable') }, { stdout: '' }] });
    assert.equal(await plugin.probeRtkHookOpencode('/tools/rtk'), false);
    assert.equal(await plugin.probeRtkHookOpencode('/tools/rtk'), true);
    assert.equal(plugin.calls.length, 2);
});

test('SetupRegistersHookAndMutatesOnlyShellCommand', async () => {
    const plugin = createPlugin();
    await plugin.plugin.setup(plugin.context);
    assert.equal(plugin.hooks.length, 1);
    assert.equal(plugin.hooks[0].name, 'execute.before');
    const readInput = { command: 'git status' };
    await plugin.hooks[0].callback({ tool: 'read', input: readInput });
    assert.equal(readInput.command, 'git status');
    assert.equal(plugin.calls.length, 1);
    const shellInput = { command: 'git status', directory: '/fixture' };
    await plugin.hooks[0].callback({ tool: 'shell', input: shellInput, agent: 'build' });
    assert.deepEqual(shellInput, { command: 'rtk git status', directory: '/fixture' });
    assert.deepEqual(plugin.calls[1].args, ['hook', 'opencode', '--agent', 'build', 'git status']);
});

test('SetupDoesNotRegisterHookWithoutRtk', async () => {
    const plugin = createPlugin({ files: [] });
    await plugin.plugin.setup(plugin.context);
    assert.equal(plugin.hooks.length, 0);
    assert.equal(plugin.calls.length, 0);
    assert.equal(plugin.warnings.length, 1);
});

test('SetupDoesNotRegisterHookForUnsupportedBinary', async () => {
    const plugin = createPlugin({ responses: [{ error: new Error('unsupported') }] });
    await plugin.plugin.setup(plugin.context);
    assert.equal(plugin.hooks.length, 0);
    assert.equal(plugin.calls.length, 1);
    assert.equal(plugin.warnings.length, 1);
});
