-- NOTE: https://github.com/folke/snacks.nvim?tab=readme-ov-file#-usage
-- for more keybind search or just press <leader>sk to find key operations
return {
    "folke/snacks.nvim",
    opts = {
        scroll = { enabled = false },
        dashboard = {
            preset = {
                -- https://patorjk.com/software/taag/#p=display&f=ANSI+Shadow&t=neovim&x=none&v=4&h=4&w=80&we=false
                -- ANSI Shadow style
                header = [[
████████╗██╗  ██╗███████╗         ██╗ ██████╗ ██╗   ██╗██████╗ ███╗   ██╗███████╗██╗   ██╗
╚══██╔══╝██║  ██║██╔════╝         ██║██╔═══██╗██║   ██║██╔══██╗████╗  ██║██╔════╝╚██╗ ██╔╝
   ██║   ███████║█████╗           ██║██║   ██║██║   ██║██████╔╝██╔██╗ ██║█████╗   ╚████╔╝ 
   ██║   ██╔══██║██╔══╝      ██   ██║██║   ██║██║   ██║██╔══██╗██║╚██╗██║██╔══╝    ╚██╔╝  
   ██║   ██║  ██║███████╗    ╚█████╔╝╚██████╔╝╚██████╔╝██║  ██║██║ ╚████║███████╗   ██║   
   ╚═╝   ╚═╝  ╚═╝╚══════╝     ╚════╝  ╚═════╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝╚══════╝   ╚═╝   
]],
            },
        },
        picker = {
            sources = {
                grep_buffers = { ignored = true, hidden = true },
                -- explorer = { ignored = true, hidden = true },
                -- files = { ignored = true, hidden = true },
                -- grep = { ignored = true, hidden = true },
                -- grep_word = { ignored = true, hidden = true },
            },
        },
    },
}
