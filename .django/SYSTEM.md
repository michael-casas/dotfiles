# Dotfiles — Django's System Journal

## Overview

Personal dotfiles repository for Michael Casas (mcasa_atlantis). Managed via bare git repo at `~/.dotfiles` with symlink-based activation. All machines, shells, editors, and tooling converge through this single source of truth.

---

## Repository Structure

```
~/.dotfiles/
├── bash/                    → ~/ (primary shell)
│   ├── .bashrc
│   └── .bash_profile
├── nvim/                    → ~/.config/nvim/   (LazyVim-based)
│   └── lua/plugins/opencode.lua  # Multi-tool AI session manager
├── herdr/config.toml        → ~/.config/herdr/config.toml
├── git/.gitconfig           → ~/.gitconfig
├── starship/starship.toml   → ~/.config/starship.toml (Gruvbox Dark)
├── claude/settings.json     → ~/.claude/settings.json
├── .agent/SYSTEM.md         # Full documentation (31KB, previously canonical)
├── opencode/                # OpenCode AI runtime config
│   ├── agent/               # Agent definition files (Django, SYS_* agents, etc.)
│   │   ├── django-systems-architect.md  # Old Django agent definition
│   │   ├── architecture-code-advisor.md
│   │   ├── SYS_COMMANDER_CODEX.md
│   │   ├── SYS_OVERLORD.md
│   │   ├── SYS_EXEC.md
│   │   └── ... (many more)
│   ├── god-lock/            # GOD-LOCK-specific agent definitions
│   └── AGENTS.md
├── advisor/                 # Marketing/Sales/Strategy knowledge base
│   ├── AES-SEO-and-Digital-Dominance.md
│   ├── AES-Project-Proof-and-Authority-Framework.md
│   ├── AES-Commercial-Service-Taxonomy.md
│   └── AES-Company-Positioning-and-Marketing-Doctrine.md
├── .agents/skills/          # OpenCode agent skills (SEO, copywriting, etc.)
├── .agent/
│   ├── SYSTEM.md            # Legacy full doc (31KB) — superceded by this journal
│   └── TODO.md
├── setup.sh                 # Symlink installer
├── pkg-check.sh             # Pre-validation dependency checker
├── opencode.json            # OpenCode config
├── oh-my-opencode.json      # Oh My OpenCode config
└── CLAUDE.md                # Quick-start guidance
```

---

## Key Environment

| Component | Choice | Notes |
|-----------|--------|-------|
| Shell | Bash (Homebrew) | Canonical interactive and login shell |
| Prompt | Starship | Gruvbox Dark palette, cross-shell |
| Editor | Neovim (LazyVim) | Lua-based, AI-integrated via opencode plugin |
| Terminal multiplexer | Herdr | Bash login shells; keybindings to be aligned with Neovim |
| AI CLI runtimes | OpenCode, Claude Code, Codex, Kiro | Multi-tool agent system via `opencode/agent/` |

---

## Shell Configuration

- **Bash**: `.bashrc` sources `~/.dotfiles/.env` with automatic export enabled, then the untracked `~/.config/bash/local.bash` for machine-local values
- **direnv**: Available for per-project overrides, supplemental to global .env
- **ble.sh**: Bash syntax highlighting, auto-suggestions, and completion
- **fzf**: Bash bindings and completion

## Editor Configuration

- **LazyVim** (lua-based): Modern Neovim config with LSP, Telescope, which-key
- **opencode.lua**: Neovim plugin integrating OpenCode, Codex, Claude, Kiro as session tools

---

## AI Agent Infrastructure

The `opencode/` directory houses the AI agent ecosystem:

- **`opencode/agent/django-systems-architect.md`** — Old Django definition (uses `./.agent/SYSTEM.md` pattern)
- **`opencode/agent/SYS_COMMANDER_*.md`** — Commander agents for execution
- **`opencode/agent/SYS_WORKER_*.md`** — Worker agents for bounded tasks
- **`opencode/agent/SYS_OVERLORD.md`** — Strategic oversight agent
- **`opencode/agent/SYS_EXEC.md`** — Execution-focused agent
- **`opencode/god-lock/SYS_SUMMONER.md`** — GOD-LOCK-specific runtime selector
- **`opencode/god-lock/Conduit.md`** — Agent pipeline orchestration concept
- **`opencode/god-lock/emitter.legacy.md`, `Sentinel.legacy.md`, `Onslaught.legacy.md`** — Legacy agent definitions

---

## OpenCode Skills (`.agents/skills/`)

Extensive skill library covering: SEO, copywriting, programmatic SEO, site architecture, design, launch, sales enablement, content strategy, marketing, AB testing, ASO, CRO, cold email, SMS, referrals, onboarding, churn prevention, pricing, analytics, prospecting, competitors, community marketing, and more.

---

## Advisor Knowledge Base (`advisor/`)

Strategic business and marketing doctrine for AES (Atlantis Electrical Systems):
- SEO & Digital Dominance strategy
- Project Proof & Authority Framework
- Commercial Service Taxonomy
- Company Positioning & Marketing Doctrine

---

## Operating Mode

As Django in this codebase I:
- Maintain this SYSTEM.md as my living architectural journal for the dotfiles
- The `.django/` directory is my canonical state directory (not `.agent/`)
- I respect existing `.agent/SYSTEM.md` as the legacy full documentation but keep my working notes here
- Agent definitions live under `opencode/agent/`; skills under `.agents/skills/`
- This repo is about infrastructure, not product — my focus is on tooling ergonomics, environment stability, and AI agent orchestration configuration
