#!/usr/bin/env bash
set -Eeuo pipefail
# Fail open: the guard never blocks work because of its own error.
trap 'exit 0' ERR

# Usage: worktree-guard.sh prompt|tool  (Claude Code hook JSON on stdin)
CACHE_DIR="${WT_CACHE:-$HOME/.cache/wt}"
mode="${1:-}"
input="$(cat)"
# The ERR trap is inherited by $(...) subshells and would only end the subshell, so check the input here.
jq -e . <<<"$input" >/dev/null 2>&1 || exit 0

field() { jq -r "$1 // empty" <<<"$input"; }

cwd="$(field .cwd)"
[[ -n "$cwd" ]] || exit 0
session_id="$(field .session_id)"
override_file="$CACHE_DIR/override-$session_id"
shown_file="$CACHE_DIR/shown-$session_id"

# Sets repo_main, repo_name, is_protected, default_branch. Returns 1 outside a git repo.
load_repo_state() {
  local git_dir common_dir branch
  { read -r git_dir; read -r common_dir; } < <(git -C "$cwd" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null) || return 1
  [[ -n "$common_dir" ]] || return 1
  repo_main="${common_dir%/.git}"
  repo_name="$(basename "$repo_main")"
  is_protected=false
  [[ "$git_dir" == "$common_dir" ]] || return 0
  default_branch="$(find_default_branch)"
  branch="$(git -C "$cwd" symbolic-ref --short -q HEAD)" || return 0
  [[ "$branch" == "$default_branch" ]] && is_protected=true
  return 0
}

find_default_branch() {
  local origin_head configured
  if origin_head="$(git -C "$cwd" symbolic-ref --short -q refs/remotes/origin/HEAD)"; then echo "${origin_head#origin/}"; return; fi
  if configured="$(git -C "$cwd" config init.defaultBranch)"; then echo "$configured"; return; fi
  if git -C "$cwd" show-ref --verify --quiet refs/heads/main; then echo main; return; fi
  echo master
}

# Prints target as an absolute path with symlinks resolved in its existing parent folder.
canonical_path() {
  local target="$1" parent
  [[ "$target" == /* ]] || target="$cwd/$target"
  parent="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)" || { echo "$target"; return; }
  echo "$parent/$(basename "$target")"
}

deny() {
  jq -nc --arg reason "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
}

# Prints the pending-prune text for worktrees not yet shown in this session, and records them as shown.
pending_hint() {
  local pending_file="$CACHE_DIR/pending/$repo_name.json" unshown shown_so_far=/dev/null
  [[ -f "$pending_file" ]] || return 0
  [[ -f "$shown_file" ]] && shown_so_far="$shown_file"
  unshown="$(jq -c --rawfile shown "$shown_so_far" '[.[] | select(.path as $p | ($shown | split("\n") | index($p)) == null)]' "$pending_file")"
  [[ "$unshown" != "[]" ]] || return 0
  mkdir -p "$CACHE_DIR"
  jq -r '.[].path' <<<"$unshown" >>"$shown_file"
  echo "Merged worktrees hold git-ignored files, so removal waits for the person's decision:"
  jq -r '.[] | "- \(.path) (branch \(.branch)), ignored: \(.ignored | join(", "))"' <<<"$unshown"
  echo "Before any other work, ask the person with AskUserQuestion whether to remove each one. On yes, run \`wt prune --confirm <path>\`. On no, run \`wt prune --keep <path>\`."
}

run_prompt_mode() {
  local prompt context
  load_repo_state || exit 0
  prompt="$(field .prompt)"
  context="$(pending_hint)"
  if [[ "$is_protected" == true ]]; then
    if grep -Eqi '(^|[^[:alnum:]])on main([^[:alnum:]]|$)' <<<"$prompt"; then
      mkdir -p "$CACHE_DIR"; touch "$override_file"
    elif [[ ! -e "$override_file" ]]; then
      context+="${context:+$'\n'}You are on $default_branch in the main checkout of $repo_name. Before you edit files for this request, call EnterWorktree with name \`<type>/<slug>\` (type from feat, fix, refactor, docs, test, chore, perf, ci). For questions that change no files, do not call it."
    fi
  fi
  [[ -n "$context" ]] || exit 0
  jq -nc --arg context "$context" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$context}}'
}

run_tool_mode() {
  local tool_name target command
  local worktree_shape='(^|[;&|[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?worktree[[:space:]]+(add|remove)'
  local commit_shape='(^|[;&|[:space:]])git[[:space:]]+(-C[[:space:]]+[^[:space:]]+[[:space:]]+)?commit'
  tool_name="$(field .tool_name)"
  case "$tool_name" in
    Bash)
      command="$(field .tool_input.command)"
      if grep -Eq "$worktree_shape" <<<"$command"; then
        deny "Use \`wt new <branch>\` or EnterWorktree to create worktrees, and \`wt prune\` to remove them."
        return
      fi
      grep -Eq "$commit_shape" <<<"$command" || return 0
      load_repo_state || return 0
      [[ "$is_protected" == true && ! -e "$override_file" ]] || return 0
      deny "You are on $default_branch in the main checkout of $repo_name. Call EnterWorktree first, then commit there. To work here anyway, the person can say \"on main\"." ;;
    Edit|Write|MultiEdit|NotebookEdit)
      target="$(field '.tool_input.file_path // .tool_input.notebook_path')"
      load_repo_state || return 0
      target="$(canonical_path "$target")"
      [[ "$is_protected" == true && ! -e "$override_file" && "$target" == "$repo_main/"* ]] || return 0
      deny "You are on $default_branch in the main checkout of $repo_name. Call EnterWorktree first, then edit there. To work here anyway, the person can say \"on main\"." ;;
  esac
}

case "$mode" in
  prompt) run_prompt_mode ;;
  tool) run_tool_mode ;;
esac
