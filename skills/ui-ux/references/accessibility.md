# Accessibility

Concern: the WCAG 2.2 level AA floor: semantics, names, keyboard, focus, perception,
target size, motion sensitivity, forms, cognitive load, and how to test them.
Accessibility is observable behavior, built in from the first component. AA is the
floor unless the brief sets a higher level.

## 1. Semantics first

- Use the native element for the job: `button` for actions, `a` with an `href` for
  navigation, real form controls, real headings, lists and tables.
- ARIA adds what native HTML cannot express. It does not repair a wrong element, and it
  does not add keyboard behavior. When a custom widget is unavoidable, implement the
  full keyboard pattern for its role, or use a proven accessible primitive.
- One `h1` per page or view. Heading levels descend without skipping and reflect the
  structure, not the desired size.
- Use landmarks: header, navigation, main, footer; label repeated landmarks.
- Set the document language. Give every page or view a unique, descriptive title.
- DOM order is the reading order and the focus order. Do not reorder visually in a way
  that contradicts it.
- Data tables have header cells with scope; layout is never done with tables.

## 2. Names, labels and alternatives

- Every interactive element has an accessible name that matches or contains its visible
  label.
- Icon-only controls have a name. Decorative icons and images are hidden from assistive
  technology.
- Every form field has a persistent, associated label. Groups of related controls have
  a group label.
- Meaningful images have alt text that conveys what the image tells a sighted user in
  this context. Decorative images have empty alt text. Never "image" or a filename.
- Complex images (charts, diagrams) have a text summary or data alternative nearby.
- Time-based media has the alternative its type requires:
  - prerecorded audio-only or video-only content: an equivalent alternative, such as a
    transcript or a description (SC 1.2.1);
  - synchronized media with audio: captions, prerecorded (1.2.2) and live (1.2.4);
  - prerecorded synchronized media: audio description of the visual information needed
    to understand it (1.2.5).

  Media that is itself a clearly labelled alternative to text on the page is exempt
  where the criterion says so.
- Nothing plays sound automatically.
- Link text makes sense out of context.

## 3. Keyboard

- Everything that works with a pointer works with a keyboard.
- Tab order follows the visual order. No positive `tabindex`.
- No keyboard trap: focus can always leave a component, except inside an open modal
  dialog, which it leaves by closing.
- Composite widgets (menus, tabs, listboxes, grids) use arrow keys inside and a single
  tab stop, following the established pattern for the role.
- Provide a way to skip repeated blocks: a skip link to the main content.
- Shortcuts that use a single character can be turned off or remapped.
- Custom scroll regions are focusable so they can be scrolled by keyboard.

## 4. Focus

- Focus is always visible. Style `:focus-visible`; never remove the outline without a
  replacement.
- The AA floor is three checks: focus is visible (SC 2.4.7); the focused element is not
  entirely hidden by sticky headers, footers or overlays you created (2.4.11); and the
  indicator meets non-text contrast, 3:1, where 1.4.11 applies.
- Enhanced target, not the floor: an indicator at least as large as a 2 px perimeter
  around the element with 3:1 change contrast (2.4.13, level AAA).
- Manage focus on change: into a dialog on open and back to the trigger on close; to
  the new view's heading or main region on client-side navigation; to the first error
  or an error summary after a failed submit; to a sensible neighbor after deleting the
  focused item.
- Focus is never lost to the top of the document.

## 5. Perception

| Requirement | Threshold |
|---|---|
| Text contrast | 4.5:1 |
| Large text contrast: 18 pt regular or 14 pt bold and larger (24 CSS px, or about 18.67 CSS px bold; do not round down) | 3:1 |
| Non-text contrast: the visual cues needed to identify a control, its state, or a meaningful graphic | 3:1. Inactive controls and unmodified browser controls are exempt. |
| Text resize | Usable at 200 percent zoom without loss of content or function |
| Reflow | No two-dimensional scrolling at 320 CSS px wide, except for content that needs it (data tables, maps, diagrams) |
| Text spacing | No loss when line height is 1.5, paragraph spacing 2, letter spacing 0.12 and word spacing 0.16 times the font size |
| Target size (SC 2.5.8) | 24 by 24 CSS px, or the spacing test below, with the listed exceptions |

**Target size.** This file owns the rule; other files link here.

- A target passes at 24 by 24 CSS px. A smaller target passes the spacing test when a
  24 CSS px diameter circle centered on its bounding box intersects neither another
  target nor the circle of another undersized target.
- Exceptions: a target in a sentence, or one whose size is constrained by the line
  height of surrounding non-target text; a control whose function is available through
  another conforming control on the same page; an unmodified browser control; a size
  that is essential or legally required.
