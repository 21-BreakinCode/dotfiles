# Worktree workflow design

Date: 2026-11-26

## Intent

Every agent's feature work lands in its own git worktree under one folder,
`<worktrees.directory>/<repo>/<branch-slug>`, where `worktrees.directory` comes
from `~/.config/herdr-app/settings.json` (today `~/Projects/worktrees`). The
person wants code to hold this rule, not only a written rule. Then the Herdr
app's New worktree dialog, Claude Code, Codex, and the person use the same
place. Without a question, the workflow removes worktrees whose branch is merged.

## Goals

1. One script, `wt`, is the only code that decides a worktree path and creates
   or removes worktrees. It reads the folder from Herdr's `settings.json`, with
   Herdr's fallback `~/.herdr/worktrees`.
2. Claude Code's own worktree feature (`--worktree`, `EnterWorktree`,
   `isolation: "worktree"`) creates worktrees through `wt`.
3. When a Claude Code session is in a repo's main checkout on the default
   branch, a prompt that asks for code changes makes Claude call
   `EnterWorktree` first, and the work continues in the same session.
4. Claude Code cannot edit files in the main checkout on the default branch.
   The person can override this for one session.
5. When a merged worktree is safe (definition below), the workflow removes it
   without a question.

## Non-goals

- Enforcement for Codex or other agents. They get the rule line and `wt` on
  PATH only.
- Moving the Claude session's tab into the worktree's Herdr space. ASSUME: the
  tab stays in the repo's space, because Herdr reads the terminal process's
  folder, which does not change.
- Catching every file write made through Bash (`sed -i`, `>`). Only the named
  git commands below are guarded.

## Anti-goals

- Deleting a worktree that holds work: uncommitted or untracked files,
  commits not merged, or a branch with no commits yet.
- Delaying session start or prompt submission by seconds.
- A second place that defines the worktree path.

## Constraints and facts

- `WorktreeCreate` hook (verified in a live `claude -p` run on 2026-11-26):
  `EnterWorktree name=probe-a` fired the hook with stdin
  `{"hook_event_name":"WorktreeCreate","name":"probe-a","cwd":"<repo>",...}`.
  The hook printed an absolute path outside the repo as its last stdout line.
  Claude's following Bash calls ran in that path, on the branch the hook made.
- The hook replaces git fully. Then `WorktreeRemove` must also be a hook:
  Claude Code does not fall back to git (docs: code.claude.com/docs/en/hooks.md).
  `WorktreeRemove` gets `worktree_path`. Exit 0 with the folder gone means
  removed.
- A second live run on 2026-11-26 showed two more facts. `EnterWorktree`
  accepts a `/` in its name (`feat/probe-b`), and the hook gets it unchanged.
  After `EnterWorktree`, `PreToolUse` gets the worktree path as `cwd`, so the
  guard does not block work inside the worktree.
- `UserPromptSubmit` gets `prompt`, `cwd`, `session_id`, and adds context with
  `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"..."}}`.
