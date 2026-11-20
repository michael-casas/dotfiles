# Machine-local layers for Claude Code and OpenCode

This repository is public. Its tracked configs work on any machine and never
send a request or a credential to a private endpoint. Anything private or
machine-specific lives in untracked files that the owner creates by hand from
the templates below. Copying a template changes nothing until it is filled in
and opted into.

## Claude Code: gateway and auto-mode profile

The tracked `claude/settings.json` (linked to `~/.claude/settings.json`) sets no
`apiKeyHelper`, no `ANTHROPIC_BASE_URL` and no `autoMode` policy, so an ordinary
launch uses normal Claude authentication and the default auto-mode rules.

To route through a private gateway, keep the endpoint and its credential
together in one profile, and load it only from launches that opt in:

1. Copy `claude/local.settings.json.example` to
   `~/.config/claude/local.settings.json`. Set `env.ANTHROPIC_BASE_URL`, point
   `apiKeyHelper` at a key file you create with mode 0600, and replace or
   remove the `autoMode` section. Claude Code honours `autoMode` only from user
   settings, `--settings` or managed settings, not from a project's
   `.claude/settings.local.json`, so project-specific auto-mode policy also goes
   in this profile.
2. Opt in per launch: `claude --settings ~/.config/claude/local.settings.json`.
   The commented `claude()` function in `bash/local.bash.example` makes that
   the default for Bash shells on this machine. Claude Code started some other
   way (a GUI app, another shell) does not load the profile.

## OpenCode: private providers

The tracked `opencode/opencode.json` (inside `~/.config/opencode`) names only
public providers and local `localhost` endpoints. A private provider goes in
its own file, which OpenCode merges over the global config:

1. Copy `opencode/opencode.local.json.example` to
   `~/.config/opencode-local/opencode.json`, then set the provider's
   `baseURL`, key file and models.
2. Export `OPENCODE_CONFIG="$HOME/.config/opencode-local/opencode.json"` from
   `~/.config/bash/local.bash`. Without that variable, OpenCode does not load
   the provider and sends it nothing.

## Not part of the tracked config

- **Computer-use auto-enable hook.** Enable Claude's computer-use server per
  project, as the Claude Code docs describe. The repository does not rewrite
  `~/.claude.json` at session start.
- **Herdr agent-state hook.** `claude/settings.json` calls
  `~/.claude/hooks/herdr-agent-state.sh` only when Herdr's integration has
  installed it. Otherwise the hook exits 0 and does nothing.
