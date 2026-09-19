# Sourced by .zshrc — defines pushdot/pulldot for the public dotfiles repo.
# Repo is the source of truth; ~/.zshrc etc. are symlinks into it, so editing
# them directly is already "in" git — pushdot just commits and ships it.

DOTFILES_REPO="$HOME/Projects/breakincode/dotfiles"

pushdot() {
  (
    cd "$DOTFILES_REPO" || return 1
    ./tools/gen-file-map.sh
    git add -A
    git commit -m "sync: $(date +%F)" || echo "Nothing to commit."

    # This repo lives under the 21-BreakinCode gh account, which may not be
    # the active one. `gh auth token -u` fetches its token directly, so the
    # push authenticates correctly without switching any account state.
    git -c credential.helper= \
        -c credential.helper='!f() { echo username=x-access-token; echo "password=$(gh auth token -u 21-BreakinCode)"; }; f' \
        push
  )
}

pulldot() {
  (
    cd "$DOTFILES_REPO" || return 1
    git pull && ./bootstrap.sh
  )
}
