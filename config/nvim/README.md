# 💤 LazyVim

## Fresh Installation

```bash
git clone https://github.com/21-BreakinCode/lazyvim-config ~/.config/nvim
```

## Overwrite Existing Configuration

```bash
mv ~/.config/nvim ~/.config/nvim.backup \
    && git clone https://github.com/21-BreakinCode/lazyvim-config ~/.config/nvim
```

To restore your backup if needed:

```bash
rm -rf ~/.config/nvim
mv ~/.config/nvim.backup ~/.config/nvim
```

## Check

### Lazy git default dir

```bash
# create folder
mkdir -p ~/.config/lazygit && touch ~/.config/lazygit/config.yml
```

```bash
# into zshrc
export XDG_CONFIG_HOME="$HOME/.config"
```
