---
name: agent-wiki
description: Use when the user asks to read from, search, summarize, link, publish to, curate, or contribute to the shared Agent Wiki vault, including standards, governance docs, skills, and reusable agent knowledge. Agent reads use the headless `wiki` CLI and remain read-only by default; always ask for explicit user approval before creating, editing, moving, or deleting a Wiki note.
---

# Agent Wiki

Use the headless `wiki` CLI for Agent Wiki reads, retrieval, graph inspection, and local index health.

## Vault and index

- Vault name: `Agent Wiki`
- Default vault: `/Users/mcasa_atlantis/Documents/vaults/Agent Wiki`
- Default index: `~/.pi/agent/wiki-index/agent-wiki.sqlite`
- Vault override: `--vault <path>` or `WIKI_VAULT`
- Read tool: `wiki`

`wiki reindex` writes only the local SQLite projection. It does not modify Wiki notes.

## Headless read law

- Agents MUST use `wiki` for Agent Wiki reads.
- Agents MUST NOT invoke an Obsidian CLI, open or focus Obsidian.app, or route reads through an Obsidian process.
- Agents MUST NOT fall back to ad-hoc vault greps when `wiki` can answer the request.
- If `wiki` is unavailable or unhealthy, run the recovery sequence below. If recovery fails, report the concrete failure rather than launching a GUI-backed tool.

## Read workflow

Start by checking the projection:

```bash
wiki status --json
```

Build or refresh it when missing or stale:

```bash
wiki reindex
# Use only when replacing a stale/mismatched projection:
wiki reindex --full
```

Use exact retrieval for known notes and lexical retrieval for discovery:

```bash
wiki get "Clean Code" --json
wiki search BATDD --scope standards -k 10 --json
wiki context --seed BATDD --max-tokens 2000 --json
```

Inspect graph and health through the same headless surface:

```bash
wiki links BATDD --json
wiki backlinks BATDD --json
wiki unresolved --json
wiki orphans --json
wiki doctor --json
```

Prefer `--json` when another agent or script consumes the result. Human-readable output is suitable for direct terminal use. Context `estimatedTokens` is a conservative word/punctuation estimate, not model-specific tokenization; leave headroom for the receiving model.

## Recovery sequence

1. Run `wiki status --json` and verify the selected vault/index paths.
2. Run `wiki doctor --json` for schema, vault-identity, and unresolved-link health.
3. Run `wiki reindex`; use `--full` only for an explicitly stale or mismatched projection.
4. Retry with `--vault <path>` when the request targets a non-default vault.
5. If the binary itself is missing, report that the Agent Wiki CLI must be installed or linked on PATH. Do not substitute a GUI-backed reader.

## Permission model

- Agents always have read permission on the Agent Wiki.
- Agents must always ask for explicit user approval before any write action in the vault.
- Write actions include create, append, prepend, move, rename, delete, property mutation, or any operation that changes note contents, metadata, or structure.
- Do not treat implied intent as approval.
- `wiki` v1 is read-only and cannot publish. After approval, use only the write mechanism explicitly authorized by the user. If no mechanism is named, ask before proceeding.

## Publishing standard

The Agent Wiki is the durable knowledge layer for reusable agent context.

- Put ratified doctrine, laws, constitutions, and cross-repo standards in `standards/`.
- Put low-frequency operational knowledge, tool playbooks, and reusable procedures in `skills/`.
- Keep authoritative source material in its origin repo when one exists. The Wiki note is the graph node, summary, and discovery surface.
- Use Title Case note names and stable lowercase folder names.
- Every published note must link to at least one hub note and at least one related note.

Current hubs:

- `Agent Wiki Home.md`
- `Skills.md`
- `Standards.md`

## Approved-write workflow

When the user asks to add or update Wiki knowledge:

1. Read source material through the appropriate source tool.
2. Inspect existing notes and graph relationships with `wiki`.
3. Ask for explicit approval before drafting or publishing.
4. After approval, use only the user-authorized write mechanism.
5. Refresh and verify the projection:

```bash
wiki reindex
wiki links "<note>" --json
wiki backlinks "<note>" --json
wiki unresolved --json
wiki orphans --json
wiki doctor --json
```

## Suggested note shape

Prefer compact notes with clear provenance and graph links.

```yaml
---
type: skill | standard | hub | index
status: active | seeded | draft
source_repo: <repo-name>
source_path: <repo-relative-path>
tags:
  - skills
  - standards
---
```

Typical related-links block:

```md
## Related

- [[Agent Wiki Home]]
- [[Skills]]
- [[Standards]]
```
