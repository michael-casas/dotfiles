# Deferred Tasks

## Session Manager Extension for AI CLIs

**Status:** Deferred  
**Requested:** 2026-04-23

### Context
Currently using `tmux-fzf` for tmux session/window/pane switching. Want to extend fzf to also surface and attach to existing sessions inside AI CLI tools.

### Requested Tools
- **OpenCode**: `opencode` sessions
- **Claude Code**: `claude` sessions
- **Codex**: `codex` sessions

### Desired Behavior
1. Press a keybinding (e.g., `prefix + Shift+A` for "AI sessions")
2. Fzf popup lists all *existing* sessions across the three tools
3. Selecting a session attaches to it inside that tool's TUI
4. If no session exists, option to create a new one

### Open Questions
- How does each tool expose its session list? (CLI flags? socket files? state dirs?)
- Should this be a custom script or a tmux-fzf extension?
- What happens when a session is already attached elsewhere?

### Next Steps
- Research each tool's session persistence mechanism
- Decide if this belongs in tmux-fzf, a standalone script, or a custom tmux keybinding
