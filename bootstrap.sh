#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/21-BreakinCode/dotfiles.git"
REPO_DIR="$HOME/Projects/breakincode/dotfiles"

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
link "zshrc"                      "~/.zshrc"
link "ghostty-config"              "~/.config/ghostty/config"
link "starship.toml"               "~/.config/starship.toml"
link "mise-config.toml"            "~/.config/mise/config.toml"
link "tuicr-config.toml"           "~/.config/tuicr/config.toml"
link "claude/CLAUDE.md"            "~/.claude/CLAUDE.md"
link "claude/settings.local.json"  "~/.claude/settings.local.json"
link "claude/rules"                "~/.claude/rules"
link "claude/scripts"              "~/.claude/scripts"

# .zsh-custom stays local-only — never synced, just seeded so the guarded
# `source` lines in zshrc have something to find on a fresh machine.
mkdir -p "$HOME/.zsh-custom"
[[ -f "$HOME/.zsh-custom/env.zsh" ]]     || touch "$HOME/.zsh-custom/env.zsh"
[[ -f "$HOME/.zsh-custom/aliases.zsh" ]] || touch "$HOME/.zsh-custom/aliases.zsh"

# herdr — idempotent install.
if ! command -v herdr &>/dev/null; then
  if command -v brew &>/dev/null; then
    echo "Installing herdr..."
    brew install herdr
  else
    echo "  ! Homebrew not found — install from https://brew.sh, then rerun this script for herdr."
  fi
fi
if command -v herdr &>/dev/null && [[ ! -d "$HOME/.agents/skills/herdr" ]]; then
  npx -y skills add herdrdev/herdr --skill herdr -g
fi

# Push access: route HTTPS auth for this repo through gh (avoids SSH
# cross-account issues and macOS Keychain prompts in non-interactive shells).
if command -v gh &>/dev/null; then
  git config --local --replace-all credential.helper "!gh auth git-credential"
else
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
