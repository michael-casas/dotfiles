---
name: code-annexation
description: Analyze an external or project-local codebase, feature, repo, folder, or pasted code and decide what is worth annexing into the GOD-LOCK mothership Nx monorepo. Use when the user asks to annex, absorb, migrate, port, merge, salvage, harvest, consolidate, or evaluate code for reuse inside GOD-LOCK. Produces hard-judgment annexation reports, concept-first decisions, reusable package/domain targets, AES Directive/Op implementation plans, and optional worker lane documents. Pair with improve-codebase-architecture concepts such as module depth, interface, seam, adapter, leverage, locality, and the deletion test.
version: 1.0.0
metadata:
  hermes:
    tags: [code-annexation]
    category: engineering
---

# Code Annexation

Perform hard-judgment code annexation into the GOD-LOCK mothership. The default target is a TypeScript-first Nx monorepo with reusable packages, domains, apps, and execution tooling.

## Prime law

Annex concepts, not files.

Do not copy folders into GOD-LOCK merely because they exist. Preserve files only when they are already good candidates to adopt or lightly modify. Otherwise extract the concept, redesign the interface, and rebuild it as a clean GOD-LOCK package, domain module, seam, adapter, or reusable primitive.

## Mandatory posture

Be strict. The goal is not to save every artifact. The goal is to increase GOD-LOCK leverage, locality, readability, reuse, and long-term maintainability.

Reject code that is shallow, duplicated, vendor-leaky, over-specific, hard to test, or incompatible with GOD-LOCK architecture. Preserve vocabulary and ideas even when implementation is rejected.

Use the architecture vocabulary from `references/architecture-deepening.md` throughout: module, interface, implementation, depth, seam, adapter, leverage, locality, deletion test. For Battlefield topology and admission workflows, see `references/battlefield-pattern.md`.

## Inputs

Accept any useful evidence:

- local repo path or folder path
- GitHub URL or file tree
- pasted source code
- PRD, issue, Jira description, or spec
- Kiro `requirements.md`, `design.md`, or `tasks.md`
- prior annexation notes or ADRs
- GOD-LOCK package/domain targets

When repo contents are available, inspect code before judging. When only a summary is available, mark confidence lower and ask for source evidence only if needed for a decision.

## Outputs

Default to producing all three unless the user asks for a narrower output:

1. **Annexation report** — classify what to annex, deepen, adapt, rewrite, reject, quarantine, or extract as vocabulary.
2. **AES Directive/Op implementation plan** — GOD-LOCK-compatible plan preserving numbered tasks and `_Requirements:` dependency lines.
3. **Optional worker lanes** — parallel-consumable lane document for opencode/Hermes/Django execution when tasks can safely run concurrently.

Use `references/output-templates.md` for report and lane shapes.

## Process

### 1. Establish target context

Identify the GOD-LOCK target shape:

- package, domain, app, integration, tool, adapter, or shared primitive
- likely Nx library placement
- owning domain vocabulary
- expected consumers
- runtime: web, React Native/Expo, Next.js, NestJS, Node worker, CLI, infra, or shared TypeScript

If target placement is unclear, infer a candidate and mark it as provisional.

**Battlefield target shape:** A Battlefield is an active live client workspace nested inside the GOD-LOCK mothership. It is NOT a seed. A seed is source material to be mined; a Battlefield is the destination where seed concepts are annexed, hardened, and proven before being lifted upward into reusable mothership strata. When annexing into a Battlefield:
- Extract concepts from the seed and restructure them behind proper workspace boundaries (domain libs, shared contracts, adapters)
- DO NOT preserve weak legacy implementation structure
- DO preserve proven concepts (compilers, content templates, resolvers, artifact capture)
- Proven patterns from the Battlefield may later be lifted into the mothership as kernel primitives, domain libraries, or shared capabilities

