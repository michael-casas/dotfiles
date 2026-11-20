# Interaction

Concern: states, feedback, affordances, forms and input, errors, empty states,
overlays and data-dense interaction. An interface is finished when every state a user
can reach has been designed, not only the populated, successful one.

Owned elsewhere: the wording of errors and empty states is `content.md`; flows between
screens are `navigation.md`; keyboard and focus rules are `accessibility.md`; transitions
between states are `animation.md`.

## 1. The state inventory

Before building a screen, list the states it can be in and design each one.

### 1.1 Data states

| State | What it shows |
|---|---|
| Loading, first time | A placeholder in the shape of what is coming (skeleton) when the layout is known; a labelled indicator otherwise |
| Loading, refresh | The previous content stays visible while new data arrives |
| Empty, first use | What will appear here, why it matters, and the action that starts it |
| Empty, no results | The query or filters that produced nothing, and how to widen or clear them |
| Empty, cleared by the user | A light confirmation and an easy way to add again |
| Partial | What loaded, and which part failed or is still coming |
| Populated | The real content, at typical size |
| Overflow | The longest name, the largest number, thousands of rows: wrap, truncate with access to the full value, paginate or virtualize |
| Error | What failed, why if known, and how to recover; scoped to the part that failed |
| Offline or slow | What still works, what is queued, how to retry |
| No permission | Why access is denied and how to get it |

Loading and empty are different states. Never show "nothing here" while the first
request is still in flight.

### 1.2 Control states

Every interactive element defines the ones that apply: default, hover, focus-visible,
active (pressed), selected or current, disabled, pending (in flight), read-only,
invalid.

- Pressed feedback is immediate. A small scale (0.96 to 0.98) or a 1 px shift suits
  buttons; a background change suits list rows. Match feedback to the element's role.
- Selected and current states differ from hover by more than color alone.
- A disabled control that the user needs to understand says why, nearby or on focus.
- Pending state reflects real in-flight work and prevents an unsafe second submission.
- Hover reveals nothing essential. Whatever hover shows is also reachable by focus and
  by touch.

### 1.3 Flow states

Validation, success, failure, recovery, cancel, back, interruption, re-entry, timeout.
Design the path out of each, not only the screen.

### 1.4 What to stress

Put this content through the design before calling it done:

- a 100-character name, a one-character name, an empty optional field;
- numbers in the millions, negative values, zero;
- a list of zero, one, and several thousand items;
- text 30 to 40 percent longer, a right-to-left language, CJK characters, emoji;
- a slow connection, a dropped connection, a failed request, a request that fails once;
- ten rapid clicks on the submit action;
- a session that expires in the middle of the task.

## 2. Feedback and system status

- Every action gets a visible response within about 100 ms, even when the result takes
  longer.
- Waits over about 1 second show an indicator; long operations name what is happening
  and show real progress when it is known. Never show invented progress.
- Update the interface optimistically only when failure is rare and reversible, and
  reconcile visibly when it does fail.
- Place feedback where the user is looking: inline beside the cause. Use a transient
  message for outcomes that need no action; never for errors the user must act on.
- Routine success is quiet: the interface updates. Reserve celebration for effort or
  consequence that merits it.
- Announce changes that happen away from focus through a live region, sparingly.

## 3. Forms

### 3.1 Structure

- Ask only for what the task needs. Mark optional or required consistently.
- One column for most forms. Group related fields; order them as the user thinks.
- Label above the field, always visible, programmatically associated. Helper text
  between label and field or directly below. Error text directly below the field.
- Use the right input type, `autocomplete` token and `inputmode`, so keyboards and
  autofill work.
- State format and eligibility rules before submission, not after.
- Prefer a sensible default to a question. Prefer selection to free text when the
  options are few and known.
- Long forms: split into steps only when the steps are real, show progress, allow going
  back without losing input, and save drafts where loss would hurt.

### 3.2 Validation and errors

- Validate a field when the user leaves it, or on submit. Do not flag a field as wrong
  while the user is still typing its first value; do clear an error as soon as it is
  fixed.
- On submit with errors: keep every valid value, move focus to the first invalid field
  or to an error summary that links to each field, and state the fix for each.
- Associate each message with its field so it is announced.
- Validate on the server as well. Client-side checks are a convenience, not a guarantee.
- A failed submission never clears the form.

### 3.3 Destructive and consequential actions

- Prefer undo to confirmation when recovery is safe.
- Confirm when the action is irreversible and uncommon. The confirmation names the
  object and the consequence, and its button repeats the action's verb.
