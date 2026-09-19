# dotfiles

Personal dotfiles. Repo is the source of truth — `~/.zshrc` etc. are symlinks
into it, so editing them directly is already "in" git.

## New machine

```
sh -c "$(curl -fsSL https://raw.githubusercontent.com/21-BreakinCode/dotfiles/main/bootstrap.sh)"
```

Clones this repo to `~/Projects/breakincode/dotfiles`, symlinks everything
into place, installs herdr, and seeds `~/.zsh-custom/` (never synced — put
local secrets in `~/.zsh-custom/env.zsh`, it's gitignored by omission).

If this machine already has its own `.zshrc` etc., they get overwritten —
that's intentional, not a bug.

## Every day

```
pushdot   # commit + push local edits
pulldot   # pull latest + re-run bootstrap.sh
```

Both come from `dotsync.sh`, sourced by `.zshrc`.
