return {
    "neovim/nvim-lspconfig",
    opts = {
        servers = {
            yamlls = {
                -- NOTE: Have to add this for yamlls to understand that we support line folding
                capabilities = {
                    textDocument = {
                        foldingRange = {
                            dynamicRegistration = false,
                            lineFoldingOnly = true,
                        },
                    },
                },
                before_init = function(_, new_config)
                    new_config.settings.yaml.schemas = vim.tbl_deep_extend(
                        "force",
                        new_config.settings.yaml.schemas or {},
                        require("schemastore").yaml.schemas()
                    )
                end,

                settings = {
                    yaml = {
                        customTags = {
                            "!And sequence",
                            "!Condition",
                            "!If sequence",
                            "!Not sequence",
                            "!Equals sequence",
                            "!Or sequence",
                            "!FindInMap sequence",
                            "!Base64",
                            "!Ref",
                            "!Sub",
                            "!Sub sequence",
                            "!GetAtt",
                            "!GetAtt sequence",
                            "!GetAZs",
                            "!ImportValue",
                            "!Select",
                            "!Select sequence",
                            "!Split sequence",
                            "!Join sequence",
                        },
                    },
                },
            },
        },
    },
}
