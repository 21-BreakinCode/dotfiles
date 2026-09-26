#!/usr/bin/env bash
set -euo pipefail

# ── Plugin Registry ──────────────────────────────────────────────
# Edit these arrays to add/remove plugins.

MARKETPLACES=(
	"anthropics/claude-plugins-official"
	"21-BreakinCode/cc-plugins"
	# token optimization
	"DietrichGebert/ponytail"
	"alexgreensh/token-optimizer"
	# language
	"AminBlg/SimpleEnglish"
)

PLUGINS=(
	# official
	"code-simplifier@claude-plugins-official"
	"agent-sdk-dev@claude-plugins-official"
	"hookify@claude-plugins-official"
	"pr-review-toolkit@claude-plugins-official"
	"context7@claude-plugins-official"
	"plugin-dev@claude-plugins-official"
	"skill-creator@claude-plugins-official"
	"claude-code-setup@claude-plugins-official"
	"superpowers@claude-plugins-official"
	# official: lsp
	"typescript-lsp@claude-plugins-official"
	"pyright-lsp@claude-plugins-official"
	"gopls-lsp@claude-plugins-official"
	# official: superpowers
	# workflow (21-BreakinCode)
	"autoresearch@21-breakincode"
	"code-reviewer@21-breakincode"
	"adhd-review@21-breakincode"
	"receipts@21-breakincode"
	"humanize@21-breakincode"
	"obsidian-kit@21-breakincode"
	# token optimization
	"ponytail@ponytail"
	"token-optimizer@alexgreensh-token-optimizer"
	# language
	"simple-english@simple-english"
)

# Plugins replaced by another one. reinstall uninstalls them if still present.
RETIRED_PLUGINS=(
	"note-visualizer@21-breakincode" # replaced by obsidian-kit
	"obsidian@obsidian-skills"       # absorbed into obsidian-kit
	"session-learner@21-breakincode" # merged into obsidian-kit 2.0.0
	"hh@21-breakincode"              # merged into obsidian-kit 2.0.0
	"simple-mandarin@21-breakincode" # merged into obsidian-kit 2.0.0
	"uiux-optimizer@21-breakincode"  # removed, no replacement
)

# Installed, but kept off at user scope. Projects turn them on where needed,
# e.g. plugin-dev in 21-BreakinCode/cc-plugins (.claude/settings.json).
USER_SCOPE_OFF_PLUGINS=(
	"plugin-dev@claude-plugins-official"
	"skill-creator@claude-plugins-official"
	"agent-sdk-dev@claude-plugins-official"
)

# Optional marketplaces — prompted at install/reinstall time.
# To skip the prompt non-interactively, set env vars to `y` or `n`, e.g.
#   CLAUDE_SYNC_APPIER=y claude-sync install
OPTIONAL_MARKETPLACES=(
	# key|github-repo|plugins (space-separated)
	"appier-cc-plugins|william-hung-appier/appier-cc-plugins|cs-jira@appier-cc-plugins cs-k8s@appier-cc-plugins cs-ops@appier-cc-plugins appier-jenkins@appier-cc-plugins idash-db@appier-cc-plugins qa@appier-cc-plugins"
	"cs-ads-insight|william-hung-appier/cs-ads-insight|cs-ads-insight@cs-ads-insight"
)

# ── Paths ────────────────────────────────────────────────────────

CLAUDE_DIR="${HOME}/.claude"
INSTALLED_JSON="${CLAUDE_DIR}/plugins/installed_plugins.json"
MARKETPLACES_DIR="${CLAUDE_DIR}/plugins/marketplaces"
LOCAL_PLUGINS_DIR="${CLAUDE_DIR}/plugins/local"

# ── Helpers ──────────────────────────────────────────────────────

get_installed_sha() {
	local plugin_key="$1"
	if [[ ! -f "$INSTALLED_JSON" ]]; then
		echo ""
		return
	fi
	if command -v jq &>/dev/null; then
		jq -r ".plugins[\"${plugin_key}\"][0].gitCommitSha // empty" "$INSTALLED_JSON" 2>/dev/null || echo ""
	else
		echo ""
	fi
}

get_installed_version() {
	jq -r ".plugins[\"$1\"][0].version // empty" "$INSTALLED_JSON" 2>/dev/null || echo ""
}

