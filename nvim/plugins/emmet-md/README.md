# emmet-md

Expand Emmet-style abbreviations into Markdown. Requires Neovim 0.11 with
native snippets. Put this directory on the runtime path with your plugin
manager. The plugin registers an Insert-mode target and a command.

```lua
vim.keymap.set("i", "<M-e>", "<Plug>(emmet-md-expand)")
```

Try `:EmmetMd ul>li*3` or put `table3x2` on a Markdown line and invoke your
mapping. Tab stops use Neovim's native snippet engine. See `:help emmet-md`
for keymap setup, configuration, and the Lua API.

Run `tests/run-lua.sh` for standalone tests.
