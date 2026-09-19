# dotfiles

This repository holds personal dotfiles. The repository is the only real copy of each file.

Pushdot and pulldot share one flow:

```md
┌─────┐                   ┌────────────┐                       ┌────────┐
│ You │                   │ Local Repo │                       │ GitHub │
└─────┘                   └────────────┘                       └────────┘
   │                             │                                  │
   │        edit ~/.zshrc        │                                  │
   ├─────────────────────────────→                                  │
   │                             │                                  │
   │           pushdot           │                                  │
   ├─────────────────────────────→                                  │
   │                             │                                  │
   │                             │        add, commit, push         │
   │                             ├──────────────────────────────────→
   │                             │                                  │
   │           pulldot           │                                  │
   ├─────────────────────────────→                                  │
   │                             │                                  │
   │                             │            git pull              │
   │                             ├──────────────────────────────────→
   │                             │                                  │
   │                             │         latest commits           │
   │                             ←──────────────────────────────────┤
   │                             │                                  │
   │        relink files         │                                  │
   ←─────────────────────────────┤                                  │
   │                             │                                  │
```

Pushdot runs add, commit, and push. Pulldot runs git pull, then bootstrap.sh. Bootstrap.sh relinks each file like this:

```txt
┌───────┐   ┌─────────────────┐   ┌───────┐   ┌──────────┐
│ zshrc │ → │ rm -rf ~/.zshrc │ → │ ln -s │ → │ ~/.zshrc │
└───────┘   └─────────────────┘   └───────┘   └──────────┘
```

> Do not add secrets to this repository. The repository is public.
> Put local secrets in `~/.zsh-custom/env.zsh`. The sync process never reads or writes that file.

## Installed packages

Pushbrewfile and pullbrewfile follow the same flow, for installed packages instead of
dotfiles:

```md
┌─────┐                   ┌────────────┐                       ┌────────┐
│ You │                   │ Local Repo │                       │ GitHub │
└─────┘                   └────────────┘                       └────────┘
   │                             │                                  │
   │        pushbrewfile         │                                  │
   ├─────────────────────────────→                                  │
   │                             │                                  │
   │                             │     dump, add, commit, push      │
   │                             ├──────────────────────────────────→
   │                             │                                  │
   │        pullbrewfile         │                                  │
   ├─────────────────────────────→                                  │
   │                             │                                  │
   │                             │            git pull              │
   │                             ├──────────────────────────────────→
   │                             │                                  │
   │                             │         latest commits           │
   │                             ←──────────────────────────────────┤
   │                             │                                  │
   │     brew bundle install     │                                  │
   ←─────────────────────────────┤                                  │
   │                             │                                  │
```

Pushbrewfile runs `brew bundle dump`, then add, commit, and push. Pullbrewfile runs git
pull, then `brew bundle install` to match `config/Brewfile`.

## New machine

Run this command:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/21-BreakinCode/dotfiles/main/bootstrap.sh)"
```

The command does the following:

- It clones the repository to `~/Projects/breakincode/dotfiles`.
- It links each file listed in [FILE_MAP.md](docs/FILE_MAP.md) into place.
- If the machine does not have Homebrew, it installs Homebrew.
- It installs herdr.
- If the folder `~/.zsh-custom/` is missing, it creates the folder.
- If `git`, `gh`, or a git identity is missing, it prints a message.

If this machine already has its own `~/.zshrc` or other listed file, the command replaces it with the repository version. This is intentional. It is not a bug.

The command does not install packages from `config/Brewfile`. Run `pullbrewfile` after bootstrap.sh to install them.

## Claude Code statusline

Claude Code reads `~/.claude/settings.json` for user-level config. It never reads a
user-level `settings.local.json`. That filename only means something inside a
project's own `.claude/` folder. So the statusline command cannot sync as a symlinked
file. Add it by hand, once per machine, as a key inside `~/.claude/settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "~/.claude/scripts/statusline.sh",
  "padding": 0
}
```

`~/.claude/scripts/statusline.sh` is already synced by this repo, so only the JSON key
above needs adding by hand.

## Every day

```bash
pushdot        # rebuild FILE_MAP.md, commit, and push local edits
pulldot        # pull the latest version and run bootstrap.sh again
pushbrewfile   # dump installed packages to config/Brewfile, commit, and push
pullbrewfile   # pull the latest version and install packages from config/Brewfile
```

The file `tools/dotsync.sh` defines these commands. `.zshrc` sources that file.