# The version a fresh install would get. Comparing it with the installed version means a
# plugin reinstalls only when it changed; the marketplace repo HEAD moves on any commit to
# any plugin in a monorepo, so comparing HEADs reinstalled nearly every plugin each run.
# Order: marketplace.json version, then the plugin's plugin.json version, then the pinned
# source sha (url sources), then the marketplace's 12-char HEAD, which is the version
# Claude Code records for an unversioned plugin.
get_expected_version() {
	local plugin_key="$1"
	local plugin_name="${plugin_key%%@*}"
	local marketplace_dir="${MARKETPLACES_DIR}/${plugin_key##*@}"
	local manifest="${marketplace_dir}/.claude-plugin/marketplace.json"
	[[ -f "$manifest" ]] || { echo ""; return; }

	local entry version source_path
	entry=$(jq -c --arg name "$plugin_name" '.plugins[] | select(.name == $name)' "$manifest" 2>/dev/null)
	[[ -n "$entry" ]] || { echo ""; return; }

	version=$(jq -r '.version // empty' <<<"$entry")
	if [[ -z "$version" ]]; then
		source_path=$(jq -r 'if (.source | type) == "string" then .source else empty end' <<<"$entry")
		[[ -n "$source_path" ]] && version=$(jq -r '.version // empty' "${marketplace_dir}/${source_path}/.claude-plugin/plugin.json" 2>/dev/null)
	fi
	if [[ -z "$version" ]]; then
		version=$(jq -r 'if (.source | type) == "object" then (.source.sha // empty) else empty end' <<<"$entry")
		[[ -n "$version" ]] && { echo "sha:${version}"; return; }
	fi
	[[ -z "$version" && -d "${marketplace_dir}/.git" ]] && version=$(git -C "$marketplace_dir" rev-parse --short=12 HEAD 2>/dev/null)
	echo "$version"
}

prompt_optional() {
	# Per-item yes/no prompt; honors CLAUDE_SYNC_<KEY> env override
	# (key uppercased, hyphens → underscores). Returns 0 = yes, 1 = no.
	local key="$1"
	local label="${2:-marketplace}"
	local env_var="CLAUDE_SYNC_$(echo "$key" | tr '[:lower:]-' '[:upper:]_')"
	local override="${!env_var:-}"

	if [[ "$override" =~ ^[yY]$ ]]; then return 0; fi
	if [[ "$override" =~ ^[nN]$ ]]; then return 1; fi

	# No override — only prompt on a TTY; default to skip otherwise
	if [[ ! -t 0 ]]; then return 1; fi

	read -r -p "  Sync optional ${label} '${key}'? [y/N] " ans
	[[ "$ans" =~ ^[yY]$ ]]
}

disable_user_scope_off_plugins() {
	# Runs after every install or update pass, so a sync never turns these back on at user scope.
	for plugin in "${USER_SCOPE_OFF_PLUGINS[@]}"; do
		claude plugin disable "$plugin" --scope user 2>/dev/null || true
	done
}

install_optional() {
	for entry in "${OPTIONAL_MARKETPLACES[@]}"; do
		local key="${entry%%|*}"
		local rest="${entry#*|}"
		local repo="${rest%%|*}"
		local plugins="${rest#*|}"

		if prompt_optional "$key"; then
			claude plugin marketplace add "$repo" 2>/dev/null || true
			for p in $plugins; do
				claude plugin install "$p" 2>/dev/null || true
				# Work plugins stay off at user scope; settings.appier-cs.json enables them per work repo.
				if [[ "$key" == "appier-cc-plugins" ]]; then
					claude plugin disable "$p" --scope user 2>/dev/null || true
				fi
			done
		fi
	done
}

# ── Non-Marketplace Tools ────────────────────────────────────────
# Tools installed outside the Claude plugin marketplace.

HINDSIGHT_HOOKS_DIR="${HOME}/.hindsight/coding-agents/dist"
HINDSIGHT_CONFIG="${HOME}/.hindsight/coding-agent.json"
HINDSIGHT_BANKS="${CLAUDE_DIR}/configs/hindsight-banks.json"

