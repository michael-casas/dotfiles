# Visual-Gate Tooling and Pre-Flight Pitfalls

> Captured 2026-06-19 during /contact visual migration prep.
> Two load-bearing lessons that bit during a real Codex (gpt-5.4) grounding run
> and would have bit again on Opus's execution pass. Encode so future specs
> don't repeat.

## Pitfall 1 — `chrome-devtools-cli` Does Not Exist (Use the MCP Server)

**The wrong reference:** "verify with `chrome-devtools-cli`" or "run `chrome-devtools-cli` to take a screenshot." That CLI does not exist as a standalone binary.

**The actual tool:** the `chrome-devtools` MCP server is wired in `~/.codex/config.toml` (lines ~152-178) like this:

```toml
[mcp_servers.chrome-devtools]
command = "npx"
args = [ "chrome-devtools-mcp@latest" ]

[mcp_servers.chrome-devtools.tools.new_page]
approval_mode = "approve"

[mcp_servers.chrome-devtools.tools.take_snapshot]
approval_mode = "approve"

[mcp_servers.chrome-devtools.tools.evaluate_script]
approval_mode = "approve"

[mcp_servers.chrome-devtools.tools.navigate_page]
approval_mode = "approve"

[mcp_servers.chrome-devtools.tools.take_screenshot]
approval_mode = "approve"

[mcp_servers.chrome-devtools.tools.emulate]
approval_mode = "approve"

[mcp_servers.chrome-devtools.tools.click]
approval_mode = "approve"

[mcp_servers.chrome-devtools.tools.resize_page]
approval_mode = "approve"
```

Every tool is `approval_mode = "approve"` — no per-call permission prompts.

Storybook MCP is wired at `http://localhost:6006/mcp` exposing `run-story-tests` (also pre-approved).

### MCP tools agents should invoke

- `navigate_page(url)` — load a URL
- `take_screenshot(path)` — full-page PNG
- `evaluate_script("...")` — DOM queries, computed style checks
- `emulate({feature, value})` — hover, prefers-reduced-motion, viewport
- `resize_page({width, height})` — viewport breakpoints
- `click(ref)` — interaction

### Spec / charter authoring rule

When writing any ATDD spec, charter, or agent prompt that wants browser verification:

1. Name the specific MCP tools (`navigate_page → take_screenshot → evaluate_script → emulate`) the agent should invoke.
2. Reference the config file path so the agent can verify wiring: `~/.codex/config.toml` lines 152-178.
3. Do NOT say "use chrome-devtools-cli" — that tool does not exist and the agent will fail to find it.

## Pitfall 2 — Pre-Flight Gates Belong to Django, NOT the Agent

**The wrong pattern:** "Opus runs `curl http://localhost:5173/contact` as the first pre-flight step."

**The failure mode:** Codex (gpt-5.4) in `~/.codex/config.toml` runs in `sandbox_mode = "workspace-write"` with `[sandbox_workspace_write] network_access = false` (line ~13). The sandbox blocks outbound network — including to localhost — even when the dev server is fully up in Founder's shell. Codex's `curl localhost:*` returned `000` and reported it as a blocker; the actual cause was sandbox, not a missing server.

**The same restriction likely applies to Opus** running in a TUI sandbox. The agent cannot reliably verify localhost pre-conditions from inside its sandbox.

### Spec / charter authoring rule

In any ATDD spec / charter that lists pre-flight gates:

1. **Frame pre-flights as Django / Founder-runtime gates, not agent gates.** "Django runs these BEFORE dispatching the agent. The agent inherits the green pre-flight."
2. **Move the actual `curl` commands into Django's dispatch protocol, not the agent's body.** Django runs them in Founder's unrestricted shell before the dispatch fires.
3. **The agent's only pre-flight responsibility is:** read the materials listed in the spec, then check that the inherited pre-flight is green (don't re-verify). If at any point during the run the dev server or storybook dies, the agent surfaces the failure with file:line evidence and HALTs — does not silently restart or fall back.

### What Django runs in the dispatch protocol (before any fire)

```bash
# Dev server check
curl -s -o /dev/null -w "%{http_code}" http://localhost:5173/<route>  # must return 200

# Storybook check
curl -s -o /dev/null -w "%{http_code}" http://localhost:6006  # must return 200

# Surface idle check (read-screen before send — hard rule for any cmux send)
cmux read-screen --workspace workspace:N --surface surface:M  # must be at clean idle prompt, not generating
```

If any of these fails, HALT and surface to Founder. Do NOT spin up your own servers.

## Pitfall 3 — L0 → L1 Is Sequential, NOT Parallel

**The pattern:** when dispatching Opus (T4, hired gun) on high-judgment work that requires a Context Burst, run a Codex (gpt-5.4) grounding pass FIRST.

```
L0 (Codex, GPT 5.4)  →  L1 (Opus, T4)
  ground the working doc    execute the ATDD spec
  rewrite the .md in place  reads ATDD + grounded .md + visual target
  MUST finish first         MUST NOT start until L0 lands
```

**Why L0 is needed:** Opus (T4) is too expensive to spend context on repo archaeology. Codex (GPT 5.4) is the right tier for mechanical grounding work — read existing files, quote real paths/tokens/props, write a working doc that maps the ATDD spec to repo reality.

**Why L1 cannot start until L0 lands:** Opus's first-turn read becomes efficient only when the grounding is already on disk. Without L0, Opus either (a) does its own repo archaeology in expensive T4 context, or (b) reads CONTACT.md and finds prose variants not grounded to actual file paths — both wastes Opus's budget.

**Founder directive 2026-06-19:** "Remember L0 → L1 IN SEQUENCE — NOT PARALLEL."

### L0 charter shape (Codex grounding task)

- **Working directory:** `<worktree>` (the iqne worktree, NOT a sibling annex)
- **INPUT FILES (read all):** visual source HTML, current implementation file, design-system surface, theme.css token names, the ATDD spec (DO NOT MODIFY)
- **OUTPUT FILE (rewrite in place, ONE file only):** the grounded working doc with sections like "Visual Source Summary", "Per-Section File Paths + Props + Tokens", "Surfaces Opus Will Touch (create/modify/HARD-NO-touch)", "Pre-Flight Verification", "Trust Framework Constraints"
- **HARD PROHIBITIONS:** no JSX, no design-system modifications, no new theme.css tokens, no spinning up dev server/storybook
- **RESULT BLOCK:** file rewritten + line counts + files NOT touched (verified by `git diff`) + quoted real paths/tokens from the repo

### L1 charter shape (Opus execution task)

See Section 5 of any ATDD spec — pre-flight reads, strict section-then-assembly-then-wiring order, expansion grants with caps, scope audit on completion.

## Related

- `references/aes-campaign-pattern.md` — 4-pass sequential campaign pattern; L0→L1 fits as Pass 0 (grounding) before Pass 1 (foundation).
- `aes-iqne-trust-framework` — the cross-agent judgment skill for AES iqne content work; referenced in L0's grounding for trust-framework constraints.
- `agent-charter-crafter` — the charter-writing discipline for codex / claude-code / opencode dispatches.