- `PreToolUse` denies with
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}`.
  The reason is shown to Claude.
- `~/.claude/settings.json` is not in git. `bootstrap.sh` merges
  `config/claude/settings.base.json` into it with `jq -s '.[0] * .[1]'`.
  `config/claude/scripts` is linked to `~/.claude/scripts`.
- The Herdr `worktree` mod (`~/.config/herdr-app/mods/worktree/main.js:204-215`)
  makes `<root>/<repo>/<slug(branch)>`. Its `slug()` (lines 30-38) applies NFC,
  replaces each run of characters other than letters, marks, digits, `.`, `_`
  and `-` with one `-`, and trims dashes at both ends. A name with no such
  characters becomes `branch-<FNV-1a hash as 8 hex digits>`. The mod reuses an existing branch, else
  `git worktree add -b <branch> <path> HEAD`. `<repo>` is the basename of the
  main checkout (from `git rev-parse --git-common-dir`).
- The person merges with merge commits (`gh pr merge --merge`), but also
  merges on the GitHub web page. That page can also squash or rebase.

## Decisions from the review round

- The Herdr New worktree dialog stays separate. `wt` copies its `slug()` rule,
  so both give the same path. Herdr-made worktrees have no `wtBase`, so
  cleanup removes them only by rule B.
- Ignored files: the person sees the list and decides (section Ignored files).

## Approaches considered

For the auto-trigger:

1. Hand off to a new Herdr space (`herdr-app do space.new --argv claude --task`).
   Correct Herdr nesting, but the person loses the current chat. Rejected: the
   person prefers the same session, and the live test showed it works.
2. Same session through `EnterWorktree` plus the `WorktreeCreate` hook.
   Picked.

For detecting a prompt that needs a worktree:

1. Context hint only. Depends on the model following it.
2. Keyword match. Misses other wordings, fires on false matches.
3. Hint plus an edit guard on the main checkout's default branch. Picked by the
   person: the hint makes Claude act early, the guard makes the rule hold.

For cleanup: list-and-approve, auto-remove-when-safe, or manual only. The
person picked automatic removal of safe worktrees, with the definition below.

## Design

### Files (all in the dotfiles repo)

| File | Role |
|---|---|
| `config/claude/scripts/wt` | the worktree script, subcommands below |
| `config/claude/scripts/worktree-guard.sh` | `UserPromptSubmit` hint and `PreToolUse` deny |
| `config/claude/scripts/tests/wt-test.sh` | self-test with throwaway repos |
| `config/claude/settings.base.json` | adds the hook entries |
| `bootstrap.sh` | adds `link "config/claude/scripts/wt" "~/.local/bin/wt"` |
| `config/claude/rules/git-workflow.md` | adds the rule line |

### `wt` subcommands

- `wt new <branch>`: print the worktree path on stdout as the last line. All
  git output goes to stderr. Path is `<root>/<repo>/<slug>`, with Herdr's exact `slug()` rule. If
  the path exists and is a worktree of this repo on that branch, reuse it. If
  the branch exists, run `git worktree add <path> <branch>`. If not, create
  the branch from `HEAD`, as Herdr does. Record the start commit with
  `git config branch.<branch>.wtBase <sha>`.
- `wt hook-create`: read stdin JSON, take `.name` as the branch and `.cwd` as
  the repo, run `wt new`. Used by `WorktreeCreate`.
- `wt hook-remove`: read `.worktree_path`. Run `git worktree remove <path>`
  (no `--force`). Then delete the branch in two cases only: the rule below
  calls it merged, or it has no commits past `wtBase`. In other cases, keep it. Used by
  `WorktreeRemove`.
- `wt prune [--auto] [repo]`: remove merged worktrees under `<root>/<repo>/`.
  `--auto` prints only a summary line. Without a repo argument it uses the
  current repo.

### Safe-to-remove rule (`wt prune`)

Run `git fetch --prune origin` first. The default branch is from
`git symbolic-ref refs/remotes/origin/HEAD`. If that ref is missing, prune
runs `git remote set-head origin --auto` once. If it is still missing, prune
does nothing for that repo. Builder's call: guessing the base for deletion is
unsafe. For each worktree in
`git worktree list --porcelain` whose path is under `<root>/<repo>/`:

- Skip the main checkout and any worktree on the default branch.
- Skip a worktree that has output from `git status --porcelain`.
- Skip a worktree that a Claude session entered. `hook-create` writes
  `~/.cache/wt/active/<session_id>` with the path, and `hook-remove` and a
  `SessionEnd` hook delete it. Lock files older than 7 days do not count.
  Builder's call: `hc ls` shows the Claude process folder, not the worktree.
- Skip a worktree that has a live terminal inside it: any `hc ls --json` terminal whose cwd
  is the path or below it.
- The branch is merged in two cases, A and B:
  - A: `git merge-base --is-ancestor <branch> origin/<default>`, and the
    branch tip is not equal to `branch.<branch>.wtBase`. A worktree with no
    `wtBase` (made by Herdr, by hand, or before `wt`) uses B only. Builder's
    call, from the anti-goal: without a base, A cannot tell a merged branch
    from an empty one. One such worktree exists today:
    `~/Projects/worktrees/wStack/feat-phone-first-diagrams`.
  - B: `gh pr list --head <branch> --state merged --json headRefOid` has an
    entry whose `headRefOid` equals the branch tip. If `gh` is missing or not
    logged in, skip B.
- For a merged branch with ignored files, do not remove it. The person decides
  (see Ignored files below).
- For a merged branch with no ignored files, run `git worktree remove <path>`, then `git branch -D <branch>` (`-D`
  because a squash merge is not an ancestor), then
  `git config --unset branch.<branch>.wtBase`.

### Ignored files

`git worktree remove` deletes git-ignored files without a question. The person
wants to see which ignored files exist and decide. The background prune cannot
ask, so it works in two steps:

1. Prune lists the ignored paths with
   `git status --porcelain --ignored=matching` (folders stay collapsed, for
   example `node_modules/`). It writes the worktree path, branch and that list
   to `~/.cache/wt/pending/<repo>.json`.
2. The next `UserPromptSubmit` in that repo reads the pending file and adds
   context: the worktrees, their branches, and the ignored paths, with the
   instruction to ask the person (AskUserQuestion) before any other work. On a
   yes, Claude runs `wt prune --confirm <path>`. That command removes the
   worktree with `--force` only when it is still merged and clean, and removes
   the entry from the pending file. On a no, Claude runs
   `wt prune --keep <path>`, which marks it kept with
   `git config branch.<branch>.wtKeep true`. Prune skips kept branches.

The hint shows each pending worktree once per session, so the person is not
asked on every prompt.

### Hooks in `settings.base.json`

- `WorktreeCreate`: `~/.claude/scripts/wt hook-create`.
- `WorktreeRemove`: `~/.claude/scripts/wt hook-remove`.
- `SessionStart`: start `wt prune --auto` in the background (`nohup ... &`),
  so the session does not wait for `fetch` and `gh`. Its log goes to
  `~/.cache/wt/prune.log`.
- `UserPromptSubmit`: `worktree-guard.sh prompt`.
- `PreToolUse` with matcher `Edit|Write|MultiEdit|NotebookEdit|Bash`:
  `worktree-guard.sh tool`.

The existing `SessionStart` entry stays. The merge in `bootstrap.sh` replaces
arrays, so the base file keeps both `SessionStart` entries.

### `worktree-guard.sh`

"Protected" means: `cwd` is in a git repo, `cwd` is the main checkout (its
`--git-dir` equals its `--git-common-dir`), and the current branch is the
default branch. Here, the default branch is `origin/HEAD` when set, else
`init.defaultBranch`, else `main`, else `master`. Builder's call: a wrong
guess in the guard only adds a hint or a deny, and deletes nothing.

- `prompt` mode. If the prompt contains the override token `!main` (case-sensitive, a standalone word), write
  `~/.cache/wt/override-<session_id>` and add no hint. In other protected
  cases, add this context: "You are on <default> in the main checkout of
  <repo>. Before you edit files for this request, call EnterWorktree with name
  `<type>/<slug>` (type from feat, fix, refactor, docs, test, chore, perf, ci).
  For questions that change no files, do not call it."
- `tool` mode, for Edit, Write, MultiEdit and NotebookEdit. The guard denies
  the call in one case: the session is protected, the target file is inside
  the main checkout, and no override file exists for this session. The reason
  tells Claude to call EnterWorktree.
- `tool` mode, for Bash. In any repo, the guard denies `git worktree add` and
  `git worktree remove`, with the reason "use `wt new <branch>` or
  EnterWorktree". For a protected session with no override file, it also
  denies `git commit`.
- For any failure inside the guard (not a repo, a `jq` error), the guard
  allows the call. The guard must never block work because of its own error.

### Rule line

Add to `config/claude/rules/git-workflow.md`: "Create and remove git worktrees
only with `wt` (`wt new <branch>`, `wt prune`), never with
`git worktree add`."

## Success criteria

1. `wt-test.sh` passes. It covers the path and slug, reuse of an existing
   branch, and the recorded `wtBase`. It also covers prune: it removes a merged
   (ancestor) branch, and it keeps a branch with no commits and a dirty
   worktree. Last, `hook-create` prints only the path on the last line.
2. In a live `claude -p` run in a throwaway repo with a bare `origin` with the real settings,
   `EnterWorktree` creates the worktree under the configured root.
3. In that run, an Edit on the default branch of the main checkout is denied,
   and the reason mentions EnterWorktree.
4. `UserPromptSubmit` and `PreToolUse` each finish in under 200 ms on a normal
   repo (measured with `time`).
5. The Herdr New worktree dialog and `wt new` give the same path for the same
   branch.

## Left to the builder

- How `wt` reads JSON and expands `~` (bash plus `jq` is enough).
- Exact text of the hint and the deny reasons, within the meaning above.
- Whether to check signal B with one `gh pr list --state merged` call per repo
  or one call per branch.
