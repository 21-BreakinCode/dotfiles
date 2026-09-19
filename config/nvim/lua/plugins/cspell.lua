return {
    {
        "mfussenegger/nvim-lint",
        optional = true,
        opts = {
            linters_by_ft = {
                ["*"] = { "cspell" },
            },
            linters = {
                cspell = {
                    condition = function()
                        return vim.fn.executable("cspell") == 1
                    end,
                },
            },
        },
    },
}
