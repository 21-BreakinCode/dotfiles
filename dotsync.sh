# Sourced by .zshrc — defines pushdot/pulldot for the public dotfiles repo.
# Repo is the source of truth; ~/.zshrc etc. are symlinks into it, so editing
# them directly is already "in" git — pushdot just commits and ships it.

DOTFILES_REPO="$HOME/Projects/breakincode/dotfiles"

pushdot() {
  (
    cd "$DOTFILES_REPO" || return 1
    git add -A
    git commit -m "sync: $(date +%F)" || echo "Nothing to commit."
    git push
  )
}

pulldot() {
  (
    cd "$DOTFILES_REPO" || return 1
    git pull && ./bootstrap.sh
  )
}
