---
name: grill-with-docs
description: Grilling session that challenges your plan against the existing domain model, sharpens terminology, and updates documentation (CONTEXT.md, ADRs) inline as decisions crystallise. Use when user wants to stress-test a plan against their project's language and documented decisions.
version: 1.0.0
metadata:
  hermes:
    tags: [grill-with-docs]
    category: engineering
---

<what-to-do>

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing.

If a question can be answered by exploring the codebase, explore the codebase instead.

</what-to-do>

<supporting-info>

## Domain awareness

During codebase exploration, also look for existing documentation:

### File structure

Most repos have a single context:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Create files lazily — only when you have something to write. If no `CONTEXT.md` exists, create one when the first term is resolved. If no `docs/adr/` exists, create it when the first ADR is needed.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Update CONTEXT.md inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch these up — capture them as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` should be totally devoid of implementation details. Do not treat `CONTEXT.md` as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else.

### When grilling package topology

Treat topology words as glossary work first, not structure work first. Before accepting package names like `core`, `kernel`, `sys`, `tooling`, `integration`, or `patterns`, force each one to earn a precise canonical meaning in `CONTEXT.md`.

Challenge package proposals that are named after implementation style rather than owned capability. In particular, be suspicious of top-level buckets like `patterns`, `common`, `shared`, or `utils` unless the user can define a real seam with durable ownership.

For primitive-first systems, distinguish three things explicitly:
- primitive substrate
- capability-owning strata
- composition/assembly layers

Do not let the conversation collapse these together. If the user means that a stratum owns the lowest abstract executable generic substrate, capture that distinction in the glossary immediately. If the user means a capability-owning stratum, pressure-test it separately.

For candidate primitive-pattern strata, insist on an admission rule. A reusable pattern primitive should only enter the topology when it is capability-agnostic and clearly needed in at least two distinct downstream capability contexts.

### When grilling infrastructure or backend architecture proposals

When the user presents a target-architecture brief (stack, runtime direction, canonical layers), evaluate it with the same relentless precision as package topology:

1. **Sovereignty split coherence**
   - Does each layer have one non-overlapping primary law?
   - Classic five planes: truth (persistence), semantics (federation/query/MCP), transport, trust (identity), behavior.
   - Flag any layer that tries to own two sovereignties.

2. **Semantic overreach**
   - Does the proposal expose *meaning* or *exhaust*?
   - Demand an explicit **admission law**: what earns the right to enter the semantic query plane?
   - Warn when "one query plane" becomes a license to flatten operational noise into the graph.

3. **Substrate discipline**
   - If a substrate claims multiple roles (state + queue + event + memory), demand schema discipline per role.
   - Distinguish durable domain-relevant state from ephemeral operational noise.
   - Flag the "sacred landfill" risk.

4. **Stack coherence**
   - Map each tool to its layer. Does it strengthen the layer's law or leak across layers?
   - Check for duplication collapse: seams should be one-directional (truth flows down, data flows back).
   - Verify generated artifacts (types, schemas, DDL) derive from a single source of truth where claimed.

5. **Migration / v0 path**
   - Does the brief include a build order, or is it only a target state?
   - Insist on a credible first-three-month path that gets product to clients before full-stack completeness.
   - Typical healthy order: substrate discipline → identity plane → minimal supergraph → behavior workers.

6. **Identity and entity mapping**
   - Are canonical IDs defined across trust boundaries (identity provider, external systems, internal runtimes)?
   - Without this, "federation" becomes a bag of adjacent nouns.

Produce a structured critique: strengths, specific challenges, missing sections, and a recommended migration sequence. Reference [references/infrastructure-proposal-grilling.md](references/infrastructure-proposal-grilling.md) for a condensed checklist.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful
2. **Surprising without context** — a future reader will wonder "why did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons

If any of the three is missing, skip the ADR. Use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).

</supporting-info>
