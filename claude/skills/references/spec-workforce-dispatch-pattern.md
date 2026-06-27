# Workforce Dispatch Pattern — Manager Economics & Notifications

Established June 7, 2026 during the initial workforce session.

## Profile Model Assignment

Managers use cheap models for coordination (reading docs, planning, delegating). Subagents are also cheap (deepseek-v4-flash) by current policy — the expensive Codex/GPT models are reserved for AES-only work.

| Profile | Manager Model | Subagent Model | Domain |
|---|---|---|---|
| `software-manager` | deepseek-v4-flash | deepseek-v4-flash | Architecture, code, implementation |
| `marketing-manager` | deepseek-v4-flash | deepseek-v4-flash | Content, SEO, campaigns, research |
| `product-design-manager` | deepseek-v4-flash | deepseek-v4-flash | UI/UX, design tokens, components |

**All models:** deepseek-v4-flash via OpenCode Go — $10/mo fixed subscription covers all inference.
**Legacy codex subagentry:** The original gpt-5.4 + openai-codex configuration was changed June 8, 2026 per Founder directive. Codex/GPT models may return for AES-specific work only.

Configured via each profile's `config.yaml`:

```yaml
model:
  default: deepseek-v4-flash       # manager's own model (cheap)
  provider: opencode-go

delegation:
  model: deepseek-v4-flash         # subagent model (same cheap pool)
  provider: opencode-go
  max_concurrent_children: 3
  max_spawn_depth: 2
```

## Pitfalls

- **Verify delegation.provider exists in Hermes config before assigning.** `delegation.provider: openai-codex` crashes subagent launches with "pid not alive" because no such provider is configured. The only working provider is `opencode-go`. Check `~/.hermes/config.yaml` for `providers: {}` to confirm no custom providers exist.
- **Agent crashes with "pid not alive" after config change.** If a Kanban task crashes twice with "pid not alive", check the profile's `delegation.provider` — if it references a non-existent provider, subagent processes fail silently on spawn. Fix the provider, unblock the task, and retry.

## Kanban Board Isolation

Use a separate kanban board per project:

```bash
hermes kanban boards create <slug> --name "<Display Name>" --icon <emoji>
hermes kanban boards switch <slug>
```

## Task Creation with Persistent Workspace

Scratch workspaces are deleted on completion. Use `--workspace dir:` to persist artifacts:

```bash
hermes kanban create "Task Title" \
  --assignee <manager-profile> \
  --body "ATDD spec or detailed instructions. See the atdd-spec skill for the required structure." \
  --workspace dir:/absolute/path/to/project
```

## Completion Notifications (Kanban-Notify)

A cron job every 2 minutes polls the kanban database for recently completed tasks and sends Discord notifications via browser-harness. This is the async callback mechanism — Django doesn't poll or sleep.

**Implementation:** `~/.hermes/scripts/kanban-notify.sh` (no_agent=true cron script)

The script:
1. Queries `~/.hermes/kanban.db` for tasks with `kind='completed'` events since the last check
2. Formats a Discord message with task id, title, and summary
3. Calls `post-to-discord.sh --hard "message"` which uses browser-harness to inject the message into Discord web
4. Updates the state file for the next tick

**Cron config:**
```json
{
  "schedule": "every 2m",
  "script": "kanban-notify.sh",
  "no_agent": true,
  "deliver": "origin"
}
```

## Expected Costs

At 2% rolling usage over 5 hours on OpenCode Go, a full week of continuous workforce operation costs approximately $0.50–$1.00 in inference. The $10/mo OpenCode Go subscription covers the manager models. Codex sub only fires when subagents need implementation capabilities.

At scale (5 clients, monthly content packages), total infrastructure cost is approximately $115/mo:
- $10 OpenCode Go (manager inference + marketing subagents)
- $20/client web hosting (Vercel)
- $30 Greptile (code review, future)
- $25 Railway/Fly.io (agent hosting)
- ~$30 one-off setup per client
