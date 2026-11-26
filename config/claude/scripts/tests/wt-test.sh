#!/usr/bin/env bash
set -uo pipefail

# Tests for wt. `source wt-test.sh --lib` defines the helpers without running tests.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WT="$TESTS_DIR/../wt"
HERDR_MAIN_JS="$HOME/.config/herdr-app/mods/worktree/main.js"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

assert_eq() { [[ "$1" == "$2" ]] || { echo "  $3: expected [$1] got [$2]" >&2; exit 1; }; }
assert_ok() { local label="$1"; shift; "$@" >/dev/null 2>&1 || { echo "  $label: expected success: $*" >&2; exit 1; }; }
assert_fails() { local label="$1"; shift; ! "$@" >/dev/null 2>&1 || { echo "  $label: expected failure: $*" >&2; exit 1; }; }

# Exports TEST_TMP, ROOT, WT_HERDR_SETTINGS, WT_CACHE. Never touches real user paths.
setup_env() {
  TEST_TMP="$(cd "$(mktemp -d)" && pwd -P)"
  ROOT="$TEST_TMP/wtroot"
  WT_HERDR_SETTINGS="$TEST_TMP/settings.json"
  WT_CACHE="$TEST_TMP/cache"
  echo "{\"worktrees\":{\"directory\":\"$ROOT\"}}" >"$WT_HERDR_SETTINGS"
  export TEST_TMP ROOT WT_HERDR_SETTINGS WT_CACHE
  install_stubs
}

# gh and hc stubs shadow the real ones. Per-test data: $TEST_TMP/hc.json, $TEST_TMP/gh-<branch with / as _>.json.
install_stubs() {
  mkdir -p "$TEST_TMP/bin"
  cat >"$TEST_TMP/bin/hc" <<'STUB'
#!/usr/bin/env bash
if [[ -f "$TEST_TMP/hc.json" ]]; then cat "$TEST_TMP/hc.json"; else echo '{"terminals":[]}'; fi
STUB
  cat >"$TEST_TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  [[ "$1" == "--head" ]] && head_name="$2"
  [[ "$1" == "--state" ]] && state="$2"
  shift
done
[[ "${state:-}" == "merged" ]] || exit 1
reply_file="$TEST_TMP/gh-${head_name//\//_}.json"
[[ -f "$reply_file" ]] && cat "$reply_file" || exit 1
STUB
  chmod +x "$TEST_TMP/bin/hc" "$TEST_TMP/bin/gh"
  export PATH="$TEST_TMP/bin:$PATH"
}

# Prints a main checkout named "proj" with a bare origin, origin/HEAD -> main, one commit pushed.
make_repo() {
  local repo="$TEST_TMP/proj"
  git init -q --bare -b main "$TEST_TMP/origin.git"
  git init -q -b main "$repo"
  git -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" remote add origin "$TEST_TMP/origin.git"
  git -C "$repo" push -q -u origin main
  git -C "$repo" remote set-head origin main
  echo "$repo"
}

run_wt_in() { local dir="$1"; shift; (cd "$dir" && "$WT" "$@"); }

