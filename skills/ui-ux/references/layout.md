# Layout

Concern: the grid, the spacing scale, composition, responsive behavior and viewport
mechanics. Layout turns priority into position and rhythm.

Owned elsewhere: what is prominent and in what order is `hierarchy.md`; navigation
patterns are `navigation.md`; native app structure is `native-platforms.md`; spacing
and breakpoint tokens are `tokens.md`.

## 1. Set the spatial thesis first

Sketch the task at its smallest and its largest supported size before moving anything.
On each sketch mark what must stay together, what takes priority, and the point at
which the arrangement has to change. Build the least structure that holds both
sketches.

## 2. Space and rhythm

- Use one spacing scale on a 4-unit base. No one-off values.
- Make the steps mean something: gap within a group < gap between groups < gap between
  sections. One value repeated at every level gives no grouping information.
- Create rhythm by contrast between tight and generous intervals. Across a long page,
  vary density, scale and pace inside one grammar: a dense passage earns a quiet one.
- How dense the screen should be is decided in `hierarchy.md`, section 4. Spacing is
  how that decision is expressed.
- Section padding is a decision per section, in proportion to its content. Top and
  bottom padding may differ; check them optically.
- Keep body text off the viewport edge: at least 16 px of gutter on narrow screens.
- Use `gap` for sibling rhythm where it expresses the relationship directly.

## 3. Composition

- Choose alignment in the plan and hold it. Left-aligned, centered and asymmetric are
  all valid; each is chosen for the content, not inherited from a template.
- Repetition supports recognition. Repeat a section layout when the content is truly
  parallel; change it when the content or its priority changes. Do not vary layouts
  only for variety, and do not repeat one layout only because it was already written.
- A grid has exactly as many cells as there is content. Shape the grid to the content.
- Constrain reading width. A page-level max width (commonly 1200 to 1440 px) keeps
  content from stretching on wide screens; data surfaces and full-bleed media may use
  the full width on purpose.
- Long lists: past about five items, consider grouping, columns, tabs or a table before
  extending a single stack. Use a table when rows are compared across the same fields.
- Navigation layout across widths is owned by `navigation.md`, section 5.

## 4. Layout mechanics

- Flex for one-dimensional relationships, grid for two-dimensional composition.
- Let content size the box. Avoid fixed pixel widths and heights on anything holding
  text. Prevent overflow in flex and grid children with `min-width: 0` and
  `minmax(0, 1fr)`.
- Visual order follows DOM order, so focus and reading order match what is seen. Dense
  grid auto-placement, `order` and reversed flex directions move boxes without moving
  them in the DOM; check the tab order wherever one is used.
- Fix overflow at its source. Clipping the whole page hides the bug and can hide
  content.
- Full-height sections: choose the viewport unit for the behavior you want. `svh` is
  stable while browser chrome shows and hides; `dvh` tracks it and so changes during
  scroll; plain `vh` overflows behind mobile browser chrome. Use `min-height`, so
  content can grow.
- Overlays (menus, popovers, tooltips) must escape clipping ancestors: use the native
  dialog or popover mechanisms, fixed positioning, or a portal. Test them at the
  viewport edge, while scrolling, and at zoom.
- Reserve space for images, embeds and late-loading content with intrinsic dimensions or
  `aspect-ratio`, so nothing shifts when they arrive.
- Use logical properties (`margin-inline-start`, `padding-inline`) so the layout mirrors
  correctly for right-to-left languages.
- Keep selector specificity flat and predictable. A section-level rule and a
  component-level rule that both set padding or margin will cancel each other; decide
  which layer owns spacing between sections.

## 5. Responsive behavior

### 5.1 Principles

- **Recompose, do not shrink.** Decide what reorders, collapses, wraps, scrolls or stays
  fixed at each size. State the narrow layout for every multi-column section explicitly.
- **Start from the narrowest layout** and add complexity with `min-width` queries.
- **Breakpoints come from the content.** Widen the layout until it breaks and put a
  breakpoint there. Three are usually enough.
- **Detect input, not just size.** Use `pointer` and `hover` media queries. A laptop can
  have touch; a tablet can have a keyboard.
- **Components adapt to their container** where the same component appears in different
  contexts; use container queries when available.
- **Nothing essential is removed on small screens.** If it matters, it works there.
  Keep the same information architecture across sizes.

### 5.2 Widths to check

| Width (CSS px) | Why |
|---|---|
| 320 | Reflow floor: content and function without two-dimensional scrolling |
| 375 | Common phone |
| 768 | Tablet, and the usual point of recomposition |
| 1024 | Small laptop; navigation and multi-column layouts are under most pressure |
| 1280 | Common desktop |
| 1440 to 1920 | Wide: check max width, line length and stranded whitespace |

Also check the user's actual viewport when it is known, landscape on phones, and 200
percent zoom.

### 5.3 Patterns

Primary navigation across widths is in `navigation.md`, section 5.

| Element | Narrow | Wide |
|---|---|---|
| Multi-column content | Single column in priority order | Columns |
| Data table | Priority columns plus a detail view, a horizontally scrolling region with a fixed first column, or stacked rows with labels | Full table |
| Secondary content | Disclosure, tab or separate screen | Side panel |
| Filters | A sheet or full-screen panel | Inline bar or sidebar |
| Dialog | Full-screen or bottom sheet | Centered dialog or side panel |

### 5.4 Touch

- Target size follows `accessibility.md`, section 5. The hit area may be larger than
  the visible mark.
- Put frequent actions within thumb reach on phones.
- No function depends on hover. Gate hover-only effects behind
  `@media (hover: hover) and (pointer: fine)`.
- Inputs use at least 16 px text; smaller text makes iOS Safari zoom the page on focus.
- Respect safe areas: use `env(safe-area-inset-*)` with `viewport-fit=cover`.
- Every gesture has a visible, non-gesture alternative.

### 5.5 Other contexts

- **Print:** remove navigation and controls, expand collapsed content, show link
  targets, break pages at logical points.
- **Email:** single column, about 600 px wide, inline styles, no dependence on hover or
  scripts, large obvious actions.
- **Emulation is not a device.** Viewport emulation shows layout; it does not show touch
  behavior, real performance, font rendering or the on-screen keyboard. Say which one
  produced your evidence.

## Audit coverage

AUDIT items `LAYOUT-01` to `LAYOUT-05`, and `LAYOUT-06` to `LAYOUT-11`.
Fixed-width translated labels are `LAYOUT-05`.
Reflow and zoom are `LAYOUT-03`. Related: `A11Y-05` and `A11Y-06` (targets, text
spacing), `PERF-01` (layout shift), `SLOP-01`, `HIER-02` (grouping).
