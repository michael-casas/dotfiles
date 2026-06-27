# AES Trust Campaign Pattern — 4-Pass Sequential Execution

> Proven June 17, 2026 during the AES iqne Trust Framework campaign
> (4 passes, ~18 minutes total agent time, ~$3 Opus cost + GPT 5.5/5.4 quotas).
> Use this as the template for any campaign that needs to: (a) build
> durable foundations, (b) ground an existing spec against them,
> (c) produce a reusable rubric, (d) execute per-page/per-archetype.

## When to Use This Pattern

- The campaign needs **reusable building blocks** (recipes, contracts, components) that downstream agents will compose
- An existing framework document uses **prose variants** (e.g. "Split + supporting List") that need to be **grounded to on-disk primitives** (e.g. `SPLIT_MEDIA.ts`)
- A **durable rubric** needs to be produced that will be loaded by every future agent on this work
- The execution is **per-archetype** (page-by-page, route-by-route) with each archetype shipping independently

**Don't use this pattern for:**
- Single-file changes (just patch directly)
- Pure research tasks (use `research-convergence` directly)
- Specs that ship as one batch (no per-archetype independence)

## The 4-Pass Structure

```
Pass 1 (Foundation)  →  Pass 2 (Ground)  →  Pass 3 (Rubric)  →  Pass 4+ (Execute)
   recipes              spec-doc             durable skill        per-archetype
   locked files         patch cells          loaded per agent     sweep one at a time
```

| Pass | Goal | Output | Model Tier | Why |
|------|------|--------|------------|-----|
| **1. Foundation** | Build the locked recipes / components that everything else composes | N `.ts` recipe files + 1-2 primitive patches + 1 page DTO demonstrating the pattern | GPT 5.5 high (xhigh if available) | High-judgment work: turning prose into structured variant grammar, identifying what reusable shapes to extract |
| **2. Ground** | Patch the existing spec/framework document to reference the new primitives | One markdown file patched: every prose cell → file reference + rename stages per invariant + enforce link-graph rules | GPT 5.4 medium | Mechanical but voluminous: 60-100 cells to patch with evidence-backed file:line citations |
| **3. Rubric** | Produce a durable skill that downstream agents load | One `SKILL.md` (≤250 lines) + optional `references/` (no cap) | Opus (1M context, xhigh) | High-judgment governance: encode 4 invariants + 7 rules + per-archetype overlay + failure-mode matrix. Opus earns the cost because the rubric compounds across every archetype |
| **4. Execute** | Per-archetype sweep: DTO patch + copy + visual verify | One patched page DTO + PROGRESS.md updated | Sonnet (1M context) | Highest-trust copy work: DTO mapping + trust-aligned prose. Sonnet is the superior copy writer per Founder evidence |

## Why Sequential, Not Parallel

The 4 passes have hard dependencies:

- Pass 2 needs Pass 1's recipes to exist (it references them by filename)
- Pass 3 needs Pass 2's grounded spec (it cites stage names + DTO files)
- Pass 4 needs Pass 3's rubric (it loads the skill on agent turn opening)

**You can parallelize Pass 1 across multiple recipes** (5 files in parallel via GPT 5.5 dispatches) — but Pass 2, 3, 4 are strictly sequential.

**Pass 4 is parallelizable across archetypes** — once one archetype ships, the next can ship while visual verification happens. Each archetype is its own Sonnet session.

## Pre-Flight Scaffolding (CRITICAL — Founder directive)

Before Pass 3 (rubric production), patch the brand/source-of-truth files so the high-judgment agent has current grounding. Examples from the AES campaign:

- Patched `BRAND.minimal.md` with the Real Funnel, 4 Client Avatars, 4 Copy Invariants, 5 Named Proof Assets BEFORE Opus ran. Without this, Opus would have produced a generic rubric.
- Patched `FRAMEWORK.md` with the 5th invariant (List must be in Split) BEFORE Pass 2 ran.
- Patched `SKELETON_GRAPH.md` with the stage renames BEFORE Pass 2 grounded it.

**The discipline:** if a high-judgment agent will reference a brand/framework/spec file during its run, that file must be current at the start of the run. Patch scaffolding before firing agents, not after.

## Skill Loading Pattern (Load-Once)

The rubric skill (Pass 3 output) is loaded **once on agent turn opening**, not per section. Pattern:

```
First 100 tokens: "Skill loaded. N rules internalized. Per-archetype overlay loaded."
Then: reference rules by ID in commit messages, never re-read SKILL.md per section
References/ files: read once at turn opening; reference by name if needed mid-run
```