test_path_slug() {
  local repo; repo="$(make_repo)"
  assert_eq "$ROOT/proj/feat-login-oauth" "$(run_wt_in "$repo" path feat/login-oauth)" "slash"
  [[ "$(run_wt_in "$repo" path "fix login")" == */fix-login ]] || exit 1
  [[ "$(run_wt_in "$repo" path "-a--b-")" == */a--b ]] || exit 1
  [[ "$(run_wt_in "$repo" path "###")" =~ /branch-[0-9a-f]{8}$ ]] || { echo "  symbols-only slug" >&2; exit 1; }
}

test_slug_parity_with_herdr() {
  if ! command -v node >/dev/null; then echo "  skip: node missing"; return 0; fi
  local repo branch expected; repo="$(make_repo)"
  for branch in feat/x "fix login" "###" "é/ü" "a__b..c"; do
    expected="$(node -e "$(sed -n 30,38p "$HERDR_MAIN_JS"); console.log(slug(process.argv[1]))" "$branch")"
    assert_eq "$expected" "$(basename "$(run_wt_in "$repo" path "$branch")")" "parity for [$branch]"
  done
}

test_new_creates_branch_from_head() {
  local repo path; repo="$(make_repo)"
  path="$(run_wt_in "$repo" new feat/a 2>/dev/null | tail -n1)"
  assert_eq "$ROOT/proj/feat-a" "$path" "path"
  assert_ok "dir exists" test -d "$path"
  assert_eq "feat/a" "$(git -C "$path" branch --show-current)" "branch"
  assert_eq "$(git -C "$repo" rev-parse HEAD)" "$(git -C "$repo" config branch.feat/a.wtBase)" "wtBase"
}

test_new_reuses_existing_branch() {
  local repo path; repo="$(make_repo)"
  git -C "$repo" branch feat/b
  git -C "$repo" worktree add -q "$TEST_TMP/scratch" feat/b
  git -C "$TEST_TMP/scratch" commit -q --allow-empty -m work
  git -C "$repo" worktree remove "$TEST_TMP/scratch"
  path="$(run_wt_in "$repo" new feat/b 2>/dev/null | tail -n1)"
  assert_eq "feat/b" "$(git -C "$path" branch --show-current)" "branch"
  assert_fails "no wtBase" git -C "$repo" config branch.feat/b.wtBase
}

test_new_is_idempotent() {
  local repo first second; repo="$(make_repo)"
  first="$(run_wt_in "$repo" new feat/a 2>/dev/null | tail -n1)"
  second="$(run_wt_in "$repo" new feat/a 2>/dev/null | tail -n1)"
  assert_eq "$first" "$second" "same path"
  assert_ok "dir exists" test -d "$first"
}

test_root_fallback() {
  local repo; repo="$(make_repo)"
  echo '{}' >"$WT_HERDR_SETTINGS"
  export HOME="$TEST_TMP/home"; mkdir -p "$HOME"
  assert_eq "$HOME/.herdr/worktrees/proj/x" "$(run_wt_in "$repo" path x)" "fallback root"
  assert_fails "nothing created" test -e "$HOME/.herdr"
}

test_hook_create_last_line_and_lock() {
  local repo out; repo="$(make_repo)"
  out="$(echo "{\"name\":\"feat/c\",\"cwd\":\"$repo\",\"session_id\":\"s1\"}" | "$WT" hook-create 2>/dev/null)"
  assert_eq "$ROOT/proj/feat-c" "$out" "only stdout line is the path"
  assert_eq "$ROOT/proj/feat-c" "$(cat "$WT_CACHE/active/s1")" "lock content"
}

test_hook_create_fails_when_path_is_plain_dir() {
  local repo out; repo="$(make_repo)"
  mkdir -p "$ROOT/proj/feat-z"; echo x >"$ROOT/proj/feat-z/file"
  out="$(echo "{\"name\":\"feat/z\",\"cwd\":\"$repo\",\"session_id\":\"s1\"}" | "$WT" hook-create 2>/dev/null)" && { echo "  expected failure" >&2; exit 1; }
  assert_eq "" "$out" "no stdout path"
  assert_fails "no lock" test -e "$WT_CACHE/active/s1"
  assert_fails "no wtBase" git -C "$repo" config branch.feat/z.wtBase
}

test_hook_remove_keeps_branch_with_work() {
  local repo path; repo="$(make_repo)"
  path="$(run_wt_in "$repo" new feat/d 2>/dev/null | tail -n1)"
  git -C "$path" commit -q --allow-empty -m work
  echo "{\"worktree_path\":\"$path\",\"session_id\":\"s1\"}" | "$WT" hook-remove >/dev/null 2>&1
  assert_fails "dir gone" test -d "$path"
  assert_ok "branch kept" git -C "$repo" show-ref --verify --quiet refs/heads/feat/d
}

test_hook_remove_deletes_empty_branch() {
  local repo path; repo="$(make_repo)"
  echo "{\"name\":\"feat/e\",\"cwd\":\"$repo\",\"session_id\":\"s1\"}" | "$WT" hook-create >/dev/null 2>&1
  path="$ROOT/proj/feat-e"
  assert_ok "created first" test -d "$path"
  echo "{\"worktree_path\":\"$path\",\"session_id\":\"s1\"}" | "$WT" hook-remove >/dev/null 2>&1
  assert_fails "dir gone" test -d "$path"
  assert_fails "branch gone" git -C "$repo" show-ref --verify --quiet refs/heads/feat/e
  assert_fails "lock gone" test -e "$WT_CACHE/active/s1"
}

test_hook_remove_refuses_dirty() {
  local repo path; repo="$(make_repo)"
  path="$(run_wt_in "$repo" new feat/f 2>/dev/null | tail -n1)"
  echo x >"$path/untracked"
  assert_fails "refuses" bash -c "echo '{\"worktree_path\":\"$path\",\"session_id\":\"s1\"}' | '$WT' hook-remove"
  assert_ok "dir kept" test -d "$path"
}

# Prints the path of a worktree whose branch (with one commit and a .gitignore for .env) is merged into origin/main.
make_merged_worktree() {
  local repo="$1" branch="$2" path
  path="$(run_wt_in "$repo" new "$branch" 2>/dev/null | tail -n1)"
  echo ".env" >"$path/.gitignore"
  git -C "$path" add .gitignore
  git -C "$path" commit -q --allow-empty -m work
  git -C "$repo" merge -q --no-ff "$branch" -m "merge $branch"
  git -C "$repo" push -q origin main
  echo "$path"
}

branch_exists() { git -C "$1" show-ref --verify --quiet "refs/heads/$2"; }

test_prune_removes_merged_ancestor() {
  local repo path; repo="$(make_repo)"
  path="$(make_merged_worktree "$repo" feat/m)"
  run_wt_in "$repo" prune >/dev/null 2>&1
  assert_fails "dir gone" test -d "$path"
  assert_fails "branch gone" branch_exists "$repo" feat/m
  assert_fails "wtBase unset" git -C "$repo" config branch.feat/m.wtBase
}

test_prune_keeps_empty_branch() {
  local repo path; repo="$(make_repo)"
  path="$(run_wt_in "$repo" new feat/empty 2>/dev/null | tail -n1)"
  run_wt_in "$repo" prune >/dev/null 2>&1
  assert_ok "dir kept" test -d "$path"
}

test_prune_keeps_no_wtbase_without_gh() {
  local repo path="$ROOT/proj/hand"; repo="$(make_repo)"
  git -C "$repo" worktree add -q -b feat/h "$path"
  run_wt_in "$repo" prune >/dev/null 2>&1
  assert_ok "dir kept" test -d "$path"
}

test_prune_squash_via_gh() {
  local repo path tip; repo="$(make_repo)"
  path="$(run_wt_in "$repo" new feat/s 2>/dev/null | tail -n1)"
  git -C "$path" commit -q --allow-empty -m work
  tip="$(git -C "$path" rev-parse HEAD)"
  echo '[{"headRefOid":"0000000000000000000000000000000000000000"}]' >"$TEST_TMP/gh-feat_s.json"
  run_wt_in "$repo" prune >/dev/null 2>&1
  assert_ok "different oid kept" test -d "$path"
  echo "[{\"headRefOid\":\"$tip\"}]" >"$TEST_TMP/gh-feat_s.json"
  run_wt_in "$repo" prune >/dev/null 2>&1
  assert_fails "dir gone" test -d "$path"
  assert_fails "branch gone" branch_exists "$repo" feat/s
}

test_prune_keeps_dirty() {
  local repo path; repo="$(make_repo)"
  path="$(make_merged_worktree "$repo" feat/dirty)"
  echo x >"$path/untracked"
  run_wt_in "$repo" prune >/dev/null 2>&1
  assert_ok "dir kept" test -d "$path"
}

test_prune_keeps_locked() {
  local repo path; repo="$(make_repo)"
  path="$(make_merged_worktree "$repo" feat/lock)"
  mkdir -p "$WT_CACHE/active"; echo "$path" >"$WT_CACHE/active/s1"
  run_wt_in "$repo" prune >/dev/null 2>&1
  assert_ok "dir kept" test -d "$path"
}

test_prune_ignores_stale_lock() {
  local repo path old; repo="$(make_repo)"
  path="$(make_merged_worktree "$repo" feat/stale)"
  mkdir -p "$WT_CACHE/active"; echo "$path" >"$WT_CACHE/active/s1"
  old="$(date -v-8d +%Y%m%d%H%M 2>/dev/null || date -d '8 days ago' +%Y%m%d%H%M)"
  touch -t "$old" "$WT_CACHE/active/s1"
  run_wt_in "$repo" prune >/dev/null 2>&1
  assert_fails "dir gone" test -d "$path"
}

test_prune_keeps_live_terminal() {
  local repo path; repo="$(make_repo)"
  path="$(make_merged_worktree "$repo" feat/term)"
  echo "{\"terminals\":[{\"cwd\":\"$path/sub\"}]}" >"$TEST_TMP/hc.json"
  run_wt_in "$repo" prune >/dev/null 2>&1
  assert_ok "dir kept" test -d "$path"
}

test_prune_keeps_when_ignored_status_fails() {
  local repo path real_git; repo="$(make_repo)"
  path="$(make_merged_worktree "$repo" feat/sf)"
  echo secret >"$path/.env"
  real_git="$(command -v git)"
  mkdir -p "$TEST_TMP/failbin"
  printf '#!/usr/bin/env bash\n[[ "$*" == *--ignored* ]] && exit 1\nexec %s "$@"\n' "$real_git" >"$TEST_TMP/failbin/git"
  chmod +x "$TEST_TMP/failbin/git"
  PATH="$TEST_TMP/failbin:$PATH" run_wt_in "$repo" prune >/dev/null 2>&1
  assert_ok "dir kept" test -d "$path"
  assert_ok ".env kept" test -f "$path/.env"
}

test_prune_keeps_wtkeep() {
  local repo path; repo="$(make_repo)"
  path="$(make_merged_worktree "$repo" feat/k)"
  git -C "$repo" config branch.feat/k.wtKeep true
  run_wt_in "$repo" prune >/dev/null 2>&1
  assert_ok "dir kept" test -d "$path"
}

test_prune_no_origin_head() {
  local repo path err; repo="$(make_repo)"
  path="$(make_merged_worktree "$repo" feat/n)"
  git -C "$repo" remote set-head origin -d
  git -C "$repo" remote set-url origin "$TEST_TMP/missing.git"
  err="$(run_wt_in "$repo" prune 2>&1 >/dev/null)" || { echo "  expected exit 0" >&2; exit 1; }
  [[ -n "$err" ]] || { echo "  expected stderr message" >&2; exit 1; }
  assert_ok "dir kept" test -d "$path"
}

test_prune_outside_repo_is_silent() {
  local out; out="$(cd "$TEST_TMP" && "$WT" prune --auto 2>&1)" || { echo "  expected exit 0" >&2; exit 1; }
  assert_eq "" "$out" "no output"
}

test_prune_ignored_goes_pending() {
  local repo path; repo="$(make_repo)"
  path="$(make_merged_worktree "$repo" feat/i)"
  echo secret >"$path/.env"
  run_wt_in "$repo" prune >/dev/null 2>&1
  assert_ok "dir kept" test -d "$path"
  assert_eq "$path" "$(jq -r '.[0].path' "$WT_CACHE/pending/proj.json")" "pending path"
  assert_eq "feat/i" "$(jq -r '.[0].branch' "$WT_CACHE/pending/proj.json")" "pending branch"
  assert_eq ".env" "$(jq -r '.[0].ignored[]' "$WT_CACHE/pending/proj.json")" "pending ignored"
}

test_prune_confirm_and_keep() {
  local repo confirm_path keep_path; repo="$(make_repo)"
  confirm_path="$(make_merged_worktree "$repo" feat/c)"
  keep_path="$(make_merged_worktree "$repo" feat/kp)"
  echo secret >"$confirm_path/.env"; echo secret >"$keep_path/.env"
  run_wt_in "$repo" prune >/dev/null 2>&1
  assert_eq 2 "$(jq length "$WT_CACHE/pending/proj.json")" "two pending"
  run_wt_in "$repo" prune --confirm "$confirm_path" >/dev/null 2>&1
  assert_fails "confirmed dir gone" test -d "$confirm_path"
  assert_fails "confirmed branch gone" branch_exists "$repo" feat/c
  run_wt_in "$repo" prune --keep "$keep_path" >/dev/null 2>&1
  assert_ok "kept dir stays" test -d "$keep_path"
  assert_eq true "$(git -C "$repo" config branch.feat/kp.wtKeep)" "wtKeep"
  assert_eq 0 "$(jq length "$WT_CACHE/pending/proj.json")" "pending empty"
}

test_prune_confirm_refuses_unmerged() {
  local repo path; repo="$(make_repo)"
  path="$(run_wt_in "$repo" new feat/u 2>/dev/null | tail -n1)"
  git -C "$path" commit -q --allow-empty -m work
  assert_fails "refuses" run_wt_in "$repo" prune --confirm "$path"
  assert_ok "dir kept" test -d "$path"
}

test_prune_auto_summary_and_log() {
  local repo out; repo="$(make_repo)"
  make_merged_worktree "$repo" feat/a >/dev/null
  out="$(run_wt_in "$repo" prune --auto 2>/dev/null)"
  assert_eq "wt prune: removed 1, pending 0, kept 0" "$out" "summary"
  assert_ok "log written" grep -q "removed" "$WT_CACHE/prune.log"
}

test_hook_remove_deletes_merged_branch() {
  local repo path; repo="$(make_repo)"
  path="$(make_merged_worktree "$repo" feat/g)"
  echo "{\"worktree_path\":\"$path\",\"session_id\":\"s1\"}" | "$WT" hook-remove >/dev/null 2>&1
  assert_fails "dir gone" test -d "$path"
  assert_fails "branch gone" branch_exists "$repo" feat/g
}

GUARD="$TESTS_DIR/../worktree-guard.sh"

# guard_run <mode> <json>: prints the guard's stdout.
guard_run() { printf '%s' "$2" | "$GUARD" "$1"; }
prompt_json() { jq -nc --arg cwd "$1" --arg prompt "$2" '{cwd:$cwd,session_id:"s1",prompt:$prompt}'; }
tool_json() { jq -nc --arg cwd "$1" --arg tool "$2" --arg key "$3" --arg value "$4" '{cwd:$cwd,session_id:"s1",tool_name:$tool,tool_input:{($key):$value}}'; }
deny_reason() { jq -r '.hookSpecificOutput | select(.permissionDecision == "deny") | .permissionDecisionReason'; }
make_worktree_dir() { git -C "$1" worktree add -q "$TEST_TMP/wt-$2" -b "$2" && echo "$TEST_TMP/wt-$2"; }

test_guard_prompt_hint_on_main() {
  local repo out; repo="$(make_repo)"
  out="$(guard_run prompt "$(prompt_json "$repo" "add a login page")")"
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$out")" == *EnterWorktree* ]] || { echo "  no hint: $out" >&2; exit 1; }
}

