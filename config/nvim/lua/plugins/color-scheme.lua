-- NOTE: dracula colorscheme
-- return {
--     {
--         "Mofiqul/dracula.nvim",
--         lazy = false,
--         priority = 1000,
--         opts = {
--             transparent_bg = true,
--             italic_comment = true,
--             show_end_of_buffer = true,
--         },
--         config = function(_, opts)
--             require("dracula").setup(opts)
--             vim.cmd([[colorscheme dracula]])
--         end,
--     },
--     {
--         "LazyVim/LazyVim",
--         opts = {
--             colorscheme = "dracula",
--         },
--     },
-- }

-- NOTE: VSCode colorscheme
return {
    {
        "Mofiqul/vscode.nvim",
        lazy = false,
        priority = 1000,
        config = function()
            require("vscode").setup({
                italic_comments = true,
                transparent = true,
                terminal_colors = true,
            })
            require("vscode").load()
        end,
    },
    {
        "LazyVim/LazyVim",
        opts = {
            colorscheme = "vscode",
        },
    },
}
