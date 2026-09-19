vim.keymap.set("n", "<leader>k0", "zM", { desc = "Close all folds" })
vim.keymap.set("n", "<leader>kj", "zR", { desc = "Open all folds" })

vim.api.nvim_set_keymap("i", "jj", "<Esc>", { noremap = true, silent = true })

-- Buffer & Window mgmt
vim.keymap.set("n", "<C-t>", "<cmd>vsplit<cr>", { desc = "Split window right" })
vim.keymap.set("n", "<C-->", "<C-o>", { desc = "Jump to previous cursor position" })
