# TEMPLATE-ISOW

# INVENTORY SCOPE OF WORK — [ISOW-ID]

## Phase I — SEAL / Structural Discovery

### Directive
[Exact bounded directive this ISoW answers. Discovery objective only. No remediation or execution language.]

### Visual Audit Binding
- Bound Visual Audit Artifact Path: `[VISUAL-AUDIT-ARTIFACT-PATH]`
- Supplied By: `[Founder | Advisor | Named Role]`
- Full Read Confirmed: `YES`
- Artifact Role: `PRIMARY TRUTH SOURCE`
- Evidence Mode: `[Rendered visual audit evidence | Rendered visual and auditory evidence]`
- Mismatch Rule: `Any mismatch between artifact truth and structural mapping triggers ambiguity declaration or HALT`

### Target Slice
[Exact component / route family / subsystem / compiler slice under investigation]

### Discovery Scope

#### Inspected Surfaces
- `[path]` — [role] — [why included]
- `[path]` — [role] — [why included]

#### Intentionally Excluded
- `[path or surface]` — [why excluded]
- `[path or surface]` — [why excluded]

### Visual Failure Registry
| Case ID | Route / Page | Surface / Section | Breakpoint / Device | Failure Class | Severity | Evidence Basis |
|---|---|---|---|---|---|---|
| VF-001 | [route] | [surface] | [breakpoint] | [failure] | [severity] | [artifact reference] |
| VF-002 | [route] | [surface] | [breakpoint] | [failure] | [severity] | [artifact reference] |

### Structural Inventory Registry
| Path | Role | Why Included | Write Candidate |
|---|---|---|---|
| `[path]` | [role] | [reason] | [YES/NO] |
| `[path]` | [role] | [reason] | [YES/NO] |

### Dependency Notes
- `[source] -> [target]` — [dependency nature]
- `[source] -> [target]` — [dependency nature]

### Schema vs Usage Delta Map
| Surface | Contract Allows | Active Usage | Delta | Packet Relevance |
|---|---|---|---|---|
| [surface] | [state] | [state] | [delta] | [why it matters] |

### Composition / Ownership Map

#### Renderer Composition Map
- [renderer branch / composition truth]

#### Breakpoint / Layout Resolution Map
- [layout resolution truth]

#### Token Consumption Map
- [token / spacing / sizing truth]

### Write Candidate Set
| Candidate | File / Surface | Mutation Purpose | Ownership Hypothesis | Risk |
|---|---|---|---|---|
| WC-001 | [file/surface] | [purpose] | [hypothesis] | [risk] |
| WC-002 | [file/surface] | [purpose] | [hypothesis] | [risk] |

### Forbidden Surfaces
- `[path or domain]` — [why forbidden]
- `[path or domain]` — [why forbidden]

### Ambiguities / Confidence Gaps
| Gap ID | Open Question | Evidence Present | Missing Truth | Packet Relevance | Status |
|---|---|---|---|---|---|
| AG-001 | [question] | [present evidence] | [missing truth] | [why it matters] | [OPEN/CLOSED] |

### Recommended Packet Seams
| Seam ID | File / Surface | Exact Line Range | Mutation Purpose | Notes |
|---|---|---|---|---|
| PS-001 | [file/surface] | [lines] | [purpose] | [notes] |
| PS-002 | [file/surface] | [lines] | [purpose] | [notes] |

### Stop Boundary
- Discovery stops at: [boundary]
- Stop reason: [why minimum lawful coverage is achieved]
- Declared conditions for additional discovery: [only if later required]

### Provisional Execution Mutation Map
| Failure Class | File / Surface | Provisional Owner | Basis |
|---|---|---|---|
| [failure] | [file/surface] | [owner] | [basis] |

---

## Phase II — Tightening / Ambiguity Collapse

### Ambiguity Intake Statement
[State exactly what remained unresolved after SEAL and why tightening is required.]

### Normalized Case Registry
| Case ID | Route / Page | Surface | Breakpoint / Device | Layout Mode | Relevant Count / Dimension | Notes |
|---|---|---|---|---|---|---|
| NC-001 | [route] | [surface] | [breakpoint] | [layout] | [count/dimension] | [notes] |

### Layer Contribution Analysis

#### Renderer Analysis
- [evidence and ruling]

#### Resolver Analysis
- [evidence and ruling]

#### Token Analysis
- [evidence and ruling]

#### DTO / Content Analysis
- [evidence and ruling]

#### Adjacent Surface Analysis
- [evidence and ruling]

### Root-Cause Ruling
[Explicit primary cause statement grounded in prior phases.]

### Exact Mutation Ownership Boundary
- Primary owner: `[layer / file / surface]`
- Lawful mutation boundary: `[exact scope]`
- Excluded ownership claims: `[layers that do not own the failure]`

### Responsibility Separation Table
| Layer | Status | Basis |
|---|---|---|
| [primary owner] | PRIMARY RESPONSIBLE | [basis] |
| [contributing layer] | CONTRIBUTING PRESSURE | [basis] |
| [excluded layer] | NOT RESPONSIBLE | [basis] |

### Tightening Halt / Closure Statement
- Packet-relevant ambiguity remaining: `[YES/NO]`
- May proceed to extraction: `[YES/NO]`
- Closure statement: [exact ruling]

---

## Phase III — Execution Slice Extraction

### Extraction Directive
[Exact extraction purpose for execution packet authoring only. State explicitly that this phase is not rediscovery.]

### Exact Slice Registry

#### Slice-001 — [name]
- File: `[path]`
- Exact Line Range: `[start-end]`
- Symbols: `[symbol list]`
- Completeness: `[FULL / PARTIAL WITH JUSTIFICATION]`
- Purpose: [why extracted]

#### Slice-002 — [name]
- File: `[path]`
- Exact Line Range: `[start-end]`
- Symbols: `[symbol list]`
- Completeness: `[FULL / PARTIAL WITH JUSTIFICATION]`
- Purpose: [why extracted]

### Cross-Slice Dependency Check
| Symbol | Defined In | Consumed By | Status | Notes |
|---|---|---|---|---|
| [symbol] | [slice/file] | [slice/file] | [OK/MISSING] | [notes] |

### Read Completeness Matrix
| Slice / Surface | Exact Line Range | Completeness Status | Additional Read Required |
|---|---|---|---|
| [slice] | [lines] | [status] | [YES/NO] |

### Execution Authoring Readiness Check
- Additional read surfaces required: `[YES/NO]`
- Packet authoring may begin: `[YES/NO]`
- Readiness basis: [exact basis]

## FINAL RULING
`EXECUTION AUTHORING READY`
or
`NOT READY — additional declared discovery required`
