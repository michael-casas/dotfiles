# Infrastructure / Backend Architecture Proposal Grilling Checklist

Condensed companion to the `grill-with-docs` infrastructure-proposal section.
Use when evaluating a target-architecture brief, stack direction, or canonical-backend proposal.

---

## 1. Sovereignty split coherence

| Plane | Primary Law | Typical Owner |
|---|---|---|
| Truth | Persistence, state substrate, lineage | PostgreSQL / durable store |
| Semantics | Query composition, entity federation, MCP surface | Apollo Federation + Apollo GraphQL MCP |
| Transport | TLS, routing, retries, rate limiting | Envoy / edge proxy |
| Trust | Identity, tenancy, RBAC, audit | WorkOS / identity provider |
| Behavior | Stateless execution, async workers | Cloud Run / stateless compute |

**Halt signal**: any layer claims two primary laws.

---

## 2. Semantic overreach

Demand an explicit **admission law** for the semantic query plane. Example healthy law:

> A source earns subgraph status only if it owns meaningful entities, federation reduces caller complexity, identity is compatible, and it exposes meaning rather than transport detail.

**Halt signal**: "The supergraph will expose everything because it can."

---

## 3. Substrate discipline

If a substrate (e.g., PostgreSQL) claims multiple roles, demand per-role schema discipline:

- Relational tables vs JSONB state
- Append-only lineage vs mutable operational state
- Vector memory attachment rules
- Job/event retention windows
- Audit normalization

**Halt signal**: "Postgres will be our state + queue + event + memory + lineage substrate" without per-role schema laws.

---

## 4. Stack coherence

Map each proposed tool to its plane. Check:
- Does it strengthen the plane's law or leak across planes?
- Are seams one-directional? (truth/schema flows down; data flows back up)
- Is there a single source of truth for types/schemas/DDL?

**Healthy pattern**: One Zod schema propagates to all boundaries:

```
Zod Schema (single definition)
    │
    ├── Zodgres → Postgres DDL + auto-migrations
    ├── zod-to-x → TypeScript + Python + Go + C++ + Protobuf
    ├── pg_graphql → GraphQL type reflection
    └── Apollo Federation → Composed supergraph entities
              │
              ▼
       Apollo GraphQL MCP → ONE semantic cognition surface
```

One source, multiple generated boundaries, one unified MCP interface.

**Key contract**: The system exposes *meaning*, not infrastructure. Agents query entities and relationships through a unified graph interface, not fragmented tool-specific MCP servers.

---

## 5. Migration / v0 path

Insist on a credible first-three-month path. Typical healthy order:

1. **Substrate discipline** — schemas, migrations, identity references
2. **Identity plane** — org/user/machine identity mapping
3. **Minimal supergraph** — one or two internal subgraphs, not all external systems at once
4. **Apollo MCP surface** — prove one unified semantic cognition interface over the supergraph
5. **One real cognition loop** — query → memory → event → inspect lineage through the MCP surface
6. **External federation** — Atlassian, Payload, etc. only after internal semantics are proven
7. **Operational cockpit** — human interfaces once the graph is stable

**Halt signal**: the brief is only a target state with no build order.

---

## 6. Identity and entity mapping

Before accepting federation promises, verify:
- What is the canonical identity key across WorkOS, external systems, and internal runtimes?
- Who owns project/work-item lineage?
- What gets mirrored vs extended vs referenced?

**Halt signal**: "Federation will handle identity" without explicit entity mapping.

---

## Output template

Produce a structured critique:

1. **Strengths** — what is genuinely good (sovereignty splits, duplication collapse, cognition-first design)
2. **Challenges** — specific risks with evidence (overreach, landfill, identity gaps)
3. **Missing sections** — what must be added before execution (admission law, build order, entity mapping)
4. **Recommended migration sequence** — numbered, bounded, client-value-first
5. **Verdict** — Strong / Credible with gaps / Not ready to execute / Reject
