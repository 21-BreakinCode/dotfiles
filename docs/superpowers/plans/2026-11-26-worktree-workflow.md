# Worktree Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One `wt` script decides where every git worktree goes. Claude Code hooks send its worktree feature through `wt` and keep edits off the main checkout's default branch. Cleanup removes merged worktrees safely.

**Architecture:** `wt` (bash, subcommands) owns all worktree creation and removal. `worktree-guard.sh` (bash) owns the `UserPromptSubmit` hint and the `PreToolUse` deny. `settings.base.json` wires both into Claude Code. A plain bash test file exercises both against throwaway repos with a bare `origin`.

**Tech Stack:** bash, git 2.56, jq, perl (for the Unicode slug), gh (optional), hc (optional).

**Spec:** `docs/superpowers/specs/2026-11-26-worktree-workflow-design.md`

## Global Constraints

- Root folder: `.worktrees.directory` in `~/.config/herdr-app/settings.json`, fallback `~/.herdr/worktrees`. A leading `~` expands to `$HOME`.
- Path: `<root>/<repo>/<slug(branch)>`, `<repo>` = basename of the main checkout from `git rev-parse --path-format=absolute --git-common-dir` (strip `/.git`).
- `slug()` must match `~/.config/herdr-app/mods/worktree/main.js:30-38` exactly (NFC. Runs of chars outside `\p{L}\p{M}\p{N}._-` → one `-`. Trim `-` both ends. Empty → `branch-<FNV-1a 32-bit over code points, 8 lowercase hex>`).
- New branches start from `HEAD`. Record `git config branch.<branch>.wtBase <sha>`.
- Hook stdout for `WorktreeCreate`: the absolute path as the last non-empty line. All git output to stderr.
- Guard errors allow the call (exit 0, no output). Never block on its own failure.
- Override phrase: `on main` (case-insensitive) in the prompt.
- Cache dir: `~/.cache/wt` (`active/<session_id>`, `override-<session_id>`, `pending/<repo>.json`, `shown-<session_id>`, `prune.log`). Locks older than 7 days do not count.
- Test seams (env): `WT_HERDR_SETTINGS` (default `~/.config/herdr-app/settings.json`), `WT_CACHE` (default `~/.cache/wt`). `gh` and `hc` are found on `PATH`, so tests stub them.
- No commits. The person decides about commits.

## Review Focus

- A branch name with `/`, spaces or only symbols (`feat/x`, `fix login`, `###`): path must equal Herdr's. Test in Task 1.
- Prune on a repo with no `origin` or no `origin/HEAD`: must do nothing, not guess. Test in Task 2.
- A worktree made outside `wt` (no `wtBase`) whose tip is already in `origin/main`: must not be removed by signal A. Test in Task 2.
- A Bash command that only mentions the words, for example `echo "git worktree add"` or `grep 'git commit'`: deny is acceptable (documented limit), but `git commit` inside a worktree must be allowed. Test in Task 3.
- Guard called outside any git repo or with malformed JSON: exit 0, no output. Test in Task 3.

---

### Task 1: `wt` core (path, new, create/remove hooks, locks)

**Files:**
- Create: `config/claude/scripts/wt` (executable)
- Create: `config/claude/scripts/tests/wt-test.sh` (executable)

