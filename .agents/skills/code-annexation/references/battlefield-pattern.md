# Battlefield Pattern Reference

A Battlefield is an active live client workspace nested inside the GOD-LOCK mothership where real client delivery occurs. It is the destination where seed concepts are annexed and hardened before being lifted upward into reusable mothership strata.

## Battlefield vs Seed

| Property | Seed | Battlefield |
|---|---|---|
| Purpose | Source material for concept extraction | Active client delivery workspace |
| Lifecycle | Mined, then optionally archived | Continuous, live, shipping |
| Direction of value flow | Outward (concepts extracted) | Bidirectional (seed concepts in, proven patterns out) |
| Topology | Often solo/monolithic | Nx workspace with proper package strata |
| Relation to mothership | Source of annexable nuggets | Proving ground that feeds the mothership via Lift |

## Battlefield admission workflow

When admitting a new Battlefield into GOD-LOCK:

1. **Identify the workspace path** — e.g., `./battlefields/<client-slug>/`
2. **Create a steering file** — `.kiro/steering/battlefields.md` with `inclusion: always`
   - Name the Battlefield and its contained projects
   - Map project paths within the Battlefield
   - Define annexation rules for any seed material being consumed
   - Add vocabulary table for Kiro specs (Battlefield → path, project → path)
   - Include halt conditions (e.g., do not target old seed paths, do not confuse Battlefield with mothership)
3. **Update CONTEXT.md** — add Battlefield vocabulary to the canonical product context
   - `Battlefield`: the concept definition
   - `<Name> Battlefield`: the specific instance with path
   - `Lift`: the upward motion from Battlefield to mothership
   - Add to example dialogue if useful
4. **Update .gitignore** — add `battlefields/*` so active client workspaces are not committed to the mothership repo
5. **Update all path references** — search for and update any existing references to the old path (e.g., `prototypes/` → `battlefields/`)
6. **Verify with the user** — confirm the Battlefield steering file loads correctly and Kiro can resolve "targeting the <Name> Battlefield" to the correct path

## Lift workflow

When a Battlefield has proven a pattern worth reusing:

1. **Identify the proven concept** — e.g., a content compiler seam, a Payload integration pattern, a workspace generator behavior
2. **Evaluate for generalization** — can it be made capability-agnostic? Does it apply to at least two distinct client contexts?
3. **Design the mothership target** — kernel primitive, domain library, shared contract, or tooling module
4. **Extract and test** — pull the concept out of the Battlefield, generalize the interface, add tests against the new seam
5. **Apply the Pattern Admission Rule** — if targeting `kernel/patterns`, it must be needed in at least two downstream capability contexts and remain capability-agnostic
6. **Document the lift** — update CONTEXT.md or relevant ADR to record that the concept was lifted from a specific Battlefield

## Halt conditions for Battlefield work

- Do not generate specs targeting old seed paths when a Battlefield is the intended target. The seed path is archival; active work happens in the Battlefield.
- Do not confuse a Battlefield with the mothership. Battlefields are client workspaces; the mothership owns reusable primitives.
- Do not treat seed file copies as annexation. Annexation into a Battlefield means concept extraction + interface redesign + proper workspace placement.
- Do not lift concepts from a Battlefield until they have been proven in real client delivery. Unproven concepts belong in the Battlefield, not the mothership.

## Example Battlefield steering file shape

~~~markdown
---
inclusion: always
---

# GOD-LOCK Active Battlefields

A Battlefield is a live client workspace nested inside the GOD-LOCK mothership.

## Active Battlefields

### <Name> Battlefield

- **Path**: `./battlefields/<client-slug>/`
- **Client**: <client name>
- **Status**: Active, live, client-facing
- **Purpose**: <what this Battlefield proves>

**Contained projects:**

| Project | Path within Battlefield | Role |
|---|---|---|
| `<app-name>` | `apps/<app>/` | Primary client-facing application |
| `<seed-name>` | `apps/<seed>/` | Annexation target |

**Annexation rules for this Battlefield:**
- <seed-name> is a seed being consumed BY this Battlefield
- Extract <concepts> and rebuild behind proper Nx library boundaries
- DO NOT preserve weak legacy implementation structure
- DO preserve proven concepts: <list>

**When generating specs for <Name> Battlefield:**
- Target files live under `./battlefields/<client-slug>/`
- Prefer workspace-native commands (`pnpm nx ...`)
- Any spec must name concrete files under the Battlefield path

## Vocabulary for Kiro specs

| Term | Meaning | Path |
|---|---|---|
| <Name> Battlefield | The active <client> workspace | `./battlefields/<client-slug>/` |
| <App> | The client-facing app | `./battlefields/<client-slug>/apps/<app>/` |
| <Seed> | The annexation target | `./battlefields/<client-slug>/apps/<seed>/` |
| Lift to mothership | Extract proven patterns into GOD-LOCK | `battlefields/<client-slug>/` → `packages/` or `kernel/` |

## Halt conditions

- Do not target old seed paths when this Battlefield is intended.
- Do not confuse Battlefield with mothership.
- Do not treat seed copies as annexation.
~~~
