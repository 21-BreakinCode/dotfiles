# dotfiles

These are personal dotfiles. The repo is the source of truth. Files like
`~/.zshrc` are symlinks into the repo. If you edit them directly, the change
is already tracked in git.

## New machine

```
sh -c "$(curl -fsSL https://raw.githubusercontent.com/21-BreakinCode/dotfiles/main/bootstrap.sh)"
```

This command clones the repo to `~/Projects/breakincode/dotfiles`. It links
every file into place. It installs herdr. It also creates the folder
`~/.zsh-custom/`, which the sync process never touches. Put local secrets in
`~/.zsh-custom/env.zsh`. That file is not tracked in the repo.

If this machine already has its own `.zshrc` and similar files, the command
overwrites them. This is intentional. It is not a bug.

## Every day

```
pushdot   # commit and push local edits
pulldot   # pull the latest version and run bootstrap.sh again
```

The `dotsync.sh` file defines both commands. `.zshrc` sources that file.
