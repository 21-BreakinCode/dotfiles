# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Neovim configuration based on LazyVim, a modern Neovim distribution that provides a pre-configured setup with lazy loading of plugins.

## Architecture

### Plugin Loading System

LazyVim uses lazy.nvim for plugin management with a specific loading order:

1. `init.lua` loads `lua/config/lazy.lua`
2. `lazy.lua` bootstraps lazy.nvim and sets up plugin specs:
   - LazyVim core plugins (`LazyVim/LazyVim`)
   - Custom plugins from `lua/plugins/` directory
3. Each plugin file returns a table specification that defines plugin settings, dependencies, and keymaps

### Plugin Specification Pattern

All custom plugins in `lua/plugins/` follow this structure:

```lua
return {
  "plugin/repo",
  dependencies = { "required/plugin" },
  keys = { -- lazy-loaded keymaps
    { "<leader>xx", function() require("plugin").action() end, desc = "Description" }
  },
  opts = { -- plugin configuration
    setting = value
  },
  config = function(_, opts)
    -- additional setup if needed
  end
}
```

## Development Commands

### Code Formatting and Linting

```bash
# Format all Lua files (uses stylua with 4 spaces, 120 column width)
stylua lua/

# Format specific file
stylua lua/plugins/example.lua

# Check formatting without modifying
stylua --check lua/
```

### Plugin Management

```vim
:Lazy               # Open plugin manager UI
:Lazy sync          # Update plugins and regenerate lazy-lock.json
:Lazy restore       # Restore plugins to versions in lazy-lock.json
:Lazy profile       # Profile plugin load times
:Lazy check         # Check for plugin updates without applying
:Lazy clean         # Clean unused plugins
:checkhealth lazy   # Check plugin health
```

### Debugging and Health Checks

```vim
:checkhealth         # General health check
:Lazy log            # View lazy.nvim logs
:messages            # View Neovim messages
```

## Custom Keymaps

Key leader mappings defined in `lua/config/keymaps.lua`:

- `<leader>` = space (LazyVim default)
- `jj` = escape to normal mode (insert mode)
- `<leader>k0` = close all folds
- `<leader>kj` = open all folds
- `<C-t>` = split window vertically

## LazyVim Extras

Configured extras in `lazyvim.json` provide extended language support:

- **Coding**: blink, luasnip, mini-comment, mini-surround, nvim-cmp
- **Editor**: fzf, inc-rename, snacks_picker, telescope
- **Formatting**: prettier
- **Languages**: cmake, docker, git, go, helm, json, markdown, python, terraform, toml, yaml
- **Linting**: eslint
- **UI**: indent-blankline, treesitter-context

## Adding New Functionality

### Adding a New Plugin

1. Create a new file in `lua/plugins/` (e.g., `lua/plugins/myplugin.lua`)
2. Return a plugin specification table
3. Run `:Lazy sync` to install

### Modifying Existing Plugins

To override LazyVim default plugin settings, create a file in `lua/plugins/` with the same plugin name:

```lua
return {
  "existing/plugin",
  opts = {
    -- your overrides
  }
}
```

### Adding Language Support

Check available LazyVim extras:

```vim
:LazyExtras
```

## Custom Plugins

Current custom plugins in `lua/plugins/`:

- `claudcode.lua` - Claude Code integration
- `color-scheme.lua` - Dracula theme with transparency
- `cspell.lua` - Spell checking integration
- `incline.lua` - Floating statuslines
- `snacks.lua` - Collection of QoL plugins (disabled scroll animation, custom dashboard)
- `swagger.lua` - Swagger/OpenAPI support
- `treesitter.lua` - Syntax highlighting with 40+ languages configured
- `typr.lua` - Typing practice plugin

Language-specific LSP configurations in `lua/plugins/lsp/`:

- `python.lua` - Ruff LSP + Pyright with coordinated linting/formatting
- `yaml.lua` - YAML LSP with CloudFormation schema support

## Repository Details

- **Remote**: <git@github.com>:21-BreakinCode/lazyvim-config.git
- **Main branch**: main
- **Stylua config**: 4 spaces, 120 column width (see `stylua.toml`)

## Installation

```bash
# Fresh installation
git clone https://github.com/21-BreakinCode/lazyvim-config ~/.config/nvim

# Overwrite existing configuration (with backup)
mv ~/.config/nvim ~/.config/nvim.backup \
    && git clone https://github.com/21-BreakinCode/lazyvim-config ~/.config/nvim
```

## LazyGit Configuration

Ensure LazyGit is properly configured:

```bash
# Create LazyGit config directory
mkdir -p ~/.config/lazygit && touch ~/.config/lazygit/config.yml

# Add to your shell configuration (.zshrc or .bashrc)
export XDG_CONFIG_HOME="$HOME/.config"
```

