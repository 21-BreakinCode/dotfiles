// Branch Jira: a sidebar for the current checkout and its Jira issues.
// The methods are built from separate files, so a method used here may live in:
//   state/saved.js        filters, the open issue and tabs across reloads
//   jira/discovery.js     which issues this copy is looking at
//   jira/reads.js         loading lists and issues through the helper
//   actions/changes.js    comments
//   actions/agents.js     who is on an issue, and handing work to them
//   actions/worktrees.js  starting work: an issue's checkouts
//   actions/menus.js      the popup menus
//   views/list.js, detail.js, comments.js, worktrees.js   the drawing
// jira/model.js says what the helper's answers mean; views/ui.js holds every look.
// Git runs on the checkout's machine. Jira requests go through a local helper that
// reads JIRA_BASE_URL, JIRA_EMAIL and JIRA_API_TOKEN; the mod never sees the token.
import { View } from "gpui-kit";
import { InputState, TextareaState } from "gpui-base";
import { spaces, panes, nextCommand, layout, shared } from "herdr";
import { loadSettings, duration } from "./settings.js";
import { savedMethods } from "./state/saved.js";
import { discoveryMethods } from "./jira/discovery.js";
import { readMethods } from "./jira/reads.js";
import { changeMethods } from "./actions/changes.js";
import { agentMethods } from "./actions/agents.js";
import { worktreeMethods } from "./actions/worktrees.js";
import { menuMethods } from "./actions/menus.js";
import { listMethods } from "./views/list.js";
import { detailMethods } from "./views/detail.js";
import { commentMethods } from "./views/comments.js";
import { worktreeViewMethods } from "./views/worktrees.js";
import { keyProblem, panelShown } from "./jira/model.js";
import { Busy, Panel } from "./views/ui.js";

const CONTEXT_POLL_MS = 1000;
const REFRESH_INTERVAL_MS = 60000;
const FIRST_LOAD_LIMIT_MS = 30000;
const NOTICE_MS = 5000;
// Better Search asks for one by shared `branch-jira.open`, { space, identifier, at }; older asks are let go.
const ASK_MS = 10000;
const ASK_POLL_MS = 100;
// Preferences a person may change in the installed mod.json under `settings`.
const DEFAULT_SETTINGS = {
  refresh: { every: "60s", search_debounce: "450ms" },
  branch: { max_identifiers: 4 },
  // The panel shows my issues on this Jira board, through the board's own filter.
  board: { name: "CR Kanban" },
  worktrees: { root: "~/.herdr/worktrees", open_with: "terminal" },
};

function activeSpace() {
  const sp = spaces().find((s) => s.active);
  if (!sp) return null;
  const tab = sp.tabs?.find((t) => t.active)?.id;
  const candidates = panes().filter((p) => p.tab === tab && p.cwd);
  const current = candidates.find((p) => p.focused) ?? candidates[0];
  return { ...sp, folder: current?.cwd ?? sp.folder, branch: current?.branch ?? sp.branch };
}

function spaceContextKey(space) {
  if (!space) return "";
  return `${space.machine ?? "local"}:${space.id}:${space.folder}:${space.branch ?? ""}`;
}

class JiraIssues extends View {
  init(_props, cx) {
    this.view = "all"; // the Branch tab was removed; status groups in All are the view
    this.reopenSaved = true;
    // v2: groups are status categories now; the old per-status keys are dropped.
    localStorage.removeItem("closed-groups");
    this.closedGroups = new Set(this.readStoredList("closed-groups:v2"));
    this.branchIssues = [];
    this.items = [];
    this.cache = {};
    this.listToken = 0;
    this.detailToken = 0;
    this.branchToken = 0;
    this.searchToken = 0;

    this.menuFocus = cx.focus_handle();

    this.settings = DEFAULT_SETTINGS;
    this.settingsProblems = [];
    this.section = "overview";
    this.search = InputState.new({ placeholder: "Search · CR-123 or text" });
    this.search.on("change", (_e, cx) => {
      if (!this.restoringSearch) this.searchChanged(cx);
    });
    this.linkInput = InputState.new({ placeholder: "CR-123" });
    this.linkInput.on("submit", (_e, cx) => this.linkIssue(cx));
    this.editor = TextareaState.new({ placeholder: "Write a comment…", rows: 4 });
    this.editor.on("change", (_e, cx) => {
      if (this.draftKey) localStorage.setItem(this.draftKey, this.editor.value());
      cx.notify();
    });
    // Its own state, so a new comment stays put while a handoff is being written.
    this.newComment = TextareaState.new({ placeholder: "Write a comment…", rows: 4 });
    this.newComment.on("change", (_e, cx) => {
      if (this.commentKey) localStorage.setItem(this.commentKey, this.newComment.value());
      cx.notify();
    });
    this.startPolling(cx);
    this.listenForCommands(cx);
    this.applySettings(cx);
  }