test_guard_prompt_override() {
  local repo out; repo="$(make_repo)"
  out="$(guard_run prompt "$(prompt_json "$repo" "quick typo fix ON MAIN")")"
  assert_eq "" "$out" "no output"
  assert_ok "override file" test -e "$WT_CACHE/override-s1"
}

test_guard_prompt_silent_in_worktree() {
  local repo path; repo="$(make_repo)"; path="$(make_worktree_dir "$repo" feat/x)"
  assert_eq "" "$(guard_run prompt "$(prompt_json "$path" "hello")")" "worktree"
}

test_guard_prompt_silent_on_feature_branch() {
  local repo; repo="$(make_repo)"
  git -C "$repo" checkout -q -b feat/x
  assert_eq "" "$(guard_run prompt "$(prompt_json "$repo" "hello")")" "feature branch"
}

test_guard_prompt_pending_once() {
  local repo out context; repo="$(make_repo)"
  mkdir -p "$WT_CACHE/pending"
  echo '[{"path":"/w/proj/feat-a","branch":"feat/a","ignored":["node_modules/",".env"]}]' >"$WT_CACHE/pending/proj.json"
  out="$(guard_run prompt "$(prompt_json "$repo" "hello")")"
  context="$(jq -r .hookSpecificOutput.additionalContext <<<"$out")"
  for needle in /w/proj/feat-a feat/a node_modules/ .env "wt prune --confirm" "--keep"; do
    [[ "$context" == *"$needle"* ]] || { echo "  first call lacks [$needle]" >&2; exit 1; }
  done
  context="$(guard_run prompt "$(prompt_json "$repo" "again")" | jq -r '.hookSpecificOutput.additionalContext // ""')"
  [[ "$context" != *feat/a* && "$context" != *"--keep"* ]] || { echo "  second call repeats pending" >&2; exit 1; }
}