**Project vocabulary discovery:** Before judging any source, check for `./LANGUAGE.md` and `./CONTEXT.md` in the repo root. Read them if present. These files contain per-project architecture vocabulary and product context. Do not assume terms carry over from other projects or from global memory. Key terms, seam names, and domain boundaries may differ per workspace.

Group source code by concept, not by file tree. For each candidate concept, identify:

- source files
- caller-facing behavior
- data shapes
- invariants
- external dependencies
- tests or missing tests
- domain vocabulary
- coupling and duplication
- implementation quality

Prefer concept names over file names. Example: say “quote request intake module,” not “the `QuoteForm.tsx` folder,” unless the file itself is the candidate.

### 3. Apply hard annexation judgment

Classify each candidate as one of:

- **Annex** — implementation is already deep, clean, tested, and GOD-LOCK-compatible enough to adopt or lightly modify.
- **Deepen** — concept is valuable, but interface/implementation should be redesigned into a deeper GOD-LOCK module.
- **Adapt** — concept belongs behind a GOD-LOCK seam with adapters.
- **Rewrite** — concept is valuable, but implementation should not be brought over.
- **Reject** — neither concept nor implementation improves GOD-LOCK.
- **Quarantine** — potentially useful, but too risky or unclear to annex now.
- **Extract Vocabulary** — keep terms, domain distinctions, examples, or business rules, but not code.
- **Lift** — a proven concept or pattern already hardened in an active Battlefield that should be extracted upward into the GOD-LOCK mothership as a reusable kernel primitive, domain library, or shared capability. This is the reverse direction of annexation: instead of bringing a seed concept into a Battlefield, you are moving a Battlefield-proven concept into the mothership for reuse across future client projects.

Be explicit about why. Do not soften rejections.

### 4. Use deepening tests

For each non-trivial candidate:

- Apply the deletion test.
- Assess depth of the current interface.
- Decide whether callers would gain leverage from a deeper module.
- Identify whether locality improves by annexing.
- Classify dependencies using `references/architecture-deepening.md`.
- Decide the test surface at the interface.

A candidate earns annexation only when it increases leverage or locality inside GOD-LOCK.

### 5. Design GOD-LOCK target shape

For every accepted candidate, specify:

- target package/domain/module name
- GOD-LOCK interface shape
- implementation strategy
- seam placement
- adapters, if justified
- migration path
- tests to preserve, delete, or rewrite
- risks and validation

Use Nx-friendly boundaries: reusable packages for shared logic, domain modules for business concepts, app-local code only when reuse is not expected.

#### Special case: cross-platform UI + Storybook experiments

When annexing an experimental React Native / Expo / Next.js / NativeWind UI workspace, default to **Deepen + Adapt** unless the source already has clean package/app boundaries.

Typical target split:

- `packages/ui` — stateless presentational components, primitives, tokens, and narrowly-justified platform-specific implementation files such as `.web.tsx`
- `apps/storybook-web` — Next.js or web Storybook host/runtime, preview decorators, manager branding, CSS/bootstrap, and web-only wiring
- `apps/storybook-mobile` — Expo/React Native Storybook host/runtime, metro/expo config, app bootstrap, fonts, splash handling, and device preview wiring

Do not admit a package called `ui` as-is when it also contains Expo app entrypoints, Storybook hosts, Next.js config, Metro config, fonts/icons/splash assets, or other runtime/bootstrap concerns. That shape proves a seam; it is not yet the seam.

For these audits, explicitly separate:

- reusable UI concepts worth preserving
- host/runtime concerns to move into app targets
- platform adapters/interops that justify retention
- demo components that should be treated as examples rather than annexed product primitives

Before recommending raw adoption, verify whether typecheck/tests currently pass. Broken verification is not always a rejection of the concept, but it is strong evidence to prefer redesign over file-copy migration.

### 6. Produce implementation plan

When asked for an implementation plan, use AES Directive/Op structure. If the `god-lock-jira-structure` skill is available, use it for exact formatting.