  // Read the installed mod.json once; list defaults apply until a saved view exists.
  applySettings(cx) {
    cx.spawn(async (cx) => {
      const { settings, problems } = await loadSettings("branch-jira", DEFAULT_SETTINGS);
      this.settings = settings;
      this.settingsProblems = problems;
      this.settingsReady = true;
      const sp = activeSpace();
      this.changeSpace(sp, spaceContextKey(sp), cx);
      cx.notify();
    });
  }

  // Better Search's ask, looked for often so the panel turns to it at once.
  takeAsk(cx) {
    const ask = shared("branch-jira.open");
    if (!ask || ask.at <= (this.askedAt ?? 0)) return;
    // Follow the space first, as the slower look does, so it can't cancel this load after.
    const sp = activeSpace();
    const key = spaceContextKey(sp);
    if (key !== this.spaceKey) this.changeSpace(sp, key, cx);
    // A write in progress finishes first; the ask waits for the next look.
    if (ask?.identifier && ask.space === sp?.id && ask.at > (this.askedAt ?? 0) && Date.now() - ask.at < ASK_MS && !this.mutating) {
      this.askedAt = ask.at;
      // What was open last time mustn't replace what was asked for when the list loads.
      this.reopenSaved = false;
      this.restoreSelection = null;
      // As a click in the list does: what was open goes, and the loading line shows until it's here.
      if (this.issue) this.rememberView();
      this.issue = null;
      this.composer = null;
      this.notice = null;
      this.opening = { identifier: ask.identifier };
      this.openIssue(ask.identifier, cx);
      cx.notify();
    }
  }

  startPolling(cx) {
    cx.timer.every(ASK_POLL_MS, (cx) => this.takeAsk(cx));
    cx.timer.every(CONTEXT_POLL_MS, (cx) => {
      if (!this.settingsReady) return;
      const sp = activeSpace();
      const key = spaceContextKey(sp);
      const interval = duration(this.settings.refresh.every, REFRESH_INTERVAL_MS);
      // A read that never answers mustn't leave the tabs locked; the helper itself
      // gives up after 26 seconds.
      if (Date.now() - this.contextSince > FIRST_LOAD_LIMIT_MS) {
        this.listLoaded = true;
        this.branchLoaded = true;
      }
      // A confirmation says its piece and goes; an error stays until it's dealt with.
      if (this.notice !== this.noticeShown) {
        this.noticeShown = this.notice;
        this.noticeSince = Date.now();
      } else if (this.notice && Date.now() - this.noticeSince > NOTICE_MS) {
        this.notice = null;
        cx.notify();
      }
      if (key !== this.spaceKey) this.changeSpace(sp, key, cx);
      this.rememberView();
      const minute = Math.floor(Date.now() / 60000);
      if (minute !== this.updatedMinute && this.lastUpdated) {
        this.updatedMinute = minute;
        cx.notify();
      }
      const due = Date.now() - (this.refreshed ?? 0) > interval;
      // Coming back to a hidden panel makes it due at once, if it's been a while.
      if (!this.busy && !this.mutating && due && panelShown(layout(), "branch-jira"))
        this.refresh(cx);
    });
  }

  listenForCommands(cx) {
    cx.spawn(async (cx) => {
      for (;;) {
        const command = await nextCommand();
        if (command === "refresh" && this.settingsReady) this.refresh(cx);
        cx.notify();
      }
    });
  }

  get busy() {
    return this.branchLoading || this.searchPending || this.loading || this.detailLoading;
  }

  render() {
    const root = Panel({ id: "issue-root" });
    if (!this.settingsReady) return root.child(Busy("Loading issue settings…"));
    const problem = keyProblem(this.error);
    if (problem) return this.renderKeyProblem(root, problem);
    if (this.issue) return this.renderDetail(root);
    return this.opening ? this.renderOpening(root) : this.renderList(root);
  }
}

Object.assign(
  JiraIssues.prototype,
  savedMethods,
  discoveryMethods,
  readMethods,
  changeMethods,
  agentMethods,
  worktreeMethods,
  menuMethods,
  listMethods,
  detailMethods,
  commentMethods,
  worktreeViewMethods,
);

export default JiraIssues;