test_guard_denies_edit_on_main() {
  local repo reason tool key; repo="$(make_repo)"
  for tool in Edit Write MultiEdit NotebookEdit; do
    key=file_path; [[ "$tool" == NotebookEdit ]] && key=notebook_path
    reason="$(guard_run tool "$(tool_json "$repo" "$tool" "$key" "$repo/a.txt")" | deny_reason)"
    [[ "$reason" == *EnterWorktree* ]] || { echo "  $tool not denied: [$reason]" >&2; exit 1; }
  done
}

test_guard_allows_edit_with_override() {
  local repo; repo="$(make_repo)"
  mkdir -p "$WT_CACHE"; touch "$WT_CACHE/override-s1"
  assert_eq "" "$(guard_run tool "$(tool_json "$repo" Edit file_path "$repo/a.txt")")" "override"
}

test_guard_allows_edit_in_worktree() {
  local repo path; repo="$(make_repo)"; path="$(make_worktree_dir "$repo" feat/x)"
  assert_eq "" "$(guard_run tool "$(tool_json "$path" Edit file_path "$path/a.txt")")" "worktree"
}

test_guard_allows_edit_outside_repo_file() {
  local repo; repo="$(make_repo)"
  assert_eq "" "$(guard_run tool "$(tool_json "$repo" Write file_path "/tmp/notes.txt")")" "outside file"
}

