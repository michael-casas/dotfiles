# Deferred Tasks

All currently tracked tasks are completed. This file is kept for future deferred work.

---

## Completed: Session Manager Extension for AI CLIs

**Status:** ✅ Completed via `nvim/lua/plugins/opencode.lua` (Neovim + snacks.nvim)  
**Completed:** 2026-04-24  
**Commit:** `159a353` — `feat(nvim) - AI TUI Plugin created and working`

### What was built
Higher-order `snacks.nvim` picker factory (`ai_session_picker`) parameterizing session management for any CLI tool. Each tool gets its own picker source plus a unified tool selector.

### Supported Tools
- **OpenCode** — `opencode session list --format json`
- **Codex** — reads `~/.codex/session_index.jsonl`
- **Claude** — reads `~/.claude/sessions/*.json`
- **Kiro** — `kiro-cli chat --list-sessions -f json`

### Entry Points
- `:AI` / `<leader>oai` — AI tool selector
- `:OpenCode` / `<leader>oc` — OpenCode sessions
- `:Codex` / `<leader>od` — Codex sessions
- `:Claude` / `<leader>ol` — Claude sessions
- `:Kiro` / `<leader>ok` — Kiro sessions

### Original Plan vs. Reality
- **Planned:** tmux-fzf extension with `prefix + Shift+A`
- **Actual:** Neovim-native snacks.nvim picker with buffer tracking, date-descending sort, and `vsplit | enew` terminal spawning