- Text contrast exempts logos, incidental and decorative text, and inactive controls.
- Larger targets are a usability aim, not the AA cutoff: about 44 to 48 CSS px for
  primary touch controls on the web. Native design guidance is in its own units: 44 by
  44 pt on iOS and 48 by 48 dp on Android, with spacing between targets.

- Never convey information by color alone. Add text, an icon, a pattern, a shape or a
  position.
- Measure contrast from computed, composited colors, in every state and every theme,
  including text over images and gradients.
- Support forced-colors mode: do not rely on background images or box shadows to show
  state or boundaries.
- Do not lock orientation unless the task requires it.
- Content that appears on hover or focus can be dismissed, can be hovered itself, and
  stays until dismissed.

## 6. Time, motion and change

- Honor `prefers-reduced-motion`. See `animation.md` section 9.
- This file owns the pause and flash rules; `animation.md` links here.
  - **Moving, blinking or scrolling content** that starts automatically, lasts more
    than 5 seconds and is shown alongside other content has a control to pause, stop or
    hide it, unless the movement is essential (SC 2.2.2).
  - **Auto-updating content** that starts updating automatically alongside other content
    has a control to pause, stop, hide or set the update frequency, unless the updates
    are essential. There is
    no five-second allowance for updates.
  - **Flashing:** nothing flashes more than three times in any one-second period,
    unless the flash is below the general and red flash thresholds (2.3.1).
- Time limits can be turned off, adjusted or extended, and the user is warned before one
  expires. Data entered is not lost on timeout.
- Changing a setting or focusing a field does not cause an unexpected change of context.
- Status messages (saved, loading, results updated, errors) reach assistive technology
  through a live region without moving focus. Use polite announcements by default;
  assertive only for urgent errors. Do not announce every keystroke.

## 7. Forms and errors

- Errors are identified in text, associated with their field, and say how to fix the
  problem.
- Required fields are indicated in text or programmatically, not by color or an
  unexplained symbol alone.
- Use `autocomplete` tokens for personal data.
- Do not ask for the same information twice in one process; prefill or offer it.
- Authentication does not depend on a memory or puzzle test with no alternative; allow
  paste and password managers.
- For legal, financial or data-deleting submissions, allow review, correction or undo.

See `interaction.md` section 3 for form design.

## 8. Cognitive load

- One primary task per screen, with a clear visual hierarchy.
- Present information in small groups. Group options by the decision they support;
  `hierarchy.md`, section 4, owns the principle and has no fixed count.
- Do not make the user carry information from one step to another.
- Reveal complexity progressively. Use plain language and define unavoidable terms.
- Keep patterns consistent so learning transfers.
- Help and the way to get human support appear in the same place on every screen.

## 9. Native platforms

Structure and controls on native platforms are in `native-platforms.md`.

- Use platform controls, which carry roles, traits and gestures for free.
- Give custom controls an accessibility label, role, value and state.
- Follow the system text size setting; layouts survive the largest sizes without
  clipping.
- Use semantic system colors so increased-contrast and dark appearance work.
- Respect the system reduced-motion and reduced-transparency settings.
- Native touch-target guidance is in section 5.

## 10. Testing

Automated checks find a minority of problems. Run all of the following that the
environment allows, and report which ones you ran.

1. **Automated scan** with the project's accessibility linter or a browser audit. Read
   the failing elements, not only the score.
2. **Keyboard pass.** Complete the primary flow using only Tab, Shift+Tab, Enter, Space,
   Escape and arrow keys. Watch for invisible focus, wrong order, traps and unreachable
   controls.
3. **Accessibility tree.** Inspect names, roles, states, headings and landmarks.
4. **Zoom and reflow.** 200 percent zoom, then a 320 px wide viewport.
5. **Contrast.** Compute it for text, controls and focus indicators in each theme.
6. **Reduced motion and forced colors.** Emulate each and re-check.
7. **Screen reader,** when one is available: read the page by headings, operate each
   form, trigger each error and status message.

When browser tooling is available, the `a11y-debugging` skill (see the routing table in
`SKILL.md`) provides ready checks for the tree, focus, tap targets and contrast.

Do not claim conformance from an automated scan. State what was tested and what was not.

## Audit coverage

AUDIT items `A11Y-01` to `A11Y-09`, and `A11Y-10` to `A11Y-15`. Related:
`COLOR-01` to `COLOR-03` (contrast and color-only meaning), `INTER-06` to `INTER-08`
(labels, validation, redundant entry), `ANIM-03` to `ANIM-05` (reduced motion, flashing,
pausing). Bypass and focus order are `A11Y-02` and `A11Y-04`; location and return are
`NAV-01`.