test_guard_denies_git_worktree_add() {
  local repo path reason dir; repo="$(make_repo)"; path="$(make_worktree_dir "$repo" feat/x)"
  for dir in "$repo" "$path"; do
    reason="$(guard_run tool "$(tool_json "$dir" Bash command "git worktree add ../x -b y")" | deny_reason)"
    [[ "$reason" == *"wt new"* ]] || { echo "  not denied in $dir: [$reason]" >&2; exit 1; }
  done
}

test_guard_denies_commit_on_main() {
  local repo; repo="$(make_repo)"
  [[ "$(guard_run tool "$(tool_json "$repo" Bash command "git add -A && git commit -m x")" | deny_reason)" == *EnterWorktree* ]] || exit 1
}

test_guard_allows_commit_in_worktree() {
  local repo path; repo="$(make_repo)"; path="$(make_worktree_dir "$repo" feat/x)"
  assert_eq "" "$(guard_run tool "$(tool_json "$path" Bash command "git commit -m x")")" "commit in worktree"
}

test_guard_denies_edit_via_symlink_and_relative_path() {
  local repo reason; repo="$(make_repo)"
  ln -s "$TEST_TMP" "$TEST_TMP/link"
  reason="$(guard_run tool "$(tool_json "$TEST_TMP/link/proj" Edit file_path "$TEST_TMP/link/proj/a.txt")" | deny_reason)"
  [[ "$reason" == *EnterWorktree* ]] || { echo "  symlink path allowed" >&2; exit 1; }
  reason="$(guard_run tool "$(tool_json "$repo" Edit file_path "a.txt")" | deny_reason)"
  [[ "$reason" == *EnterWorktree* ]] || { echo "  relative path allowed" >&2; exit 1; }
}

