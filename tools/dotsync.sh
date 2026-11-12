# Sourced by .zshrc — defines pushdot/pulldot for the public dotfiles repo.
# Repo is the source of truth; ~/.zshrc etc. are symlinks into it, so editing
# them directly is already "in" git — pushdot just commits and ships it.

DOTFILES_REPO="$HOME/Projects/breakincode/dotfiles"

# The Appier Claude config lives in a private work repo, never in this public one.
# Its links.sh records and restores the links into ~/.claude and the Appier projects.
APPIER_CONFIG_DIR="$HOME/Projects/Appier/william-hung-appier/claude-appier-config"
APPIER_CONFIG_URL="https://github.com/william-hung-appier/claude-appier-config.git"
APPIER_GH_ACCOUNT="william-hung-appier"

# git with the work account's token, the same way pushdot uses 21-BreakinCode's.
_appier_git() {
  git -c credential.helper= \
      -c credential.helper="!f() { echo username=x-access-token; echo \"password=\$(gh auth token -u $APPIER_GH_ACCOUNT)\"; }; f" \
      "$@"
}

# Pull the Appier config and keep live edits. Stop when they conflict with the remote,
# so a file with conflict markers never reaches the projects or the next push.
_appier_pull() {
  if [[ -z "$(git -C "$APPIER_CONFIG_DIR" ls-files -u)" ]]; then
    _appier_git -C "$APPIER_CONFIG_DIR" pull --rebase --autostash || return 1
  fi
  if [[ -n "$(git -C "$APPIER_CONFIG_DIR" ls-files -u)" ]]; then
    echo "  ! Your local edits conflict with the remote in $APPIER_CONFIG_DIR."
    echo "    Fix the conflict markers, then run: git -C $APPIER_CONFIG_DIR reset && git -C $APPIER_CONFIG_DIR stash drop"
    return 1
  fi
}

pushdot() {
  local dotfiles_status=0
  (
    cd "${DOTFILES_REPO:-$HOME/Projects/breakincode/dotfiles}" || return 1
    ./tools/gen-file-map.sh
    git add -A
    git commit -m "sync: $(date +%F)" || echo "Nothing to commit."

    # This repo lives under the 21-BreakinCode gh account, which may not be
    # the active one. `gh auth token -u` fetches its token directly, so the
    # push authenticates correctly without switching any account state.
    git -c credential.helper= \
        -c credential.helper='!f() { echo username=x-access-token; echo "password=$(gh auth token -u 21-BreakinCode)"; }; f' \
        push
  ) || dotfiles_status=$?

  [[ -d "$APPIER_CONFIG_DIR/.git" ]] || return $dotfiles_status
  echo "Appier Claude config:"
  (
    cd "$APPIER_CONFIG_DIR" || return 1
    _appier_pull || return 1
    ./links.sh scan || return 1
    git add -A
    git diff --cached --quiet || git commit -m "sync: $(date +%F)" || return 1
    _appier_git push
  ) || return $?
  return $dotfiles_status
}

pulldot() {
  (
    cd "${DOTFILES_REPO:-$HOME/Projects/breakincode/dotfiles}" || return 1
    git pull && ./bootstrap.sh
  ) || return 1

  local answer
  printf 'Also sync Appier Claude config? [Y/n] '
  read -r answer
  [[ "$answer" == [nN]* ]] && return 0
  if ! gh auth token -u "$APPIER_GH_ACCOUNT" >/dev/null 2>&1; then
    echo "  ! gh is not logged in as $APPIER_GH_ACCOUNT. Run 'gh auth login', then pulldot again."
    return 1
  fi
  if [[ -d "$APPIER_CONFIG_DIR/.git" ]]; then
    _appier_pull || return 1
  else
    _appier_git clone "$APPIER_CONFIG_URL" "$APPIER_CONFIG_DIR" || return 1
  fi
  "$APPIER_CONFIG_DIR/links.sh" apply
}

pushbrewfile() {
  (
    cd "${DOTFILES_REPO:-$HOME/Projects/breakincode/dotfiles}" || return 1
    brew bundle dump --file=config/Brewfile --force
    git add -A
    git commit -m "sync: Brewfile $(date +%F)" || echo "Nothing to commit."

    git -c credential.helper= \
        -c credential.helper='!f() { echo username=x-access-token; echo "password=$(gh auth token -u 21-BreakinCode)"; }; f' \
        push
  )
}

pullbrewfile() {
  (
    cd "${DOTFILES_REPO:-$HOME/Projects/breakincode/dotfiles}" || return 1
    git pull && brew bundle install --file=config/Brewfile
  )
}