# Reads hindsight-banks.json (relative paths) and generates coding-agent.json (absolute paths).
# To add a bank: edit ~/.claude/configs/hindsight-banks.json, then run claude-sync reinstall.
generate_hindsight_config() {
	if [[ ! -f "$HINDSIGHT_BANKS" ]]; then
		echo "  ⚠ hindsight: ${HINDSIGHT_BANKS} not found — skip config" >&2
		return 1
	fi
	if ! command -v jq &>/dev/null; then
		echo "  ⚠ hindsight: jq required to generate config" >&2
		return 1
	fi

	local serverMode apiUrl defaultBank optInOnly
	serverMode=$(jq -r '.serverMode' "$HINDSIGHT_BANKS")
	apiUrl=$(jq -r '.apiUrl' "$HINDSIGHT_BANKS")
	defaultBank=$(jq -r '.defaultBank' "$HINDSIGHT_BANKS")
	optInOnly=$(jq -r '.optInOnly // false' "$HINDSIGHT_BANKS")

	# Build mapPathToBank by expanding relative paths to $HOME
	local mapJson
	mapJson=$(jq -r '
		[.banks | to_entries[] | .key as $bank | .value[] | {("\(.)"): $bank}]
		| add // {}
	' "$HINDSIGHT_BANKS" | sed "s|\"Projects/|\"${HOME}/Projects/|g")

	jq -n \
		--arg sm "$serverMode" \
		--arg url "$apiUrl" \
		--arg bank "$defaultBank" \
		--argjson oi "$optInOnly" \
		--argjson map "$mapJson" \
		'{serverMode: $sm, apiUrl: $url, bankId: $bank, optInOnly: $oi, mapPathToBank: $map}'
}

install_hindsight() {
	# Optional, like OPTIONAL_MARKETPLACES. Skip the prompt non-interactively
	# with CLAUDE_SYNC_HINDSIGHT=y or =n.
	prompt_optional "hindsight" "tool" || return 0

	# Install hooks if missing
	if [[ -f "${HINDSIGHT_HOOKS_DIR}/claude-hook.js" ]]; then
		echo "  hindsight-coding-agents: already installed"
	else
		echo "  hindsight-coding-agents: installing..."
		# --yes: npx otherwise waits on an "Ok to proceed?" prompt the first time.
		npx --yes @vectorize-io/hindsight-coding-agents install || {
			echo "  ⚠ hindsight-coding-agents install failed (run manually: npx @vectorize-io/hindsight-coding-agents install)"
			return 0
		}
	fi

	# Deploy bank config if missing bankId or config absent
	local needsDeploy=false
	if [[ ! -f "$HINDSIGHT_CONFIG" ]]; then
		needsDeploy=true
	elif command -v jq &>/dev/null; then
		local currentBankId
		currentBankId=$(jq -r '.bankId // empty' "$HINDSIGHT_CONFIG" 2>/dev/null)
		[[ -z "$currentBankId" ]] && needsDeploy=true
	fi

	if [[ "$needsDeploy" == true ]]; then
		mkdir -p "$(dirname "$HINDSIGHT_CONFIG")"
		if generate_hindsight_config > "$HINDSIGHT_CONFIG"; then
			echo "  hindsight: deployed bank config from hindsight-banks.json"
		fi
	fi
}

# Force-deploy bank config from hindsight-banks.json (for sync-banks command).
sync_hindsight_banks() {
	mkdir -p "$(dirname "$HINDSIGHT_CONFIG")"
	if generate_hindsight_config > "$HINDSIGHT_CONFIG"; then
		echo "  hindsight: synced bank config from hindsight-banks.json"
	fi
}

# ── Commands ─────────────────────────────────────────────────────

cmd_install() {
	echo "Installing all Claude plugins..."
	echo ""

	for mp in "${MARKETPLACES[@]}"; do
		claude plugin marketplace add "$mp" 2>/dev/null || true
	done

	local installed=0
	for plugin in "${PLUGINS[@]}"; do
		# Never install locally-developed plugins — leave them untouched
		[[ "$plugin" == *@local ]] && continue

		claude plugin install "$plugin" 2>/dev/null || true
		installed=$((installed + 1))
	done

	install_optional
	disable_user_scope_off_plugins
	install_hindsight

	echo ""
	echo "Done. ${installed} plugins processed."
}

cmd_reinstall() {
	echo "Checking for plugin updates..."
	echo ""

	# Ensure marketplaces are registered
	echo "Refreshing ${#MARKETPLACES[@]} marketplaces..."
	for mp in "${MARKETPLACES[@]}"; do
		claude plugin marketplace add "$mp" 2>/dev/null || true
	done

	# Pull latest from remote marketplace caches — 'marketplace add' doesn't fetch new commits.
	# The 'local' marketplace is intentionally skipped — locally-developed plugins are never synced.
	for mp_dir in "${MARKETPLACES_DIR}"/*/; do
		[ "$(basename "$mp_dir")" = "local" ] && continue
		[ -d "${mp_dir}.git" ] || continue
		git -C "$mp_dir" pull --ff-only --quiet 2>/dev/null || true
	done

	local updated=0
	local skipped=0

	for plugin in "${PLUGINS[@]}"; do
		# Never sync locally-developed plugins — leave them untouched
		[[ "$plugin" == *@local ]] && continue

		local installed_sha
		installed_sha=$(get_installed_sha "$plugin")

		# Not installed yet — install it
		if [[ -z "$installed_sha" ]]; then
			echo "  + ${plugin} (new)"
			claude plugin install "$plugin" 2>/dev/null || true
			updated=$((updated + 1))
			continue
		fi

		local expected_version installed_version
		expected_version=$(get_expected_version "$plugin")
		if [[ "$expected_version" == sha:* ]]; then
			installed_version="sha:${installed_sha}"
		else
			installed_version=$(get_installed_version "$plugin")
		fi

		# Can't determine the expected version — skip (no manifest or jq missing)
		if [[ -z "$expected_version" ]]; then
			skipped=$((skipped + 1))
			continue
		fi

		if [[ "$installed_version" != "$expected_version" ]]; then
			echo "  ~ ${plugin} (${installed_version#sha:} -> ${expected_version#sha:})"
			claude plugin install "$plugin" 2>/dev/null || true
			updated=$((updated + 1))
		else
			skipped=$((skipped + 1))
		fi
	done

	for retired in "${RETIRED_PLUGINS[@]}"; do
		claude plugin uninstall "$retired" &>/dev/null && echo "  - ${retired} (retired)" || true
	done

	install_optional
	echo "Turning off user-scope plugins..."
	disable_user_scope_off_plugins
	install_hindsight

	echo ""
	if [[ $updated -eq 0 ]]; then
		echo "All plugins up to date. (${skipped} checked)"
	else
		echo "Updated ${updated} plugin(s). ${skipped} already current."
	fi
}

cmd_update() {
	echo "Updating all plugins via 'claude plugin update'..."
	echo ""

	# Pull latest marketplace sources first
	claude plugin marketplace update 2>/dev/null || true

	local updated=0
	local failed=0

	for plugin in "${PLUGINS[@]}"; do
		[[ "$plugin" == *@local ]] && continue
		if claude plugin update "$plugin" 2>/dev/null; then
			echo "  ✓ ${plugin}"
			updated=$((updated + 1))
		else
			failed=$((failed + 1))
		fi
	done

	# Also update optional plugins that are installed
	for entry in "${OPTIONAL_MARKETPLACES[@]}"; do
		local plugins="${entry##*|}"
		for p in $plugins; do
			if claude plugin update "$p" 2>/dev/null; then
				echo "  ✓ ${p}"
				updated=$((updated + 1))
			else
				failed=$((failed + 1))
			fi
		done
	done

	disable_user_scope_off_plugins

	echo ""
	echo "Updated ${updated} plugin(s). ${failed} skipped (not installed or already current)."
}

cmd_remove() {
	local plugin="${1:-}"
	if [[ -z "$plugin" ]]; then
		echo "Usage: claude-sync remove <plugin-name>"
		echo "Example: claude-sync remove session-learner@local"
		return 1
	fi
	echo "Removing ${plugin}..."
	claude plugin uninstall "$plugin"
}

cmd_sync_banks() {
	echo "Syncing Hindsight bank config from ${HINDSIGHT_BANKS}..."
	sync_hindsight_banks
	echo ""
	echo "Deployed to ${HINDSIGHT_CONFIG}"
	echo "Banks:"
	jq -r '.banks | to_entries[] | "  \(.key): \(.value | length) dir(s)"' "$HINDSIGHT_BANKS" 2>/dev/null
}

cmd_help() {
	echo "Usage: claude-sync <command> [args]"
	echo ""
	echo "Commands:"
	echo "  install     Install all plugins (idempotent)"
	echo "  reinstall   Only reinstall plugins with source changes"
	echo "  update      Update all plugins via 'claude plugin update'"
	echo "  sync-banks  Deploy Hindsight bank config from hindsight-banks.json"
	echo "  remove      Remove a plugin (claude-sync remove <name>)"
	echo "  help        Show this help"
}

# ── Main ─────────────────────────────────────────────────────────

main() {
	local command="${1:-help}"
	shift 2>/dev/null || true

	case "$command" in
	install) cmd_install ;;
	reinstall) cmd_reinstall ;;
	update) cmd_update ;;
	sync-banks) cmd_sync_banks ;;
	remove) cmd_remove "$@" ;;
	help | *) cmd_help ;;
	esac
}

main "$@"
