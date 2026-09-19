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

This repeats for every row in the file map below. If a file already exists at that path, `rm -rf` removes it first.

Files such as `~/.zshrc` are symlinks that point into this repository. A symlink is a pointer to another file. When you edit `~/.zshrc`, you edit the file inside the repository. Git already tracks the change.

> Do not add secrets to this repository. The repository is public.
> Put local secrets in `~/.zsh-custom/env.zsh`. The sync process never reads or writes that file.

## New machine

Run this command:

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/21-BreakinCode/dotfiles/main/bootstrap.sh)"
```

The command does the following:

- It clones the repository to `~/Projects/breakincode/dotfiles`.
- It links each file in the table below into place.
- It installs herdr.
- If the folder `~/.zsh-custom/` is missing, it creates the folder.
- If `git`, `gh`, or a git identity is missing, it prints a message.

If this machine already has its own `~/.zshrc` or other listed file, the command replaces it with the repository version. This is intentional. It is not a bug.

## File map

| Repository file | Linked to |
| --- | --- |
| `zshrc` | `~/.zshrc` |
| `ghostty-config` | `~/.config/ghostty/config` |
| `starship.toml` | `~/.config/starship.toml` |
| `mise-config.toml` | `~/.config/mise/config.toml` |
| `tuicr-config.toml` | `~/.config/tuicr/config.toml` |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `claude/settings.local.json` | `~/.claude/settings.local.json` |
| `claude/rules` | `~/.claude/rules` |
| `claude/scripts` | `~/.claude/scripts` |

## Every day

```bash
pushdot   # commit and push local edits
pulldot   # pull the latest version and run bootstrap.sh again
```

The file `dotsync.sh` defines both commands. `.zshrc` sources that file.
