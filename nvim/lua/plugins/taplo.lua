-- Taplo LSP for TOML with Codex config schema support
-- Enables IntelliSense and validation for ~/.codex/config.toml and .codex/config.toml
--
-- Prerequisites:
--   brew install taplo
--   # or: npm i -g @taplo/cli
--
-- The schema association below matches both global (~/.codex/config.toml)
-- and project-local (.codex/config.toml) files against OpenAI's published
-- Codex configuration schema.
return {
  -- Import LazyVim's built-in TOML support (includes taplo LSP)
  { import = "lazyvim.plugins.extras.lang.toml" },

  -- Override taplo configuration to add Codex schema association
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        taplo = {
          settings = {
            evenBetterToml = {
              schema = {
                associations = {
                  -- Match both global and project Codex config files
                  ["(.*\\/)?\\.codex\\/config\\.toml$"] = "https://developers.openai.com/codex/config-schema.json",
                },
              },
            },
          },
        },
      },
    },
  },
}