Plan rules:

- preserve `# Implementation Plan`, `## Overview`, `# Directive N`, `## Op Group N.M`, numbered checklist tasks, and `## Notes`
- make tasks atomic, implementation-ready, and testable
- include file targets inline in backticks when known
- use `_Requirements:` as the final nested bullet under tasks with dependencies
- do not flatten op groups
- do not invent parallel lanes until dependencies are clear

**After the plan is produced, delegate execution.** Do not implement directly. Hand complex creation/refactors to Claude Code or Codex. Delegate bounded, repeatable tasks/subtasks to Claude Code, Codex, or OpenCode with appropriately sized models. Every agent output must pass review before acceptance.

### 7. Enforce review gate

Before any agent-produced code is accepted:

- Verify correctness against the annexation target interface.
- Check type safety (do not accept hook fixes that bypass typechecking).
- Confirm tests exist or are planned for the new/changed interface.
- Validate that the implementation does not leak vendor specifics into product/domain code.
- Ensure file targets from the plan were honored.
- Reject and re-delegate if the output is shallow, brittle, or off-contract.

### 8. Produce worker lanes when useful

Only create lanes when requirements/dependencies make safe parallelism obvious.

Lane rules:

- lanes are execution topology, not new requirements
- preserve original task IDs
- preserve `_Requirements:` lines
- group by conflict scope, dependency stage, and runtime suitability
- do not parallelize tasks that edit the same fragile interface without a reducer
- include validation and merge/reducer notes

Use opencode for bounded execution lanes, Claude/Django for lane assignment and review, and Hermes as orchestration if requested.

## Non-negotiable rules

- Annex concepts, not files.
- Keep files only when they are good candidates to modify/adopt.
- Do not reward code volume. Reward leverage and locality.
- Do not preserve shallow pass-through modules.
- Do not leak vendor-specific APIs into GOD-LOCK product/domain code.
- Do not create seams for one adapter unless a test adapter or second implementation makes the seam real.
- Do not move code into the mothership without a target interface and validation strategy.
- Do not confuse migration with annexation. Migration moves code; annexation increases mothership capability.
- Prefer reusable GOD-LOCK packages/domains over app-local copies when the concept is broadly useful.
- Prefer rewrite over import when the source code is brittle but the concept is valuable.
- When a live seed project is still the weekly proving ground, prefer practical artifacts that improve the seed's current execution path before proposing mothership abstractions.
- For v0 planning/spec-generation flows intended for a single direct executor, prefer simple sequential task/subtask structures over richer decomposition doctrine unless the richer structure creates immediate execution leverage.
- Treat explicit file targeting as part of executability: if a generated plan/spec is meant for direct execution, tasks should name concrete target file surfaces or halt when grounding cannot be done honestly.
- **Django execution boundary:** Django (the CTO/architect role) produces judgment, plans, and reviews. Django does not directly execute code, run patches, or mutate files unless the Founder explicitly instructs intervention. Implementation is delegated to coding agents.
- **Agent delegation tiers:** Complex creation and refactors are handed to Claude Code or Codex. Repeatable, bounded tasks and subtasks are delegated to Claude Code, Codex, or OpenCode using smaller models (e.g., sonnet/haiku, gpt-5.4-mini, minimax-m2.7). The agent tier must match the task complexity.
- **Mandatory review gate:** All agent-produced code is reviewed for correctness, type safety, testability, and adherence to the annexation target interface before it is accepted into GOD-LOCK or a seed proving ground.

## Quality bar

A good annexation recommendation says:

- what concept is worth preserving
- whether the implementation should survive
- where it belongs in GOD-LOCK
- what interface should callers use
- what behavior moves behind the seam
- which tests prove the interface
- what gets deleted or rejected
- why this improves leverage or locality

A bad recommendation says only “copy this folder into libs.”
