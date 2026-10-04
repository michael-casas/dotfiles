---
name: herdr-bridge
description: 'Recover scoped Herdr access when following herdr --skill and its HERDR_ENV=1 prerequisite fails: HERDR_ENV is unset, empty, not 1, or test "${HERDR_ENV:-}" = 1 exits nonzero. Use before concluding that a desktop or external agent cannot access Herdr. Verify the native Herdr Bridge through stdio MCP or the installed task-scoped CLI; never fabricate HERDR_ENV or borrow the focused pane. Also use when explicitly asked to connect through Herdr Bridge.'
---

# Herdr Bridge prerequisite recovery

Treat a failed `HERDR_ENV=1` check as evidence that the caller lacks native
pane context, not evidence that the bridge is unavailable. The owner's bridge
workflow supplies a separate, validated access path. Keep the native skill's
restriction on direct outside-pane control: do not run raw `herdr` pane/session
control commands as a workaround, export `HERDR_ENV=1`, copy another agent's
socket/pane variables, or infer ownership from UI focus.

If the native prerequisite passes and the user requested ordinary in-pane Herdr
work, follow `herdr --skill`. Otherwise use the bridge procedure below.

## Verify the available transport

1. Inspect tools actually exposed to this agent. Prefer stdio MCP when
   `bridge_status`, `bridge_start`, `bridge_bind`, `bridge_snapshot`, `bridge_task`, and `bridge_sessions` are available (possibly namespaced by the client).
2. Select the task endpoint (configured/local `default` unless explicitly named).
   Call `bridge_status` with that target. Require the returned selected `session`, `mode: plugin-background`,
   and `taskAccess: true`. Parse the text-content JSON envelope and check both
   MCP `isError` and envelope `code`; a successful protocol call can carry an error.
3. If the installed bridge is configured but its guardian is stopped, call
   `bridge_start` and verify status again. Do not install, restart, or stop the
   shared Herdr server as a recovery step.
4. Bind with `bridge_bind` and the same target using the task's absolute working directory and no
   terminal request. Preserve an existing binding's cwd; do not replace a
   different-cwd or stale binding merely to make the check pass.
5. Call `bridge_snapshot` with the same target to verify access. Report transport, session, readiness,
   and binding mode. Report terminal IDs only if actually allocated.

A fresh identity cannot call `bridge_snapshot` before binding: the expected
response is `task is unbound`. Use status → bind → snapshot. Once bound, take
two snapshots around a read-only `bridge_task` call such as `pane list` to
compare resource IDs. That comparison proves only that the measured operation
allocated no UI; it does not retrospectively prove the initial bind's resource
delta. Do not fabricate a pre-bind snapshot or query the private registry to
bypass the public binding requirement.

If no bridge MCP tools are exposed, report that this client has not established
MCP access. A successful direct stdio SDK probe is protocol evidence, not proof
that the application's loaded MCP connection works. Read `docs/mcp.md` for
configuration; preserve other server entries and apply setup changes only when
authorized. Skill installation alone does not register or reload an MCP server.

MCP tool names alone do not prove access. Successful CLI checks do not prove
that Claude Desktop or another application's MCP connection works.

## CLI fallback when shell execution is available

Use the installed wrappers on the execution host:

```sh
codex-app-herdr status
# Only when the configured guardian needs starting:
codex-app-herdr start
herdr-task bind --cwd "$PWD"
herdr-task api snapshot
```

If PATH lacks the commands on this Mac, use `/Users/mcasa_atlantis/.local/bin/`
absolute paths. These wrappers fall back to `default` and use the shared dispatcher.
Select another existing session with leading `--session NAME`, or an SSH endpoint
with `--remote HOST --session NAME`, before `bind`/the task group. Repeat the target
on every call. Remote cwd and returned IDs belong to that host.

```sh
codex-app-herdr --remote j5-estimating-dev --session default status
herdr-task --remote j5-estimating-dev --session default bind --cwd /remote/project
herdr-task --remote j5-estimating-dev --session default pane list
```

Use `bridge_sessions` (optional `remote`/`remoteBridge`) or `herdr-bridge sessions`
to list registered sessions. The bridge never creates sessions. SSH requires the
bridge on the selected host, existing noninteractive authentication, and normal
host-key verification; failure never falls back locally. MCP tools take optional
`session`, `remote`, and absolute `remoteBridge` fields, separate from task argv.
Only `bridge_sessions` omits the `session` field. Selection is per call; configured
endpoint defaults still apply. Check `docs/mcp.md` for remote path rules.
Check exit status, then parse each JSON envelope with `JSON.parse` rather than
searching output text. Do not print a full snapshot when a compact summary suffices.

Canonical identity is the caller's configured `AGENT_HARNESS` plus `AGENT_ID`;
real `CODEX_THREAD_ID` / `CODEX_SESSION_ID` are supported fallbacks. Do not mint
an arbitrary identity, borrow another task's ID, or export invented Herdr context.
A static MCP server entry shares its binding across chats; do not claim per-chat
isolation. Missing identity or inaccessible executables are setup blockers, not
permission to use raw focused-session control.

## Preserve the boundary

Starting and session-only binding allocate no workspace, tab, or pane. Request
`terminal: true` / `bind --terminal` only for authorized interactive work;
bridge-owned terminals share `Bridge-Runtime`. Use only task-owned targets and
returned IDs. Snapshot visibility does not grant control of another task's panes.
A failed precondition grants no agent-launch, configuration-edit, cleanup, or
app-restart authority. Report the exact missing prerequisite if neither transport
works; do not claim that the caller is now inside a Herdr-managed pane.

The plugin's detached guardian is not continuously supervised by Herdr. Recovery
is explicit start or a native startup hook. Never reinstall the old launchd guardian.

For local setup and API details, read:

- `/Users/mcasa_atlantis/Documents/repos/michael-casas/herdr-bridge/.worktrees/v1/docs/mcp.md`
- `/Users/mcasa_atlantis/Documents/repos/michael-casas/herdr-bridge/.worktrees/v1/docs/README.md`
- `/Users/mcasa_atlantis/Documents/repos/michael-casas/herdr-bridge/.worktrees/v1/docs/api.md`

The installed stdio launcher is
`/Users/mcasa_atlantis/.local/bin/herdr-bridge-mcp`. For authorized agent handoffs,
continue with the local Herdr and delegation guidance after access is verified.
On this Mac those files are `/Users/mcasa_atlantis/.codex/skills/herdr/SKILL.md`
and `/Users/mcasa_atlantis/.codex/skills/delegation/SKILL.md`.