**Interfaces:**
- Produces (CLI): `wt new <branch>` → stdout last line = abs path. Exit 1 with message on stderr outside a repo or without a branch.
- `wt path <branch>` → prints the path without creating (used by tests and the parity check).
- `wt hook-create` (stdin `{name, cwd, session_id}`) → same as `new` run in `cwd`. Writes `$WT_CACHE/active/<session_id>` containing the path.
- `wt hook-remove` (stdin `{worktree_path, session_id}`) → `git worktree remove` (no `--force`). Then it deletes the branch in two cases only: it is merged (Task 2's `is_merged`), or its tip equals `wtBase`. Deletes the session lock.
- `wt hook-session-end` (stdin `{session_id}`) → deletes `$WT_CACHE/active/<session_id>` and `override-<session_id>` and `shown-<session_id>`.
- Internal functions later tasks reuse: `wt_root`, `repo_main <dir>`, `repo_name <dir>`, `slug <branch>`.
- Test helpers in `wt-test.sh` that Tasks 2–3 reuse: `make_repo` (prints a temp main checkout with a bare `origin`, `origin/HEAD` → `main`, one commit pushed), `assert_eq <expected> <actual> <label>`, `assert_ok <label> <cmd...>`, `assert_fails <label> <cmd...>`. Each test runs with `WT_HERDR_SETTINGS` pointing to a temp settings file whose root is a temp dir, and `WT_CACHE` in a temp dir.

- [ ] **Step 1: Write the failing tests** in `wt-test.sh`:
  - `test_path_slug`: `wt path feat/login-oauth` = `$ROOT/<repo>/feat-login-oauth`. `wt path "fix login"` ends `/fix-login`. `wt path "-a--b-"` ends `/a--b`. `wt path "###"` ends `/branch-` + 8 hex.
  - `test_slug_parity_with_herdr`: branches `feat/x`, `fix login`, `###`, `é/ü`, `a__b..c`. For each, compare `basename "$(wt path "$b")"` with the JS `slug` from `main.js:30-38`, run in `node -e`. If `node` is missing, print a skip message.
  - `test_new_creates_branch_from_head`: `wt new feat/a` last line is the path, the dir exists, `git -C path branch --show-current` = `feat/a`, `git config branch.feat/a.wtBase` = main's `HEAD` sha.
  - `test_new_reuses_existing_branch`: create branch `feat/b` with one commit, `wt new feat/b` checks it out and sets no `wtBase`.
  - `test_new_is_idempotent`: second `wt new feat/a` prints the same path, exit 0.
  - `test_root_fallback`: settings file without `worktrees` → root is `$HOME/.herdr/worktrees` (only `wt path`, nothing created).
  - `test_hook_create_last_line_and_lock`: `echo '{"name":"feat/c","cwd":"'$REPO'","session_id":"s1"}' | wt hook-create` → last non-empty stdout line is the path, it is the only stdout line, `$WT_CACHE/active/s1` contains the path.
  - `test_hook_remove_keeps_branch_with_work`: worktree with one new commit, `hook-remove` removes the dir, branch still exists.
  - `test_hook_remove_deletes_empty_branch`: fresh `wt new feat/e`, `hook-remove` removes dir and branch, and lock `s1` is gone.
  - `test_hook_remove_refuses_dirty`: untracked file in worktree → exit non-zero, dir still exists.
- [ ] **Step 2: Run** `config/claude/scripts/tests/wt-test.sh` → every test FAILs (`wt: not found` or similar).
- [ ] **Step 3: Implement `wt`** with `set -euo pipefail`, a `case "$1"` dispatcher, and the functions above. `slug` runs one `perl -CSA -MUnicode::Normalize` command (NFC, the regex, trim, FNV-1a with `& 0xffffffff`). `hook-remove` calls `is_merged` from Task 2, so define a stub `is_merged() { return 1; }` now. Task 2 replaces it. Keep each function under 50 lines.
- [ ] **Step 4: Run** `wt-test.sh` → all Task 1 tests PASS.

### Task 2: `wt prune` (merged detection, skips, ignored files)

**Files:**
- Modify: `config/claude/scripts/wt`
- Modify: `config/claude/scripts/tests/wt-test.sh`

**Interfaces:**
- Consumes: Task 1 functions and test helpers.
- Produces: `wt prune [--auto] [repo]`, `wt prune --confirm <path>`, `wt prune --keep <path>`. Internal `default_branch <repo>` (prune variant: `origin/HEAD` only, one `git remote set-head origin --auto` attempt, else return 1) and `is_merged <repo> <branch> <default>` (A or B per spec).
- Pending file `$WT_CACHE/pending/<repo>.json`: `[{"path": str, "branch": str, "ignored": [str]}]`.
- `--auto` prints one line: `wt prune: removed N, pending M, kept K` and appends details to `$WT_CACHE/prune.log`.

- [ ] **Step 1: Write the failing tests** (stub `gh` and `hc` as scripts in a temp `bin/` placed first on `PATH`. Default stubs: `hc ls --json` prints `{"terminals":[]}`, `gh` exits 1):
  - `test_prune_removes_merged_ancestor`: `wt new feat/m`, commit, push to origin, merge into main with `--no-ff`, push main. `wt prune` → dir and branch gone, `wtBase` unset.
  - `test_prune_keeps_empty_branch`: fresh `wt new feat/empty` → kept.
  - `test_prune_keeps_no_wtbase_without_gh`: `git worktree add` by hand (no `wtBase`), branch tip already in `origin/main` → kept.
  - `test_prune_squash_via_gh`: branch with a commit, not an ancestor of main. `gh` stub prints `[{"headRefOid":"<tip>"}]` for `pr list --head feat/s` → removed. Same with a different oid → kept.
  - `test_prune_keeps_dirty`: untracked file → kept.
  - `test_prune_keeps_locked`: fresh lock in `active/` → kept.
  - `test_prune_ignores_stale_lock`: lock set 8 days back with `touch -t` → removed.
  - `test_prune_keeps_live_terminal`: `hc` stub reports a terminal whose `cwd` is a worktree subfolder → kept.
  - `test_prune_keeps_wtkeep`: `git config branch.feat/k.wtKeep true` → kept.
  - `test_prune_no_origin_head`: repo whose `origin` has no `HEAD` set and `set-head --auto` fails (origin URL to a missing path) → exit 0, nothing removed, message on stderr.
  - `test_prune_ignored_goes_pending`: merged worktree with ignored `.env` (add `.env` to `.gitignore`) → dir stays, pending file has the entry with `".env"` in `ignored`.
  - `test_prune_confirm_and_keep`: after the pending case, `wt prune --confirm <path>` removes it and the pending entry. On another pending worktree `wt prune --keep <path>` sets `wtKeep` and drops the entry.
  - `test_prune_confirm_refuses_unmerged`: `--confirm` on an unmerged worktree → exit non-zero, dir stays.
  - `test_hook_remove_deletes_merged_branch`: replaces the Task 1 stub path: merged branch with commits → `hook-remove` deletes the branch.
- [ ] **Step 2: Run** `wt-test.sh` → the new tests FAIL.
- [ ] **Step 3: Implement** `default_branch`, `is_merged` (replace the stub), `prune`, `--confirm`, `--keep`. `prune` runs `git fetch --prune origin` once, reads `git worktree list --porcelain`, and only considers paths under `<root>/<repo>/`. Signal B: one `gh pr list --state merged --limit 200 --json headRefName,headRefOid` per repo (builder's call from the spec). If `gh` fails, skip signal B. Ignored list: `git -C <wt> status --porcelain --ignored=matching | sed -n 's/^!! //p'`.
- [ ] **Step 4: Run** `wt-test.sh` → all tests PASS.

### Task 3: `worktree-guard.sh`

**Files:**
- Create: `config/claude/scripts/worktree-guard.sh` (executable)
- Modify: `config/claude/scripts/tests/wt-test.sh`

**Interfaces:**
- Consumes: `wt` on the same folder (`"$(dirname "$0")/wt"`) only to read pending files' location (`WT_CACHE`). No other calls.
- Produces: `worktree-guard.sh prompt` (stdin UserPromptSubmit JSON) and `worktree-guard.sh tool` (stdin PreToolUse JSON). Output is the hook JSON from the spec, or nothing.
- Guard default branch, first match wins: `origin/HEAD`, `git config init.defaultBranch`, an existing `main`, then `master`.

- [ ] **Step 1: Write the failing tests** (pipe JSON into the guard, parse output with `jq`):
  - `test_guard_prompt_hint_on_main`: protected `cwd` → `.hookSpecificOutput.additionalContext` contains `EnterWorktree`.
  - `test_guard_prompt_override`: prompt `"quick typo fix on main"` → no output, `$WT_CACHE/override-s1` exists.
  - `test_guard_prompt_silent_in_worktree` and `test_guard_prompt_silent_on_feature_branch` (main checkout on `feat/x`) → no output.
  - `test_guard_prompt_pending_once`: pending file for the repo exists → first call's context lists the path, branch and ignored files and mentions `wt prune --confirm` and `--keep`. Second call with the same `session_id` omits them.
  - `test_guard_denies_edit_on_main`: `{"tool_name":"Edit","tool_input":{"file_path":"$REPO/a.txt"},"cwd":"$REPO","session_id":"s1"}` → `permissionDecision` = `deny`, reason contains `EnterWorktree`. Same for `Write`, `MultiEdit`, and `NotebookEdit` with `notebook_path`.
  - `test_guard_allows_edit_with_override`, `test_guard_allows_edit_in_worktree`, `test_guard_allows_edit_outside_repo_file` (file under `/tmp`).
  - `test_guard_denies_git_worktree_add` in any `cwd`, including a worktree. Reason contains `wt new`.
  - `test_guard_denies_commit_on_main` and `test_guard_allows_commit_in_worktree`.
  - `test_guard_fail_open`: `cwd` = `/`, and also input `not json` → exit 0, no output.
  - `test_guard_speed`: 20 runs of each mode in a test repo. Average under 200 ms (use `date +%s%N` via `perl -MTime::HiRes`).
- [ ] **Step 2: Run** `wt-test.sh` → guard tests FAIL.
- [ ] **Step 3: Implement** `worktree-guard.sh`: top `trap 'exit 0' ERR`. Read stdin once. `jq` extracts fields. "protected" check per Global Constraints and spec. Bash match with `grep -Eq '(^|[;&|[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?worktree[[:space:]]+(add|remove)'` and the same shape for `commit`.
- [ ] **Step 4: Run** `wt-test.sh` → all tests PASS.

### Task 4: Wiring (settings, PATH link, rule line)

**Files:**
- Modify: `config/claude/settings.base.json` (`.hooks`)
- Modify: `bootstrap.sh:59` (add one `link` line after `config/claude/scripts`)
- Modify: `config/claude/rules/git-workflow.md` (append a `## Worktrees` section with the spec's rule line)

**Interfaces:**
- Consumes: the four entry points from Tasks 1–3 at `~/.claude/scripts/wt` and `~/.claude/scripts/worktree-guard.sh` (that folder is already linked to `config/claude/scripts`).

- [ ] **Step 1: Edit `settings.base.json`** so `.hooks` has: the existing `SessionStart` entry plus a second one running `nohup ~/.claude/scripts/wt prune --auto >>~/.cache/wt/prune.log 2>&1 &` (`timeout` 5). `SessionEnd` → `~/.claude/scripts/wt hook-session-end` (`timeout` 5). `WorktreeCreate` → `wt hook-create` (`timeout` 120). `WorktreeRemove` → `wt hook-remove` (`timeout` 60). `UserPromptSubmit` → `worktree-guard.sh prompt` (`timeout` 5). `PreToolUse` with `"matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash"` → `worktree-guard.sh tool` (`timeout` 5).
- [ ] **Step 2: Make sure that** `jq -e '.hooks | (.SessionStart|length)==2 and has("WorktreeCreate") and has("WorktreeRemove") and has("SessionEnd") and has("UserPromptSubmit") and has("PreToolUse")' config/claude/settings.base.json` → `true`.
- [ ] **Step 3: Add** `link "config/claude/scripts/wt"               "~/.local/bin/wt"` to `bootstrap.sh`, and the rule section to `git-workflow.md`. Make sure that `bash -n bootstrap.sh` prints no output.
- [ ] **Step 4: Stop and ask the person** before running `bootstrap.sh` or merging into `~/.claude/settings.json`, because it changes their live setup (CLAUDE.md Core Principle 2). Running it is not needed for Task 5.

### Task 5: Live verification (spec success criteria 2–5)

**Files:** none changed. Work in the scratchpad.

- [ ] **Step 1:** Make a throwaway repo with a bare `origin`. Reuse `make_repo` from `wt-test.sh` (source it with a `--lib` guard), or repeat its 6 commands. From inside the repo, run:
  `claude -p --settings <dotfiles>/config/claude/settings.base.json --dangerously-skip-permissions "Edit README.md to add a line 'x'. Report any tool error verbatim." < /dev/null`
  Expected: output reports a denial whose reason mentions EnterWorktree, or Claude calls EnterWorktree first. Either one passes criterion 3, as long as `README.md` in the main checkout is unchanged (`git status --porcelain` empty).
- [ ] **Step 2:** Same repo: `claude -p ... "Call EnterWorktree with name 'feat/live-check', then run pwd."` Expected: `pwd` = `~/Projects/worktrees/<repo>/feat-live-check` (criterion 2).
- [ ] **Step 3:** Criterion 5: compare `wt path feat/live-check` with the Herdr mod's path for the same branch (Task 1's parity test already covers the slug. Here, make sure that the root matches by reading `jq -r .worktrees.directory ~/.config/herdr-app/settings.json`).
- [ ] **Step 4:** Criterion 4: `wt-test.sh` `test_guard_speed` result.
- [ ] **Step 5:** Clean up: `wt hook-remove` the live worktree (or `git worktree remove --force`), delete the scratch repo and `~/.config/.../worktrees/<scratch repo>` folder. Report results to the person with the evidence lines.
