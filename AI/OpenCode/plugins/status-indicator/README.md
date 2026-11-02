# Windows Terminal activity indicator

Based on `sorenjuul/opencode-tui-status-indicator`, commit
`8bb2a777597aa33ceb6459a22b4684e33a8296b6`. The upstream MIT license is included.

Local changes (AI-assisted with OpenCode):

- Native Windows Terminal tab/taskbar activity via OSC 9;4 in the TUI process.
- No redundant Braille animation in the title; static ready/waiting/error markers remain.
- Tolerate an already-closed renderer during disposal.
- Keep the title tied to the displayed conversation's root, while aggregating work across that root and its known descendants. Other conversation families remain isolated.
- Reconcile status from cached session/permission/form/pending data on startup and every 500 ms, including after navigation and delayed metadata hydration. No extra server or model polling is performed.
- Keep native progress busy until the last working family member stops. A simultaneous input request adds a static `◉` title marker; with no non-blocked work left, native progress changes to paused.

This is a local maintenance responsibility until an upstream release includes these changes.
An upstream contribution remains on the migration task list.

Load the directory only through the user's `cli.json` `plugins` list; it has no server entrypoint.
Keep `terminal.title: false` to avoid competing title writers.

Each client tracks the root and family of its currently displayed session. Viewing a worker
therefore retains the root conversation title. Known nested descendants are included. Missing
metadata is not guessed; OpenCode's normal cache hydration must establish the parent chain.
Once it arrives, the next cache check picks it up without another lifecycle event.

Unchanged snapshots do not resend title/progress output. Real queued work counts as activity;
synthetic reminder inputs do not. Error state follows the root's outcome, not arbitrary historical
worker failures. Very short activity between two checks may not appear in the terminal indicator.

The offline tests use `node:test` and independent cache fixtures, not real agents or network
calls. They cover parallel workers, delayed parent metadata, mixed input/work states, distinct
conversation families, navigation, output failure and disposal. Run
`node AI/OpenCode/tests/status-indicator.test.mjs` from the repository root.

Real Windows Terminal background-agent/multi-tab behavior still needs a visual acceptance check
after changes. No PSMux forwarding is implemented here.
