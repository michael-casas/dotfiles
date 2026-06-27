# Variant-Annex Spec Doctrine — Handrolled-Anchor Re-Sync (added 2026-06-24)

**Trigger condition:** writing a spec for a variant-annex pattern (R16 "expanded" or similar) where the handrolled section is the canonical anchor.

**Why this exists:** the existing `handrolled-page-architecture` skill doctrine says "the handrolled source is the canonical anchor, not a migration target" (Founder ruling 2026-06-24, encoded in the annex-pattern section). But a real failure surfaced in the R17 recon (iqne, 2026-06-24): **the handrolled anchor can go stale after the compiler annex lands new canonical data shapes.**

The R16 annex shipped `resolveDivisionsOverviewExpanded` with **canonical 12 services** (from `service.map.ts`) and a **per-card "Learn More" pill CTA** (commit `a0337f00`, M3). The compiler path is now the most up-to-date. But the handrolled `src/app/pages/home/sections/DivisionsBand.tsx` still has:

- 12 services with **5/12 display texts diverging from canonical**
- **No "Learn More" pill CTA** (the anchor is older than the compiler)
- **Raw tailwind hover treatment** (compiler uses `.card-division` class with `--motion-card-lift`)

The doctrine "handrolled is canonical" was correct at annex time. It becomes wrong when the compiler annex outgrows the handrolled. The fix: **re-sync the handrolled anchor to the compiler canonical**, not the other way around.

## The re-sync reflex (added to the annex spec pattern)

**When writing an annex ATDD spec, add a Section 5.5 "Handrolled anchor re-sync check":**

```markdown
### 5.5 Handrolled anchor re-sync (if annex has already landed in compiler)

- **If this is the FIRST annex** (R<N> is the original compiler annex): the handrolled
  source is the canonical anchor. Do NOT modify it. Section 5.5 = N/A.

- **If this is a SUBSEQUENT pass** (R<N+1> on top of an existing R<N> compiler annex):
  recon must include a "Handrolled-vs-compiler drift" table. Spec must either:
  (a) Re-sync the handrolled to the compiler canonical (recommended), OR
  (b) Document the drift as intentional and add it to the open-questions section.
```

## The handrolled-anchor staleness checklist (worked example, R17)

When the recon refresh surfaces drift, the spec must enumerate it explicitly:

```markdown
| Aspect | Handrolled (X.tsx) | Compiler canonical (R<N> commit) | Match? |
|---|---|---|---|
| Service count per division | (count) | (count) | Y/N |
| Service slug source | (home.copy.ts inline) | (service.map.ts canonical) | Y/N |
| Display text matches canonical | (N/M diverge) | Exact match | Y/N |
| Per-card CTA pill | (Absent/Present) | (label) → (route) | Y/N |
| Card CSS | (Raw tailwind / .card-division) | (Class name) | Y/N |
| Card hover | (treatment) | (treatment) | Y/N |
| Services container | (mt-auto? space-y?) | (layout) | Y/N |
| Service row icon | (treatment) | (treatment) | Y/N |
```

**Spec DoD additions for re-sync:**

- [ ] All N/M display texts in handrolled data source match compiler canonical
- [ ] Handrolled anchor has the same CTA treatment as compiler canonical
- [ ] Handrolled anchor has the same hover treatment (or documented divergence)
- [ ] Visual regression: handrolled still pixel-matches pre-re-sync screenshots

## Founder doctrine remains: handrolled-first design intent, compiler-first generalization

The doctrine from the R16 cycle is unchanged for **new** design:

- **First-time design of a pattern:** handrolled is the canvas. Founder iterates in handrolled TSX until visual intent is right.
- **Annex:** compiler takes the handrolled treatment and exposes it as a DTO variant. Handrolled stays as the source of truth at annex time.
- **Subsequent pass on an existing annex:** compiler may have grown (new canonical data, new CTA patterns). Re-sync handrolled to compiler — the canonical-12 services and the Learn More pill are now the SOURCE OF TRUTH; the handrolled is the legacy implementation that needs updating.

**Why this matters:** if the re-sync is skipped, the handrolled page and the compiler-routed pages drift visually. The handrolled is the homepage (`/`) — the highest-traffic page on the site. Drift there is the most visible kind.

## Recon-refresh pattern (companion doctrine)

When the prior R-pass recon is older than the working tree (new commits since recon, uncommitted R-substrate work), the spec should be preceded by a **T1 recon-refresh** dispatched to dsv4-pi. The recon-refresh:

- Treats the prior recon as a hypothesis, not a fact
- Enumerates drift (`git status` + `git diff --stat` since the recon's reference commit)
- Identifies new files (R-substrate) and their load-bearing purpose
- Lists new architectural decisions still open
- Outputs to a NEW file (`R<N>-recon-refresh.md`) with a distinct header marker — never append to the prior recon
- ≤ 4 KB cap (T1 recon standard)

See `cmux-dispatch-protocol/references/substrate-first-dispatch-2026-06-24.md` § "Recon-refresh pattern" for the dispatch flow.

## Worked example: R17 recon → R17 spec doctrine application

R16 spec (this skill applied): "build `cardLayout: 'expanded'` variant, handrolled is the canonical anchor, do not modify."

R17 recon-refresh: discovered handrolled `DivisionsBand.tsx` has 5/12 service display texts diverging, no CTA pill, raw tailwind. The R16-impl M3 commit (a0337f00) shipped canonical-12 + Learn More pill in the compiler, so the compiler is now the most current implementation.

R17 spec doctrine: **re-sync the handrolled to the compiler canonical.** Section 5.5 of the R17 spec must include the drift table and the re-sync DoD items. The handrolled `DivisionsBand.tsx` gets updated (or replaced with a `SectionCompiler` wrapper) to match the compiler's expanded-variant treatment.

## Pair with

- `handrolled-page-architecture` — the parent doctrine ("handrolled is canonical anchor at annex time")
- `cmux-dispatch-protocol/references/substrate-first-dispatch-2026-06-24.md` — the recon-refresh dispatch pattern
- `charter-authoring/templates/` — recon-refresh charter template
