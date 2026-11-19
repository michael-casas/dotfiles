# dotfiles-sync

Keeps the production checkout (`~/.dotfiles`) at `origin/main`, so a PR merged
on GitHub reaches every running nvim: nvim's hot reload (`nvim/lua/hcmux/hotreload.lua`)
watches the checkout and reloads, or shows a toast.

| File | What it is |
|---|---|
| `dotfiles-sync` | one sync: `run` (quiet, periodic), `now`, `status`; `check` (is this a checkout it may update?) |
| `dotfiles-sync-agent` | `install` / `uninstall` / `render` / `status` for the macOS LaunchAgent |
| `dotfiles-sync.plist.in` | the LaunchAgent template; `@TOKENS@` are rendered from `$HOME` at install |
| `test/run.sh` | sandbox tests (temp `HOME`, bare origin, production clone) |

## What a sync does

1. **Checkout:** `DOTFILES_SYNC_REPO` must be the top of a **main checkout**: not
   a linked worktree, not a subdirectory (`error`, exit 1). The installer checks
   the same thing before it writes the plist.
2. **Lock:** takes an `flock` on `<checkout>/.git/dotfiles-sync.lock`.
   - It belongs to the checkout, not the log directory, so the scheduled run and
     `now` share it even when their state paths differ.
   - A periodic run skips quietly (exit 3) while another sync holds it; `now`
     waits up to 60 s.
   - The merge inherits the lock, so it stays held while the merge runs, even
     if the sync shell was killed.
   - The kernel releases it once all holders have exited or been killed, so
     there is never a stale lock to clean up.
3. **State check:** skips (exit 3) unless HEAD is `refs/heads/main` and no merge,
   rebase, cherry-pick, revert or bisect is in progress, with no `index.lock`.
4. `git fetch origin main` (no tags, no submodules, no auto gc). Then it checks
   step 3 again, and that `main` hasn't moved. If the branch was switched in
   the meantime, it skips: "… (the checkout changed during the sync)".
5. Nothing to do when `main` already equals or is ahead of `origin/main`.
   Diverged: `refused`, exit 1.
6. **Blocked** (exit 1, nothing changes) when the update would touch a path that
   isn't clean locally. Paths are read NUL-delimited and compared byte for
   byte, so non-ASCII names count too. A path counts when it is:
   - a tracked file that differs HEAD→index or index→worktree (staged, unstaged
     or deleted, even when the two cancel out);
   - an untracked or ignored file where the update adds one;
   - an untracked file where the update needs a directory.

   The result names the paths: `blocked local changes in nvim/lua/plugins/neo-tree.lua`.
7. It checks step 3 and `main` once more, then runs
   `git merge --ff-only --no-autostash --no-overwrite-ignore origin/main`.
   Local changes to other paths stay as they are. If git refuses, for example
   because an ignored file appeared in the way after step 6, its reason is
   logged as `refused`.

It never stashes, resets, checks out over changes, or touches untracked or
ignored files. Resolving a block is the owner's call: commit, move or drop the
local change, and the next run catches up.

**Out of scope: another process changing the checkout during a run.** If the
checkout is switched to another branch at the exact moment the merge starts,
git advances *that* branch. The production checkout stays on `main`; branches
belong in worktrees. The sync checks the result afterwards. If that happened,
it records `wrongbranch`, naming the branch, the old and new SHAs, and the way
back. `:EnviHotReload status` shows it as "sync moved the wrong branch: …".

```sh
git -C ~/.dotfiles reset --keep <old-sha>          # while that branch is checked out
git -C ~/.dotfiles branch -f <branch> <old-sha>    # once it is not checked out
```

`git branch -f` refuses a branch that is checked out, which is why the first
command comes first. `reset --keep` keeps your local changes, and refuses if
they would be lost.

**State:** `${XDG_STATE_HOME:-~/.local/state}/dotfiles-sync/`:
- `last` holds the latest result, one line: `<UTC time> <result> <detail>`.
  `:EnviHotReload status` shows it.
- `sync.log` gets a line only when the result changes, or on every sync, so idle
  minutes add nothing. It rotates to `sync.log.1` past 256 KiB.
- `launchd.log` holds launchd's stdout and stderr, capped the same way.
- The lock file is `<checkout>/.git/dotfiles-sync.lock`. It stays in place;
  the lock is the `flock` on it.

**Needs:** `git` and `perl`. macOS ships both in `/usr/bin`.

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