**Why:** the rubric is stable. Per-section re-reads are 100% redundant overhead. With Sonnet's 1M context, the 133-line SKILL.md costs nothing.

## Skill Location Convention

The rubric skill lives at a **canonical path matching the tool that auto-loads it:**

```
<project>/.claude/skills/<skill-name>/SKILL.md   # Sonnet / Claude Code auto-loads
<project>/.claude/skills/<skill-name>/references/  # optional, loaded on explicit request
```

Not at `.agent/campaigns/<campaign>/` (that's the spec, not the skill).
Not at `~/.hermes/skills/` (that's global, not worktree-scoped).

The project-scoped path means: versioned with the worktree, deletable when the campaign ends, available to any agent that runs in that worktree.

## Tracking Progress Across Passes

Every campaign uses a `PROGRESS.md` at `iqne/.agent/campaigns/<campaign>/PROGRESS.md` (or equivalent). Shape:

```markdown
## A3.2 — ARCH-IND-HUB (`/industries`) — Sonnet target first
- [ ] S1 | 01 CONNECTION — `HERO_MEDIA.ts` + copy
- [ ] S2 | 02 BUYER-ID — `INDUSTRIES_GRID.ts` + copy
- [ ] S3 | 07 AUTHORITY — `SPLIT_MEDIA.ts` + copy
- [ ] S4 | 03 PROOF — `PROJECT_CASE_STUDIES.ts` + copy
- [ ] S5 | 08 CONVERSION — `CTA_SECTION.ts` + subline
```

Mark `[x]` when both phases ship + visual verify passes. Update per section, per archetype. Provides at-a-glance campaign state.

## Charter Shape Per Pass

Each pass gets a charter file at `~/.hermes/.django/_commands/<pass-id>-<model>-<job>.md`. The charter is **path-referenced** via cmux (never inline-pasted into the prompt). Structure:

```markdown
# Pass N — [Model] on [Job]

## Mission
One sentence: what this pass produces.

## Surface
cmux surface ref, model, working directory.

## READS (in order, before any writes)
1. <file> — why read
2. <file> — why read

## DELIVERABLE
The single artifact this pass ships.

## HARD CONSTRAINTS
- No new dependencies
- No new section types (if applicable)
- TypeScript strict
- Do not modify X

## VALIDATION
```bash
pnpm typecheck:app
```
Expected: exit 0.

## FINAL REPORT
What to reply with (5 sections, ≤1500 chars, terse).
```

## Concrete Worked Example (AES Trust Campaign 2026-06-17)

| Pass | Charter file | Time | Cost | Output |
|------|-------------|------|------|--------|
| 1 | `pass1-gpt55-recipes.md` | 6m 14s | GPT 5.5 quota | 5 recipes + LogoMark patch + divisions hub S2 (7 deliverables) |
| 2 | `pass2-gpt54-ground-skeleton.md` | 4m 26s | 839K input tokens | `SKELETON_GRAPH.md` patched (80 cells, 3 stage renames, 1 CTA link-role fix) |
| 3 | `pass3-opus-trust-copy-skill.md` | 4m 11s | $2.53 | `iqne/.claude/skills/trust-based-copywriting/SKILL.md` (133 lines) + 2 references |
| 4 | `pass4-sonnet-industries-hub.md` | TBD | TBD | `/industries` hub sweep (5 sections, 2-phase each) |

**Total: 4 charters, ~18m agent time + scaffold prep, ~$3 + model quotas.**

## Pitfalls

- **Don't skip the scaffolding pre-flight.** Firing Opus without current brand files produces a rubric that drifts from the actual brand. 5 minutes of scaffolding before Pass 3 saves hours of post-hoc rubric patching.
- **Don't run Pass 2 before Pass 1 finishes.** Pass 2 references Pass 1 outputs by filename. If Pass 2 fires first, it cites files that don't exist.
- **Don't load the skill per-section in Pass 4.** Sonnet's context is large; SKILL.md is small; load once, internalize, reference by ID.
- **Don't make Pass 3 the foundation.** The rubric encodes the framework — it's not the foundation. The foundation is the locked recipes (Pass 1). The rubric (Pass 3) tells agents how to USE the foundation.
- **Don't ship Pass 4 without visual verification.** Browser-harness verification of each archetype is the gate. Sonnet self-certifies "looks good" — that's not evidence.

## 2-Layer Token Architecture (Theme.css + Raw Tailwind) for Page Quarantine

**Proven 2026-06-19 during /contact visual migration prep.** When a campaign needs page-specific sections outside the owned design-system seam and the design system has gaps, the architecture is:

- **Layer 1: theme.css tokens** — existing primitives only (`font-display`, `text-display-xl`, `bg-surface-alt`, `text-accent`, etc.). Read-only, do not extend during the campaign.
- **Layer 2: raw tailwind utility classes** — fills gaps where theme.css has no primitive. Document each gap in a comment in the section file (what primitive is missing, why raw tailwind was used).
- **Page quarantine:** new sections live at `<worktree>/src/app/pages/<route>/sections/` (NOT in `src/design-system/`). They MAY import design-system primitives by name. They MAY use raw tailwind for gaps. They MUST NOT add new tokens to theme.css (theme is bloated).
- **Optional 1-token cap:** if a brand-tinted shadow is genuinely needed (e.g. focal form card lift) and no design-system primitive exists, AT MOST 1 new shadow token may be added. Document the cap explicitly in the ATDD spec's expansion grants.

**Why this matters for campaigns:** the design system is owned and changes slowly. Campaign work (visual migration, new pages, redesigns) often needs visual expression the design system doesn't cover. Without a clear token architecture, campaigns either (a) bypass the design system with raw tailwind everywhere (loses consistency), or (b) wait for design system to catch up (campaign stalls). The 2-layer quarantine lets campaigns ship without bloating the design system.

**Anti-pattern:** adding new tokens to theme.css during a campaign because "we'll need this for the new section." Token additions belong in a separate, owned design-system pass — not in the campaign's commit history.

## L0 → L1 Codex-Ground-Then-Opus-Execute Pattern (Two-Stage Sequential)

**Proven 2026-06-19 during /contact visual migration prep.** When a high-judgment agent (Opus, T4) needs a Context Burst to execute an ATDD spec, the pattern is:

```
L0 (Codex, GPT 5.4)  →  L1 (Opus, T4)
  ground the working doc    execute the ATDD spec
  rewrite the .md in place  reads ATDD + grounded .md + visual target
  MUST finish first         MUST NOT start until L0 lands
```

**Why L0 is needed:** Opus (T4) is too expensive to spend context on repo archaeology. Codex (GPT 5.4) is the right tier for mechanical grounding work: read existing files, quote real paths/tokens/props, write a working doc that maps the ATDD spec to repo reality.

**L0 charter shape (Codex grounding task):**
- Working directory: `<worktree>` (the iqne worktree, NOT the annex-target)
- INPUT FILES (read all): visual source HTML, current implementation file, design-system surface, theme.css token names, the ATDD spec (DO NOT MODIFY)
- OUTPUT FILE (rewrite in place, ONE file only): the grounded working doc with sections like "Visual Source Summary", "Per-Section File Paths + Props + Tokens", "Surfaces Opus Will Touch (create/modify/HARD-NO-touch)", "Pre-Flight Verification", "Trust Framework Constraints"
- HARD PROHIBITIONS: no JSX, no design-system modifications, no new theme.css tokens, no spinning up dev server/storybook
- RESULT BLOCK: file rewritten + line counts + files NOT touched (verified by `git diff`) + quoted real paths/tokens from the repo

**L1 charter shape (Opus execution task):** see Section 5 of any ATDD spec — pre-flight reads, strict section-then-assembly-then-wiring order, expansion grants with caps, scope audit on completion.

**Critical: L0 → L1 is SEQUENTIAL, NOT PARALLEL.** Opus will produce wrong work if it runs before L0 grounds the repo context. Founder directive 2026-06-19: "Remember L0 → L1 IN SEQUENCE — NOT PARALLEL." L1 cannot start until L0's RESULT block is confirmed.

**Pre-fire surface verification (both stages):**
```bash
# Find the active surface
cmux tree --all | grep -A2 "Active Worktree"

# Verify the surface is idle at the prompt (NOT generating)
cmux read-screen --workspace workspace:N --surface surface:M

# Verify dev server / storybook are running (use them, do not spin up your own)
curl -s -o /dev/null -w "%{http_code}" http://localhost:5173/<route>  # must return 200
curl -s -o /dev/null -w "%{http_code}" http://localhost:6006  # must return 200

# Verify chrome-devtools-cli is available
which chrome-devtools-cli  # must return a path
```

If any of these fails, HALT and surface to Founder. Do NOT spin up your own servers.

## Visual-Gate Tooling — `chrome-devtools` MCP, NOT a CLI (Pitfall, 2026-06-19)

**The wrong reference (DO NOT WRITE):** "verify with `chrome-devtools-cli`". `chrome-devtools-cli` does not exist as a standalone binary. The actual tool is the `chrome-devtools` MCP server wired in `~/.codex/config.toml` (lines ~152-178):

```toml
[mcp_servers.chrome-devtools]
command = "npx"
args = [ "chrome-devtools-mcp@latest" ]

[mcp_servers.chrome-devtools.tools.<each_tool>]
approval_mode = "approve"
```

MCP tools available (all pre-approved, no per-call prompt):
- `navigate_page(url)` — load a URL
- `take_screenshot(path)` — full-page PNG
- `evaluate_script("...")` — DOM queries, computed style checks
- `emulate({feature, value})` — hover, prefers-reduced-motion, viewport
- `resize_page({width, height})` — viewport breakpoints
- `click(ref)` — interaction

Storybook MCP at `http://localhost:6006/mcp` exposes `run-story-tests` (also pre-approved).

**Spec / charter authoring rule:** when writing any visual ATDD spec, charter, or agent prompt that wants browser verification, name the specific MCP tools (`navigate_page → take_screenshot → evaluate_script → emulate`) and reference the config file path. Do NOT say "use chrome-devtools-cli" — that tool does not exist and the agent will fail to find it.

## Pre-Flight Gates Belong to Django, NOT the Agent (Pitfall, 2026-06-19)

**The wrong pattern (DO NOT WRITE):** "Opus runs `curl http://localhost:5173/contact` as the first pre-flight step." Codex in `~/.codex/config.toml` runs in `sandbox_mode = "workspace-write"` with `[sandbox_workspace_write] network_access = false` (line ~13). The sandbox blocks outbound network — including to localhost — even when the dev server is fully up in Founder's shell. Codex's `curl` returned `000` and reported it as a blocker; the actual cause was sandbox, not a missing server.

**The same restriction likely applies to Opus** running in a TUI sandbox. The agent cannot reliably verify localhost pre-conditions from inside its sandbox.

**Spec / charter authoring rule:** in any ATDD spec / charter that lists pre-flight gates:

- Frame pre-flights as **Django / Founder-runtime gates, not agent gates**: "Django runs these BEFORE dispatching the agent. The agent inherits the green pre-flight."
- Move the actual `curl` commands into Django's dispatch protocol, not the agent's body
- The agent's only pre-flight responsibility is: read the materials listed, then check that the inherited pre-flight is green (don't re-verify). If at any point during the run the dev server or storybook dies, the agent surfaces the failure with file:line evidence and HALTs — does not silently restart or fall back.

**Applies to:** any ATDD spec, any charter, any agent prompt that wants the dispatched agent to verify localhost services before starting work. Move pre-flights to the orchestrator's dispatch protocol, not the agent's job.

## Charter File Location (Project-Scoped Default)

**Founder directive 2026-06-19:** charters for iqne worktrees live at:

```
<worktree>/.agent/django/commands/<charter-name>.md
```

NOT at `~/.django/_commands/` (that's session-scoped).
NOT mirrored to `~/.hermes/.django/_commands/` (the codex `external_directory` dodge is NOT needed — iqne worktree paths are pre-allowed in the Codex surface config).

**When to use which:**
- `<worktree>/.agent/django/commands/` — DEFAULT for any charter tied to a specific worktree (iqne, annex-target, etc.). Versioned with the worktree. Survives session changes.
- `~/.django/_commands/` — for cross-worktree session-scoped dispatches (rare). Mirror to `~/.hermes/.django/_commands/` if dispatching to a codex surface that doesn't have the worktree pre-allowed.
- `~/.hermes/.django/_commands/` — mirror target only, not primary.

**Path-reference dispatch (always):** write charter to disk, send `cmux send --workspace W --surface S 'read /abs/path/to/charter.md and execute exactly as instructed'`. Never inline-paste charters ≥2K chars into the cmux prompt.

## Related

- `atdd` — the umbrella; this pattern extends the spec → implement pipeline into a 4-pass campaign structure
- `model-routing` — see `references/campaign-tier-routing.md` for the tier choices from this campaign
- `meta-orchestration` — for multi-package / multi-domain campaigns at a higher tier
- `god-lock-mothership` — when the campaign is part of a kernel/compiler/walker migration