test_guard_override_phrase_needs_word_boundary() {
  local repo; repo="$(make_repo)"
  guard_run prompt "$(prompt_json "$repo" "fix the on maintenance page")" >/dev/null
  assert_fails "no override" test -e "$WT_CACHE/override-s1"
}

test_guard_no_hint_after_override() {
  local repo out; repo="$(make_repo)"
  guard_run prompt "$(prompt_json "$repo" "typo on main")" >/dev/null
  out="$(guard_run prompt "$(prompt_json "$repo" "next change")")"
  assert_eq "" "$out" "hint after override"
}

test_guard_fail_open() {
  local out rc
  out="$(guard_run tool "$(tool_json / Edit file_path /a.txt)")"; rc=$?
  assert_eq "0:" "$rc:$out" "cwd /"
  out="$(printf 'not json' | "$GUARD" prompt)"; rc=$?
  assert_eq "0:" "$rc:$out" "bad json"
  out="$(printf 'not json' | "$GUARD" tool)"; rc=$?
  assert_eq "0:" "$rc:$out" "bad json tool"
}

test_guard_speed() {
  local repo mode input start_ms end_ms average_ms i; repo="$(make_repo)"
  for mode in prompt tool; do
    input="$(prompt_json "$repo" "hello")"
    [[ "$mode" == tool ]] && input="$(tool_json "$repo" Edit file_path "$repo/a.txt")"
    start_ms="$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')"
    for i in $(seq 20); do printf '%s' "$input" | "$GUARD" "$mode" >/dev/null; done
    end_ms="$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')"
    average_ms=$(( (end_ms - start_ms) / 20 ))
    echo "  $mode average ${average_ms} ms"
    (( average_ms < 200 )) || { echo "  $mode too slow: ${average_ms} ms" >&2; exit 1; }
  done
}

run_all_tests() {
  local failed=0 test_name
  for test_name in $(declare -F | awk '{print $3}' | grep '^test_'); do
    if ( setup_env; "$test_name" ); then echo "PASS $test_name"; else echo "FAIL $test_name"; failed=1; fi
  done
  return "$failed"
}

[[ "${1:-}" == "--lib" ]] || run_all_tests
