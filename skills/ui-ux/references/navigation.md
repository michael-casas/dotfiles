# Navigation

Concern: information architecture, wayfinding, user flows, first use, and URL and view
state.

Owned elsewhere: the labels' wording is `content.md`; keyboard and focus behavior of
navigation components is `accessibility.md`; native navigation models are
`native-platforms.md`.

## 1. Information architecture

- Rank what users need to find or do by frequency. The most frequent is reachable in one
  step from anywhere it is needed.
- Choose the pattern for the relationship, not the silhouette: breadcrumbs for real
  hierarchy, tabs for peer views of one object, disclosure for secondary material, a
  stepper for a real sequence.
- Keep the top level short enough to scan and group the rest under clearly named
  categories. About five destinations is a common example, not a limit.
- Show the current location at every level: active navigation item, page title,
  breadcrumb or step.
- One word per concept, everywhere. Keep a short glossary when the product is large.
- URLs are part of the interface: readable, stable, one pattern. What belongs in them
  is decided in section 4.
- Plan for growth. A section that accumulates content needs search, filtering,
  pagination or an archive from the start.
- Provide a way back from every screen and a useful not-found page.

## 2. Flows

- Lay out the critical path, then each recovery path: cancel, back, interruption,
  re-entry, failure.
- One clear primary action per decision context. Group the other options by the
  decision they support; see `hierarchy.md`, section 4.
- Keep the information needed for a decision on the screen where the decision is made.
  Do not make the user remember it from an earlier step.
- Sequence complex tasks into steps, with defaults, templates or examples as scaffolding.

## 3. First use

- Reach the first useful result quickly. Teach inside the real product, at the moment a
  feature is needed, not in a separate tour.
- Let experienced users skip any introduction.
- An empty screen is the onboarding: say what will appear here, why it matters, and give
  the action that starts it.

## 4. URL and view state

- Give durable destinations stable addresses.
- Reload and authorized deep links restore the addressed object and its safe, shareable
  view state (for example sort order, non-sensitive filters, the selected tab, the
  page number).
- Back restores the preceding history entry and its relevant context.
- Keep sensitive queries, credentials and private draft contents out of URLs. They leak
  through history, logs and copied links.
- The back button undoes navigation, never an action. Opening an overlay that reads as
  a new place adds a history entry; a transient menu does not.
- Client-side navigation updates the page title and moves focus to the new view. See
  `accessibility.md`, section 4.
- Leaving a screen with unsaved work warns the user or preserves the draft.

## 5. Navigation across widths

- Navigation fits on one line at its breakpoint, at a modest height (commonly 56 to
  72 px on desktop). When items do not fit, shorten, group or move them.

These arrangements are examples.

| Width | Primary navigation |
|---|---|
| Narrow | A bottom bar for a few top-level destinations, or a menu button with a drawer |
| Intermediate | A compact horizontal bar or a collapsed rail |
| Wide | A visible bar, or a persistent side navigation |

Every destination stays reachable and keeps its name at every width. The arrangement
may differ.

## Audit coverage

AUDIT items `NAV-01` to `NAV-04`. Related: `A11Y-02` and `A11Y-04` (focus, bypass and
order), `CONTENT-01` (names that change), `DARK-02` (hidden exits), `NAV-05`
for navigation that overflows, wraps or loses destinations when narrow.