- Separate destructive actions from frequent ones in space and in weight.

## 4. Overlays

- Use a modal dialog only when the task needs interruption and protected focus. For
  everything else, prefer inline editing, disclosure, a side panel or a separate screen.
- A modal dialog: moves focus inside on open, keeps focus inside while open, closes on
  Escape (unless that would lose data), makes the page behind it inert, has an
  accessible name, and returns focus to a sensible trigger on close.
- Menus, popovers and tooltips are anchored to their trigger, stay within the viewport,
  and are not clipped by a scrolling ancestor.
- A tooltip supplements. It never holds the only copy of essential information, and it
  appears on keyboard focus as well as hover.
- Toasts do not steal focus, stay long enough to read, pause on hover and focus, and are
  not the only record of anything important.
- Use the project's existing overlay primitives, which already handle nesting and focus.

## 5. Data-dense interfaces

### 5.1 Tables and lists

- Use a table when rows are compared across the same fields; use a list when each item
  is read on its own.
- Align numbers to the right with tabular numerals; align text to the start. Column
  headers are real headers and state units.
- Separate rows with one device: spacing, a hairline, or alternating tint. Not all
  three, and not a full border around every cell by default.
- Sorting, filtering and selection are visible as state: which column, which direction,
  how many selected, which filters are active and how to clear them.
- Selection enables bulk actions, shown where the selection is.
- Keep headers, and the identifying first column where needed, visible while scrolling.
- Large sets are paginated or virtualized, with the total count shown. Sort, filter and
  page are restored on reload and by link under the rule in `navigation.md`, section 4,
  which keeps sensitive queries out of URLs.
- Truncated values are reachable in full.
- Row actions work by keyboard and do not depend on hover to be discovered.

### 5.2 Dashboards and monitoring

- Show only data that helps someone decide or act. Lead with what changed or needs
  attention.
- A large number needs a label, a unit, a time range and something to compare it with.
- State when the data was last updated, and show stale or failed tiles as such.
- Use plain layout for metrics; a card around every number adds chrome, not meaning.
- For the charts themselves, use the `dataviz` skill when it is available.

### 5.3 Expert use

- Frequent tasks get shortcuts, bulk paths and remembered preferences.
- Keyboard-triggered actions respond immediately; no transition delays them or hides
  their result. See `animation.md`, section 1.1.
- Density is a preference worth offering when both novice and expert users are served.

## 6. Usability heuristics

Check the finished flow against these. They are the questions; AUDIT.md holds the
specific failures.

1. **Status is visible.** The user can tell what the system is doing and where they are.
2. **The interface speaks the user's language** and follows real-world order.
3. **The user is in control.** Undo, cancel and exit are always available.
4. **Consistent and standard.** The same thing looks and behaves the same; platform
   conventions hold.
5. **Errors are prevented** by constraints, defaults and confirmation where it counts.
6. **Recognition over recall.** Options and context are visible, not remembered.
7. **Efficient for experts** without confusing newcomers.
8. **Nothing irrelevant competes** with what matters.
9. **Errors are explained and recoverable** in plain language.
10. **Help is available** at the point of need, and rarely needed.

For a first-time user: can they identify the action, understand the current state,
predict the result, and recover? For a repeat user: are there wasted steps, waits, lost
context, or missing keyboard paths? These are heuristic judgments; do not report them as
observed research.

## 7. Implementation notes (framework-agnostic)

- Keep one source of truth for each piece of state; derive the rest.
- Use the project's data layer for requests. Guard against stale responses and against
  updates after a view has gone. Preserve input on failure.
- Release what you start: timers, observers, listeners, subscriptions, animations.
- Do not update application state on every pointer or scroll frame; drive continuous
  values through styles or the motion system.
- Use semantic elements: buttons for actions, links for navigation, real form controls.
- Every link and button goes somewhere or does something. A control that is not built
  yet is omitted or shown disabled, not left as a dead link.
- Keep server-rendered and first client markup deterministic: no random values or
  current-time output during render.
- One failing component does not take down the screen. Contain errors to their region.

## Audit coverage

AUDIT items `INTER-01` to `INTER-08`, and `INTER-09` to `INTER-16`. Error
recovery is `INTER-07`. Related: `A11Y-01` to `A11Y-03`, `PERF-02` (feedback latency),
`DARK-01` to `DARK-03` (consent, exit and destructive actions), `CONTENT-01` and
`CONTENT-02`.
