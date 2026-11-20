# Hierarchy

Concern: visual hierarchy, emphasis, reading order, grouping, density and focal points.
Hierarchy decides what is seen first and what recedes; it is settled before decoration.

Owned elsewhere: the type scale and metrics are `typography.md`; the spacing scale and
grid are `layout.md`; color roles are `color.md`. This file owns how those means are
used to direct attention.

## 1. Match the composition to the surface

A wrong composition cannot be repaired by restyling it. Decide it first.

| Surface, more precisely | Composition that fits |
|---|---|
| Monitor (status, dashboards) | Dense, glanceable, most-changed values most prominent. Only data that helps someone decide or act. |
| Operate (consoles, queues, editors) | Selection state and action affordances dominate. Bulk and keyboard paths. |
| Compare (pricing, plans, results) | Aligned columns, parallel structure, one differentiator emphasized. |
| Configure (settings, forms, wizards) | Progressive disclosure, clear save and validation state, low decoration. |
| Decide or learn (landing, marketing, docs) | One idea per section. The first viewport says what this is and what to do. |
| Explore (catalogs, galleries, maps) | Filters, results and peek or zoom are the composition. |
| Inspect or command (detail panes, palettes) | Speed and focus on one object over breadth. |

A first viewport with a headline and a call to action belongs to Decide or learn. On any
other surface, open with the task.

## 2. Hierarchy and grouping

- **Squint test.** With detail blurred you can still pick out the primary element, the
  secondary one, and the major groups, in order. If everything has equal weight,
  nothing does: one primary, two or three secondary, the rest muted.
- **Proximity before containers.** Group by closeness and alignment first. Add a border,
  background or card only when the content is a real unit: a group to compare, an item
  to select, a thing that moves or is dismissed as one.
- **Flat over nested.** One framing move per region. A container inside a container
  inside a container means the grouping was never decided. Nested surfaces are valid
  when each level carries meaning.
- **Align shared edges and baselines.** In side-by-side items (cards, pricing columns,
  panels), titles, lists, prices and buttons line up across the row; pin actions to the
  bottom when content lengths differ.
- **Optical correction.** After mathematical alignment, look. Icons beside text, glyphs
  inside circles and text inside buttons often need a 1 to 2 px nudge.

## 3. Emphasis and focal points

- Use size, weight, space and tone together. Do not ask size alone to carry hierarchy.
- Roles should be recognizable with the copy blurred: you can tell heading from body
  from metadata at a glance.
- Spend boldness in one place. Let one element be the memorable thing and keep what
  surrounds it quiet. If every element is emphasized, the screen is flat.
- The accent color marks actions, current selection and state. Spent on decoration, it
  stops pointing at the primary action. See `color.md`, section 1.
- One primary action per decision context, visibly heavier than the secondary ones.
  Exception: a choice the interface must not steer (accept or decline consent, keep or
  cancel a subscription) gives both options comparable weight. See AUDIT `DARK-02`.
- Structural devices (borders, numbers, labels, dividers, icons) are emphasis too. Each
  must encode something true about the content.
- Depth (shadow, elevation, overlap) is used only when it clarifies state or hierarchy.

## 4. Density

- Density follows the surface and the frequency of use. Dense is not clutter when
  comparison is the job; airy is not elegant when it hides the task.
- Operate and monitoring surfaces lead with what changed or needs attention; a large
  number needs its label, unit and comparison beside it to mean anything.
- Persuade surfaces carry one idea per section.
- When a screen feels crowded, remove or disclose content before shrinking type or
  spacing.
- Group options by the decision they support, and test that users can locate and
  compare them. There is no fixed number: peer destinations and choices that must be
  compared stay visible together.

## 5. Reading order

- Decide the order in which a first-time visitor should take in the screen, and check
  that position, size and contrast produce that order.
- Visual order matches DOM order, so reading order, focus order and assistive
  technology agree. See `accessibility.md`, section 1.
- Narrow layouts are stacked in priority order, not in source-column order by accident.

## Audit coverage

AUDIT items `HIER-01` to `HIER-03` (roles, grouping, prominence), and `HIER-04` to
`HIER-06`. Equal group gaps are `HIER-02`. `SLOP-01` and `SLOP-02` apply when a default composition displaces
the task or the identity; `SLOP-08` and `SLOP-17` name the equal-tile and
centered-everything compositions. `LAYOUT-01` covers comparisons.
