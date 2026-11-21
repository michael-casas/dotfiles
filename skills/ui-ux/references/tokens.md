# Tokens

Concern: design tokens, theme structure, the existing design system, token drift, and
extending before inventing.

Owned elsewhere: the values themselves are decided in `color.md`, `typography.md`,
`layout.md` (spacing, breakpoints) and `animation.md` (durations, easing); how
components are composed from tokens is `atomic-design.md`.

## 1. Adopt before you build

The first move in an existing project is detection.

1. **Look for a declared system:** a styling or component library in the dependency
   file, a token or theme file, a `DESIGN.md` or brand document, a component workshop.
2. **If one exists, it is the source of truth.** Extend it in its own names, its own
   scale and its own storage format. Measure drift against it, not against this file.
3. **If only repeated values exist** (the same greys and paddings across screens, no
   theme file), there is no system yet. Derive tokens from the most frequent values.
4. **Never add a second system beside an existing one.** A new theme folder next to an
   existing theme config is drift.
5. **If nothing exists,** the defaults in this file apply.

Inspect actual usage, not just token names: a token nobody uses is not the system.

## 2. Real systems and honesty

- When the brief reads as a published design system (a platform vendor's, a
  government's, a commerce platform's, a well-known component library), use it through
  its supported components or integration. Adding the package is a dependency change:
  do it only within the authorized scope. Do not rebuild its CSS by hand, and do not import its
  tokens and then override most of them.
- One system per project. Do not mix component libraries in the same tree.
- A library's untouched default theme is a starting point. Set its radius, color, type
  and shadow tokens to the project's direction before building screens on it.
- When the brief is an aesthetic and not a system (glass, brutalism, editorial, bento),
  no package owns it. Build it natively and describe it accurately. A web approximation
  of a platform vendor's proprietary material is labelled an approximation.
- **Do not impersonate a real brand.** You may take principles from a reference: density,
  command-first interaction, a monochrome-plus-accent posture, editorial hierarchy. You
  may not reproduce a company's distinctive screens, logo, wordmark or exact visual
  identity unless the user clearly owns it. Turn references into an original design.

## 3. Token structure

- **Two layers.** Primitive values (a color ramp, a spacing scale) and semantic tokens
  that name a role (`surface`, `text-muted`, `border`, `action`, `focus`, `danger`).
  Components use semantic tokens only. Themes remap semantic tokens to other primitives.
- **Name by purpose, not value.** `text-secondary`, not `gray-500`.
- **A token needs a repeated meaning.** A value used twice with the same intent is a
  token. A genuinely local value (a 1 px optical nudge) stays inline with a comment.
  Do not build a speculative taxonomy for values nobody uses.
- **One entry point.** One theme source that everything imports.
- **Follow the project's token schema.** An existing nested theme schema or platform
  adapter is authoritative. Where the project uses a flat format, variants are separate
  entries (`button-primary`, `button-primary-hover`). Every token is referenced
  somewhere; remove orphans.

Minimum categories for a new system:

| Category | Contents |
|---|---|
| Color (roles defined in `color.md`) | Surfaces (base, raised, sunken, inverse); text (primary, secondary, disabled, inverse, link); borders (default, subtle, focus); action (default, hover, active); status (success, warning, error, info); overlay |
| Space | One scale on a 4-unit base, about 8 to 12 steps. Row gap, group gap and section gap are different steps. |
| Type (metrics in `typography.md`) | Families by role; a size scale; weights; line heights; tracking for display and for caps |
| Shape | A small radius scale and a rule for which component gets which step |
| Elevation | 2 or 3 levels. Declare elevation once per element: border or shadow, not both by reflex. |
| Motion | 3 to 5 durations and 2 or 3 easing curves. See `animation.md`. |
| Layers | A named z-index scale: base, sticky, dropdown, overlay, modal, toast, tooltip |
| Breakpoints | Chosen from where this content breaks. See `layout.md`. |

## 4. Consistency rules

- **Shape.** One radius rule for the product. Either one value, or a stated rule (for
  example: controls 6, cards 12, pills for small tags only) followed everywhere. Inner
  radius equals outer radius minus the padding when containers nest.
- **Icons.** One family, one stroke weight, one sizing rule. Owned by `imagery.md`,
  section 4.
- **Depth.** Shadows suggest one light source and are soft enough to read as depth.
  Tinting a shadow toward the surface hue is an option, not a rule.
- **Layers.** Use the named scale. A new arbitrary z-index means the scale is missing a
  level or the stacking context is wrong.

## 5. Classifying drift

When something does not match the system, decide which case it is before fixing it:

| What you found | What to do |
|---|---|
| The value is needed in several places and the system has no name for it | Add the token to the system |
| The screen rebuilt something the system already provides | Replace it with the system's version |
| The screen works differently from its siblings, not just looks different | Reconcile the behavior or structure first; styling follows |
| The work was simply left unfinished | Complete it where it is |

Make the change in the smallest place that fully corrects it. A change to the system
itself is the user's decision.

## Audit coverage

AUDIT item `TOKEN-01` (theme propagation), and `TOKEN-02` to `TOKEN-06`.
Related: `ATOM-01` (forks and parallel kits), `COLOR-01` to `COLOR-03` (visible
contrast and meaning), `DARK-05` (another organization's identity).
