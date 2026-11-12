// Based on sorenjuul/opencode-tui-status-indicator at 8bb2a777597aa33ceb6459a22b4684e33a8296b6; see LICENSE.
// Local modifications AI-assisted with OpenCode.
import { Plugin } from "@opencode/plugin/tui";

const CACHE_POLL_INTERVAL = 500;
const DEFAULT_TITLE = "opencode";

type Status = "busy" | "idle" | "error" | "permission";

export default Plugin.define({
  id: "opencode-tui-status-indicator",
  setup(context) {
    const { renderer, data } = context;
    let disposed = false;
    let lastTitle: string | undefined;
    let lastStatus: Status | undefined;

    function currentSessionID(): string | undefined {
      try {
        const route = context.ui.router.current();
        return route.type === "session" ? route.sessionID : undefined;
      } catch {
        return undefined;
      }
    }

    function reportNativeProgress(status: Status) {
      const supportsProgress = (process.platform === "win32" && !!process.env.WT_SESSION) || process.env.TERM_PROGRAM === "WezTerm";
      if (!supportsProgress || !process.stdout.isTTY) return;
      const progress = {
        busy: "3;0",
        idle: "0;0",
        error: "2;100",
        permission: "4;50",
      }[status];
      try {
        process.stdout.write(`\x1b]9;4;${progress}\x07`);
      } catch {
        // A terminal output failure must not interrupt the agent or cleanup.
      }
    }

    function refresh() {
      if (disposed) return;
      const visibleID = currentSessionID();
      const rootID = visibleID === undefined ? undefined : data.session.root(visibleID);
      const root = rootID === undefined ? undefined : data.session.get(rootID);
      const members = visibleID === undefined || rootID === undefined
        ? []
        : [...new Set([rootID, visibleID, ...data.session.family(rootID)])];
      let busy = false;
      let attention = false;

      for (const sessionID of members) {
        const waiting = (data.session.permission.list(sessionID)?.length ?? 0) > 0 ||
          (data.session.form.list(sessionID)?.length ?? 0) > 0;
        if (waiting) {
          attention = true;
          continue;
        }
        busy ||= data.session.status(sessionID) === "running" ||
          data.session.pending.list(sessionID).some((item) => item.type !== "synthetic");
      }

      // Old failed workers must not leave the whole conversation permanently red.
      const status: Status = busy ? "busy" : attention ? "permission" : root?.outcome === "failed" ? "error" : "idle";
      const title = root?.title || DEFAULT_TITLE;
      const truncated = title.length > 40 ? title.slice(0, 37) + "..." : title;
      const marker = attention ? "◉ " : status === "error" ? "✗ " : status === "idle" ? "✓ " : "";
      const renderedTitle = marker + truncated;

      if (status !== lastStatus) {
        reportNativeProgress(status);
        lastStatus = status;
      }
      if (renderedTitle !== lastTitle) {
        try {
          renderer.setTerminalTitle(renderedTitle);
          lastTitle = renderedTitle;
        } catch {
          // Renderer shutdown can precede plugin disposal.
        }
      }
    }

    // Read only the local cache. This also handles delayed hydration and event/cache races.
    refresh();
    const timer = setInterval(refresh, CACHE_POLL_INTERVAL);
    return () => {
      disposed = true;
      clearInterval(timer);
      reportNativeProgress("idle");
      try {
        renderer.setTerminalTitle("");
      } catch {
        // The native session can already be closing or disposed on /exit.
      }
    };
  },
});
