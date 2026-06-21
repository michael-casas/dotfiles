# GOD-LOCK Technology Audit Framework

Condensed reference for evaluating candidate technologies against the GOD-LOCK canonical backend architecture. Use when the user asks to audit, evaluate, or research a technology for stack admission.

---

## Canonical Stack Sovereignty

| Plane | Owner | Does NOT Own |
|---|---|---|
| **Truth** | Postgres (Neon) | Behavior, transport, auth |
| **Semantics** | Apollo Federation + Apollo GraphQL MCP | Execution, persistence, identity |
| **Trust** | WorkOS | Business logic, data modeling |
| **Transport** | Envoy | Business logic, auth decisions |
| **Behavior** | Cloud Run workers | State, APIs, semantic surfaces |
| **Human Ops** | Payload CMS | The backend itself |

Core law:
```
Services own behavior.
Postgres owns truth.
Federation owns semantics.
Envoy owns transport.
WorkOS owns trust.
```

---

## Single-Source-of-Truth Propagation

```
Zod Schema (single definition)
    │
    ├── Zodgres → Postgres DDL + auto-migrations
    ├── zod-to-x → TypeScript / Python / C++ / Go / Protobuf
    ├── pg_graphql → GraphQL type reflection (Postgres subgraph)
    └── Apollo Federation → Composed supergraph entities
              │
              ▼
       Apollo GraphQL MCP → ONE semantic cognition surface
```

---

## Audit Methodology (The Verdict Pattern)

When evaluating a candidate technology, answer these questions in order:

### 1. What is it, precisely?
- Version, maturity, maintenance status, license
- GitHub metrics (stars, forks, open issues, update recency)
- Single author vs team vs corporate backing
- Stability (0.x vs 1.x+)

### 2. What problem does it claim to solve?
- Distinguish marketing from actual capability
- Check if the problem exists in GOD-LOCK's current architecture

### 3. Where in the stack would it live?
Map to the sovereignty plane:
- Truth layer? (Postgres-adjacent)
- Semantics layer? (GraphQL/Federation)
- Behavior layer? (Worker runtime)
- Transport layer? (Envoy)
- Trust layer? (WorkOS)

### 4. Does it duplicate an existing tool?
- If pg_graphql already handles Postgres→GraphQL, a new "Zod→GraphQL for Postgres" tool is likely redundant
- If zod-to-x already handles Zod→Protobuf/Go/Python/C++, a new transpiler must justify its existence

### 5. What is the specific fit for GOD-LOCK?
Define:
- **Where it makes sense** — specific subgraphs, specific use cases
- **Where it does NOT make sense** — planes already covered by canonical tools

### 6. What are the risks?
- Low adoption / single author / 0.x maturity
- Overlap with existing tools
- Bringing heavy machinery for a narrow need
- Locking into a non-canonical abstraction

### 7. Verdict categories
| Verdict | Meaning | Action |
|---|---|---|
| **Admit** | Core to the canonical stack | Add to architecture, plan adoption |
| **Watchlist** | Credible but unproven at scale | Defer, evaluate in proof-of-concept |
| **Reject** | Duplicates, immature, or misaligned | Document why, move on |
| **Hold** | Useful but not on critical path | Add to future evaluation queue |

### 8. Recommended next step
- Proof of concept scope
- Pilot boundary (which subgraph/service)
- Comparison against alternatives

---

## Case Study: @gqloom/zod Audit (2026-05-29)

### What it is
- Code-first GraphQL schema loom; weaves Zod schemas into GraphQL types + resolvers
- 97 GitHub stars, created Sept 2024, actively maintained, MIT licensed, v0.16.0
- Single main author (`xcfox`)

### What it does well
- Zod v3 + v4 support
- Apollo Federation support via `@gqloom/federation` (v0.12.0)
- Resolver factory for Prisma/Drizzle/MikroORM
- No decorators, no codegen — pure functions
- Federation features: `@key`, `@shareable`, `@external`, `resolveReference`, `_entities`, `_service`

### Where it would live
**Behavior layer / Semantics layer** — for custom service subgraphs that need curated GraphQL exposure beyond raw pg_graphql reflection.

### Does it duplicate existing tools?
- **pg_graphql** already auto-reflects Postgres schemas → GQLoom is irrelevant for Postgres subgraphs
- **zod-to-x** handles Zod→Protobuf/Go/Python/C++ but NOT GraphQL — GQLoom fills the GraphQL gap

### Specific fit
| Where it makes sense | Where it does NOT make sense |
|---|---|
| Agent service subgraphs (Cloud Run workers with behavioral GraphQL APIs) | Postgres table subgraphs (pg_graphql wins) |
| Custom operational types beyond raw pg_graphql reflection | Atlassian subgraph (Atlassian provides its own GraphQL) |
| Federated entities spanning multiple sources | Payload subgraph (Payload generates its own schema) |

### Risks
1. **97 stars, 0.x version** — not "bet the architecture" ready
2. **Single author** — maintenance risk if author moves on
3. **Full resolver framework** — heavy if only schema generation is needed
4. **Does not solve cross-language GraphQL** — only JS/TS runtime

### Verdict: **WATCHLIST**
- Credible candidate for custom subgraph generation
- Not required for canonical stack to function
- Prove pg_graphql + Apollo Router first, THEN pilot GQLoom (or Pothos) for custom subgraphs

### Recommended next step
1. Prove Postgres subgraph via pg_graphql + Apollo Router
2. When custom service schemas need GraphQL definition, pilot GQLoom vs Pothos for that specific boundary
3. Do NOT adopt a full resolver framework for schema generation alone

---

## Case Study: zod-to-x Audit (earlier session)

### What it is
- Zod v4 extension with `.zod2x()` method
- Emits AST node first, then transpiles to: TypeScript, Python, C++, Go, Protobuf v3
- Supports layered modeling with generics via decorators

### Verdict: **ADMIT** (with caveats)
- Fills a genuine gap: single Zod schema → multi-language type contracts
- Complements pg_graphql (doesn't compete)
- Combined with Zodgres: one Zod schema → Postgres DDL + all service types
- Caveat: Zodgres + zod-to-x are separate projects; no unified orchestration yet

---

## Related Skills
- `grill-with-docs` — interrogate PRDs and architecture notes against documented decisions
- `code-annexation` — evaluate external codebases for adoption into GOD-LOCK
