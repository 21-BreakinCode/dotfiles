# Sourced by .zshrc — defines pushdot/pulldot for the public dotfiles repo.
# Repo is the source of truth; ~/.zshrc etc. are symlinks into it, so editing
# them directly is already "in" git — pushdot just commits and ships it.

DOTFILES_REPO="$HOME/Projects/breakincode/dotfiles"

pushdot() {
  (
    cd "$DOTFILES_REPO" || return 1
    git add -A
    git commit -m "sync: $(date +%F)" || echo "Nothing to commit."

    # gh's git-credential helper only serves the currently active account,
    # and this repo lives under 21-BreakinCode — swap to it for the push,
    # then restore whatever account was active before.
    local prev_account
    prev_account="$(gh api user -q .login 2>/dev/null || true)"
    gh auth switch --hostname github.com --user 21-BreakinCode >/dev/null 2>&1
    git push
    [[ -n "$prev_account" ]] && gh auth switch --hostname github.com --user "$prev_account" >/dev/null 2>&1
  )
}

pulldot() {
  (
    cd "$DOTFILES_REPO" || return 1
    git pull && ./bootstrap.sh
  )
}
