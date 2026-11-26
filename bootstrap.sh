#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/21-BreakinCode/dotfiles.git"
REPO_DIR="$HOME/Projects/breakincode/dotfiles"

if ! command -v git &>/dev/null; then
  echo "  ! git not found. On a brand new Mac, run: xcode-select --install"
  echo "    Then rerun this script."
  exit 1
fi

if [[ ! -d "$REPO_DIR/.git" ]]; then
  echo "Cloning dotfiles repo..."
  git clone "$REPO_URL" "$REPO_DIR"
fi
cd "$REPO_DIR"

link() {
  local src="$REPO_DIR/$1" dest="${2/#\~/$HOME}"
  mkdir -p "$(dirname "$dest")"
  if [[ -e "$dest" || -L "$dest" ]]; then
    [[ -L "$dest" ]] || echo "  overwriting existing $dest"
    rm -rf "$dest"
  fi
  ln -s "$src" "$dest"
  echo "  linked $1 -> $dest"
}

echo "Linking dotfiles..."
link "config/zshrc"                      "~/.zshrc"
link "config/ghostty-config"              "~/.config/ghostty/config"
link "config/starship.toml"               "~/.config/starship.toml"
link "config/mise-config.toml"            "~/.config/mise/config.toml"
link "config/tuicr-config.toml"           "~/.config/tuicr/config.toml"
link "config/herdr-config.toml"           "~/.config/herdr/config.toml"
link "config/herdr-app/settings.json"     "~/.config/herdr-app/settings.json"
link "config/herdr-app/keys.json"         "~/.config/herdr-app/keys.json"
link "config/herdr-app/themes/gruvbox.json" "~/.config/herdr-app/themes/gruvbox.json"
for herdr_path in layouts/beautify21.json \
                  themes/herdr-glass.json \
                  mods/better-files mods/better-changes mods/better-sidebar mods/better-tabs mods/better-config \
                  mods/better-search mods/branch-pr mods/branch-jira mods/fuzzy-picker mods/ctrl-palette \
                  mods/herdr-glass-tabs mods/herdr-glass-pane mods/herdr-glass-toast mods/herdr-glass-chrome \
                  mods/herdr-glass-status mods/herdr-glass-agents mods/herdr-glass-spaces mods/herdr-glass-bg; do
  link "config/herdr-app/$herdr_path" "~/.config/herdr-app/$herdr_path"
done
# A file removed from this repo leaves a stale link behind: a broken one, or a mod folder
# with only Herdr's ignored jsconfig.json and gpui-kit.d.ts left. Drop the ones that point here.
for stale in "$HOME"/.config/herdr-app/{layouts,mods,themes}/*; do
  [[ -L "$stale" && "$(readlink "$stale")" == "$REPO_DIR/"* ]] || continue
  [[ ! -e "$stale" || ( "$stale" == */mods/* && ! -e "$stale/mod.json" ) ]] || continue
  rm "$stale"
  echo "  removed stale link $stale"
done
link "config/skillshare/config.yaml"      "~/.config/skillshare/config.yaml"
link "config/claude/CLAUDE.md"            "~/.claude/CLAUDE.md"
link "config/claude/rules"                "~/.claude/rules"
link "config/claude/scripts"              "~/.claude/scripts"
link "config/claude/scripts/wt"           "~/.local/bin/wt"
link "config/nvim"                        "~/.config/nvim"
link "config/gitconfig"                   "~/.gitconfig"
link "config/gitconfig-breakincode"       "~/.gitconfig-breakincode"
link "config/gitignore_global"            "~/.gitignore_global"
link "config/ssh-config"                  "~/.ssh/config"

# Claude Code rewrites ~/.claude/settings.json itself, so merge the synced keys
# into it instead of linking it. Keys from the repo file win; the rest stay.
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CLAUDE_SETTINGS_BASE="$REPO_DIR/config/claude/settings.base.json"
mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
[[ -s "$CLAUDE_SETTINGS" ]] || echo '{}' > "$CLAUDE_SETTINGS"
merged_settings="$(jq -s '.[0] * .[1]' "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS_BASE")"
printf '%s\n' "$merged_settings" > "$CLAUDE_SETTINGS"
echo "  merged config/claude/settings.base.json into ~/.claude/settings.json"

# .zsh-custom stays local-only — never synced, just seeded so the guarded
# `source` lines in zshrc have something to find on a fresh machine.
mkdir -p "$HOME/.zsh-custom"
[[ -f "$HOME/.zsh-custom/env.zsh" ]]     || touch "$HOME/.zsh-custom/env.zsh"
[[ -f "$HOME/.zsh-custom/aliases.zsh" ]] || touch "$HOME/.zsh-custom/aliases.zsh"

# Homebrew — idempotent install.
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# herdr — idempotent install.
if ! command -v herdr &>/dev/null; then
  echo "Installing herdr..."
  brew install herdr
fi
if command -v herdr &>/dev/null && [[ ! -d "$HOME/.agents/skills/herdr" ]]; then
  if command -v npx &>/dev/null; then
    npx -y skills add herdrdev/herdr --skill herdr -g
  else
    echo "  ! npx not found (Node.js missing) — skipping herdr skill install."
    echo "    Install Node, then run: npx -y skills add herdrdev/herdr --skill herdr -g"
  fi
fi

# Herdr mod helpers are per-machine binaries (gitignored), built from config/herdr-app/helpers.
for helper_build in "branch-pr herdr-pr" "branch-jira herdr-jira"; do
  read -r helper_mod helper_bin <<< "$helper_build"
  helper_out="$REPO_DIR/config/herdr-app/mods/$helper_mod/bin/$helper_bin"
  [[ -x "$helper_out" ]] && continue
  if command -v go &>/dev/null; then
    go -C "$REPO_DIR/config/herdr-app/helpers/$helper_mod" build -o "$helper_out" . \
      && echo "  built $helper_mod helper"
  else
    echo "  ! go not found — skipping the $helper_mod helper. Install Go, then rerun bootstrap.sh."
  fi
done

# Claude plugins — idempotent sync with interactive prompts for optional ones.
if command -v claude &>/dev/null; then
  echo "Syncing Claude plugins..."
  "$REPO_DIR/config/claude/scripts/claude-sync.sh" reinstall
else
  echo "  ! claude CLI not found — skipping plugin sync."
  echo "    Install Claude Code, then run: claude-sync reinstall"
fi

# Push access: pushdot supplies its own credential per-push (see tools/dotsync.sh),
# so it just needs `gh` present and logged into the 21-BreakinCode account.
if ! command -v gh &>/dev/null; then
  echo "  ! gh CLI not found — install it and run 'gh auth login' before pushdot can push."
fi

# Git identity — pushdot's first commit needs this.
if [[ -z "$(git config user.email 2>/dev/null || true)" ]]; then
  echo ""
  echo "  ! No git identity found for this repo. Before running pushdot:"
  echo "      git config --global user.name \"Your Name\""
  echo "      git config --global user.email \"you@example.com\""
fi

echo ""
echo "Done. Open a new terminal (or: source ~/.zshrc) to get pushdot/pulldot."
