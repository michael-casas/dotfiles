# dotfiles-sync

Keeps the production checkout (`~/.dotfiles`) at `origin/main`, so a PR merged
on GitHub reaches every running nvim: nvim's hot reload (`nvim/lua/hcmux/hotreload.lua`)
watches the checkout and reloads, or shows a toast.

| File | What it is |
|---|---|
| `dotfiles-sync` | one sync: `run` (quiet, periodic), `now`, `status` |
| `dotfiles-sync-agent` | `install` / `uninstall` / `render` / `status` for the macOS LaunchAgent |
| `dotfiles-sync.plist.in` | the LaunchAgent template; `@TOKENS@` are rendered from `$HOME` at install |
| `test/run.sh` | sandbox tests (temp `HOME`, bare origin, production clone) |

## What a sync does

1. Skips (exit 3) unless the checkout is on `main` with no merge, rebase or
   cherry-pick in progress, or while another sync holds the lock.
2. `git fetch origin main` (no tags, no submodules, no auto gc).
3. Nothing to do when `main` already equals or is ahead of `origin/main`.
   Diverged: `refused`, exit 1.
4. **Blocked** (exit 1, nothing changes) when the update would touch a path that
   isn't clean locally: a tracked file that is modified, staged or deleted, or an
   untracked or ignored file where the update adds one. The result names the
   paths: `blocked local changes in nvim/lua/plugins/neo-tree.lua`.
5. Otherwise `git merge --ff-only --no-autostash origin/main`. Local changes to
   other paths stay as they are. If git still refuses, its reason is logged as
   `refused`.

It never stashes, resets, checks out over changes, or touches untracked files.
Resolving a block is the owner's call: commit, move or drop the local change,
and the next run catches up.

**State:** `${XDG_STATE_HOME:-~/.local/state}/dotfiles-sync/`:
- `last` holds the latest result, one line: `<UTC time> <result> <detail>`.
  `:EnviHotReload status` shows it.
- `sync.log` gets a line only when the result changes, or on every sync, so idle
  minutes add nothing. It rotates to `sync.log.1` past 256 KiB.
- `launchd.log` holds launchd's stdout and stderr, capped the same way.

## Install (macOS)

```sh
~/.dotfiles/sync/dotfiles-sync-agent install     # writes + loads ~/Library/LaunchAgents/local.dotfiles-sync.plist
~/.dotfiles/sync/dotfiles-sync-agent status      # launchd state + last result
~/.dotfiles/sync/dotfiles-sync now               # right after merging a PR
~/.dotfiles/sync/dotfiles-sync-agent uninstall   # unload + remove
```

The agent runs `/bin/bash ~/.dotfiles/sync/dotfiles-sync run` at login and every
60 s, at low priority. Since it runs the checkout's own copy, it updates itself
with each fast-forward.

## Linux

Use a systemd user timer in place of the LaunchAgent:

```ini
# ~/.config/systemd/user/dotfiles-sync.service
[Service]
Type=oneshot
ExecStart=%h/.dotfiles/sync/dotfiles-sync run

# ~/.config/systemd/user/dotfiles-sync.timer
[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
[Install]
WantedBy=timers.target
```

Then run `systemctl --user enable --now dotfiles-sync.timer`.
