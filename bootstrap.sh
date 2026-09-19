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
link "config/claude/CLAUDE.md"            "~/.claude/CLAUDE.md"
link "config/claude/rules"                "~/.claude/rules"
link "config/claude/scripts"              "~/.claude/scripts"
link "config/nvim"                        "~/.config/nvim"

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
