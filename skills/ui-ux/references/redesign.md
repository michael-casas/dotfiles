# Redesign and refinement

Concern: changing an interface that already exists without breaking it: a restyle, a
modernization, a full redesign, or a polish pass inside a named scope. The procedure is
audit first, then fix. The first job is to find out which kind of change was asked for.

## 1. Detect the mode

| Mode | What it means | What changes | What stays |
|---|---|---|---|
| **Refine** | Fix and polish inside a named scope | Defects, missing states, inconsistencies in that scope | Identity, copy, routes, behavior, everything outside the scope |
| **Redesign, preserve** | Modernize without changing the brand | How the existing identity is executed | Brand colors, typefaces, logo, voice, structure |
| **Redesign, overhaul** | A new visual language on existing content | The visual system, by agreement | Product truth, content, function, information architecture |
| **Rebrand** | The brand itself is changing | Everything visual | Product truth and function. Treat as a new build. |

If the request does not say, ask once: should this keep the existing brand, or start
visually from scratch? Misreading the mode is the main cause of bad redesign work.

Never split the difference: polish applied to a look that is being discarded, or one
page restyled while its related states stay in the old language.

## 2. Audit before touching anything

Capture the current state first. It is the baseline for every later comparison.

1. **Screenshots** of the key screens at the applicable sizes
   in `verification.md`, section 1.1, in each theme, with
   representative data. Keep them; the after-screenshots must match them in size and
   data.
2. **Exercise the primary flow** and note what works.
3. **Record what exists:**
   - brand tokens: colors, type stack, logo treatment, radii, spacing habits;
   - information architecture: page tree, primary navigation, key paths;
   - content blocks: what does work, what is filler;
   - signature elements worth keeping: a recognizable hero, an interaction, the voice;
   - states and accessibility that already work;
   - the stack: framework, styling method, component library and their versions.
4. **Run `AUDIT.md` against the current build.** The hits are the starting findings.
5. **Sort every finding** into one of four kinds:
   - broken behavior;
   - missing or failing accessibility;
   - inconsistent craft;
   - deliberate product choice.

   The fourth kind is not a defect. Familiarity is not a defect either. Do not add
   novelty to justify the exercise.

Write the findings as a short list: evidence (screenshot or file and line), impact, and
the proposed correction.

## 3. What never changes silently

Change these only with the user's explicit approval:

- URL structure and route slugs.
- Primary navigation labels and order.
- Form field names, order and required status.
- The logo and wordmark.
- Legal, consent, pricing and factual copy; claims, statistics, testimonials, dates.
- Element IDs, anchors and event names that analytics or tests depend on.
- Page titles, descriptions and structured data that search ranking depends on.
- Existing accessibility wins: focus states, alt text, keyboard paths, contrast.
- The framework, the styling library, and the dependency set.

## 4. Order of work

Fix in this order. Stop when the brief is satisfied.

1. **Broken or blocked tasks,** data loss, misleading state, inaccessible paths.
2. **Missing states:** loading, empty, error, success, disabled, focus, overflow.
3. **Structure:** hierarchy, grouping, flow, responsive recomposition.
4. **System consistency:** tokens, spacing scale, radius rule, one icon family, one
   component per role.
5. **Typography:** scale, measure, weights, line height. Changing the typeface itself is
   an identity decision and changes wrapping everywhere; do it only in a redesign that
   authorizes it, and re-check every screen afterwards.
6. **Color:** unify neutrals, fix contrast, give the accent one job. Keep brand colors.
7. **Motion:** add feedback and continuity where state changes are unclear; remove
   motion that has no purpose.
8. **Recomposition** of key sections, then replacement of a block only when it cannot
   be repaired.

Work in small, reviewable batches. Check existing behavior after each one.

### Choosing the depth

- Structure, content and search standing are sound: evolve in place with steps 1 to 7.
  This is most of the value for the least risk.
- The debt is structural (broken architecture, no system, unusable on mobile): a full
  redesign with strict content preservation.
- The brand is changing: a new build. See `discovery.md`.

## 5. Redesign, overhaul: replacing the visual system

- Agree first on what must stay recognizable.
- The old look is evidence about the subject, not authority over the result. Derive the
  new direction through `discovery.md` section 3.
- Replace the system coherently: tokens first, then shared components, then screens.
  Every related state moves to the new language together.
- Keep content, function and architecture intact while the surface changes.
- Update the project's design documentation at the end, from what was built.

## 6. Refine

Refinement is never a concealed redesign.

- Touch only the named target. Do not restyle its neighbors, and do not add colors,
  fonts, radii, shadows or primitives the surface does not already own.
- If the concept itself is wrong, say so and recommend a redesign. Do not smuggle one in.
- To make a section stronger, amplify what the system already has: its type scale at
  full strength, its signature motif, its structural devices. Make one decisive move
  and quiet what surrounds it. The result should look more like the same brand.
- To make a section calmer, reduce the number of competing heavy elements, lower
  saturation and contrast where they are not needed, and remove decoration. Keep the
  point of view; quiet without intent becomes generic.
- To simplify, remove what does not serve the primary goal: redundant elements, repeated
  information, unneeded containers, extra steps. Keep every function and every piece of
  information a user needs to decide.
- Hold the whole path to one quality bar. Do not perfect one corner and leave the rest.

## 7. Working with the existing stack

- Use the project's framework, styling method and component library. Do not migrate.
- Check the dependency file before importing anything, and the installed version before
  using its API.
- Move stray inline styles and hard-coded values into the project's styling system as
  you touch them, within scope.
- Remove debug output, dead code and styles your change made obsolete. Leave unrelated
  code alone.

## 8. Verify and report

- Re-capture the same screens at the same sizes with the same data, and compare before
  and after side by side. Verify the flow, not only the silhouette.
- Re-run the checks that passed before the change: keyboard path, focus, contrast,
  forms, analytics hooks, links.
- Run `AUDIT.md` on the result.
- Report: what was preserved, what improved, the regression evidence, and what remains
  out of scope or unresolved.

## Audit coverage

Every `AUDIT.md` prefix applies twice: once to the baseline, once to the result. The
items most often regressed by a redesign are `NAV-01` to `NAV-04` (routes, labels,
state), `A11Y-02`, `COLOR-01` and `COLOR-02` (existing focus and contrast wins),
`TOKEN-01` (theme drift) and `ATOM-01` (a divergent kit beside the first).
