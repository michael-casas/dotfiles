# Animation

Concern: motion, easing, duration, springs, gestures, scroll-linked effects and reduced
motion, including the review of motion code. Motion is justified by what it explains.
Static is correct whenever animation adds nothing.

Owned elsewhere: motion tokens are `tokens.md`; motion sensitivity as an accessibility
requirement is `accessibility.md`, section 6.

## 1. Decide in this order

Answer each question before writing animation code.

### 1.1 Should it animate at all?

| How often the user sees it | Decision |
|---|---|
| 100 or more times a day (keyboard shortcuts, command palette, typing) | No animation |
| Tens of times a day (hover, list navigation, tab switches) | None, or barely perceptible |
| Occasionally (dialogs, drawers, toasts, page changes) | Standard transition |
| Rarely or once (onboarding, a milestone, a marketing reveal) | Room for an authored moment |

Make keyboard actions and focus updates immediate. Remove transitions that delay a
repeated command or hide its result. Keep useful feedback that does not block, and
honor reduced motion.

### 1.2 What does it explain?

Valid purposes:

- **Feedback:** the interface acknowledges an action.
- **State:** something changed, and the transition shows what.
- **Continuity:** where an element came from or went, across a layout or navigation
  change.
- **Relationship:** this panel belongs to that trigger.
- **Attention:** one thing needs noticing now.
- **Authored moment:** a deliberate expression of the brand, used once.

State the purpose in one sentence. If the sentence is "it looks good", and the user
will see it more than rarely, remove the animation.

### 1.3 How much, by surface

- **Operate and Read:** feedback, state and continuity only. No page-load choreography;
  the user arrived to work.
- **Persuade and Experience:** one orchestrated moment (a load sequence, a reveal, a
  signature interaction) lands better than effects on every section. Derive it from the
  subject: what does this thing do between states in real life? Surround it with quiet.
- Non-user-triggered motion is used sparingly on every surface.

## 2. Easing

Choose by what the element is doing.

| Situation | Easing |
|---|---|
| Entering, exiting, responding to input | Ease-out: fast start, gentle arrival |
| Moving or morphing while staying on screen | Ease-in-out |
| Hover and color changes | A gentle ease |
| Constant motion (progress, marquee, scrubbing) | Linear |
| Unsure | Ease-out |

- No single easing is banned. Ease-in-out is correct for on-screen movement and linear
  is correct for constant motion. The defect is an easing that does not match the job:
  ease-in on an element that responds to input makes the interface feel late, because
  the slow part comes exactly when the user is watching.
- Built-in keyword curves are mild. A stronger custom curve gives a clearer arrival, for
  example `cubic-bezier(0.16, 1, 0.3, 1)` or `cubic-bezier(0.23, 1, 0.32, 1)` for
  ease-out and `cubic-bezier(0.77, 0, 0.175, 1)` for ease-in-out. Define two or three
  curves as tokens and reuse them.
- Bounce and elastic curves need a reason: a playful brand, or a drag released with
  momentum.

## 3. Duration

| Element | Duration |
|---|---|
| Press feedback | 100 to 160 ms |
| Tooltip, small popover | 125 to 200 ms |
| Dropdown, select, routine state change | 150 to 250 ms |
| Dialog, drawer, layout or view transition | 200 to 500 ms |
| Authored focal sequence | 500 to 800 ms, longer only with user control |

These are starting values to tune on the target device, not limits.

- Treat about 300 ms as the point past which a routine transition needs a reason, such
  as a long travel distance. Past it, users read the wait as the system being slow.
- Scale time with the size of the change: a small control settles sooner than a panel
  crossing the screen.
- Let things leave more quickly than they arrive.
- The two halves of one interaction can run at different speeds. A deliberate hold may
  build slowly, for example over 2 s, while the release that follows completes in
  about 200 ms.
- Offset the items of a group only when they truly arrive as a group. Keep each offset
  short (tens of milliseconds, 30 to 80 as a start) and the whole run brief (about
  400 ms). The group is usable while it plays. Sections reached by scrolling are not a
  group.

## 4. Physical correctness

- Nothing appears from nothing. Enter from a scale of 0.9 to 0.97 with opacity, never
  from 0.
- Anchored surfaces grow from their trigger: set `transform-origin` to the trigger's
  position for popovers, menus and tooltips. Centered dialogs keep a centered origin.
- An element leaves the way it came, so a dismiss gesture feels consistent.
- After the first tooltip in a group has opened, neighbors open at once with no delay
  and no transition.
- Percentage translations move an element by its own size, which survives content
  changes; prefer them to fixed pixel offsets for drawers and toasts.
- A crossfade between two states that still looks like two objects can be bridged with a
  brief, small blur (about 2 px) during the change.
- Match motion to personality. A playful component may be bouncier; a professional tool
  stays crisp. One motion language across the product.

## 5. Springs and gestures

- Use springs for dragging, for gesture-driven motion that can be interrupted, and for
  elements meant to feel alive. A spring keeps its velocity when retargeted.
- Keep bounce low (0.1 to 0.3) and reserve it for playful or drag-release contexts.
- Dismiss on velocity as well as distance: a quick flick dismisses even when short.
- Past a boundary, resist with increasing friction; do not stop dead.
- Capture the pointer once a drag starts, and ignore additional touch points.
- Every gesture has a visible, non-gesture way to do the same thing.
- Test gestures on a physical device.

## 6. Interruptibility

- Anything triggered rapidly or reversibly (toggles, toasts, hover, drags) continues
  from its current position. CSS transitions and springs retarget by design. Keyframe
  animations restart from the beginning. A new Web Animations API animation does not
  continue from the interrupted position on its own: read the current value and start
  from it. Retargeting is a property of the implementation, not a guarantee of an API.
- Keyframes suit predetermined sequences that run once.
- Test rapid toggling, reversal mid-flight, and a route change during the animation.
- Each animated property has exactly one owner. Two libraries, or a library and a style
  rule, writing the same property will fight.

## 7. Performance

- Default to `transform` and `opacity`; they avoid layout. They are a good default, not
  a guarantee: measure on the target device before claiming smoothness.
- Other properties are legitimate material when bounded: blur, backdrop filters,
  clip-path, masks and shadows on small, isolated regions. Keep blur radius modest and
  keep backdrop blur off large scrolling areas.
- Do not animate layout properties (`width`, `height`, `top`, `left`, margins, padding)
  when a transform, a FLIP technique or a grid-track transition can express the change.
- List the properties being transitioned. `transition: all` animates things you did not
  intend.
- Do not drive a subtree's motion by changing an inherited custom property on a parent
  every frame; set the transform on the element.
- Do not write application state on every scroll or pointer frame. Use scroll-driven
  animation, an intersection observer, or the motion library's values.
- Apply `will-change` only to elements about to animate, and remove it afterwards.
- Prefer native CSS transitions and the Web Animations API for simple, predetermined
  motion. Use the project's installed motion library for orchestration, layout
  continuity and gestures. Do not add a library for an effect the stack already
  expresses. Declarative CSS animation keeps running when the main thread is busy;
  script-driven animation may not.
- Fixed, full-viewport texture layers (grain, noise) sit on a fixed, non-interactive
  element, never on a scrolling container.
- Clean up on unmount: animations, observers, scroll triggers, timers.

## 8. Resilience

- Content is visible by default. An entrance animation enhances an element that is
  already there; if the script fails, the tab is hidden, or the observer never fires,
  nothing stays invisible.
- Prefer native scrolling. Scroll-linked motion is used only when the scroll
  relationship itself carries meaning, and it has a non-pinned fallback and works by
  keyboard and touch.
- Loops that are not essential stop when off screen or when the tab is hidden.
- Automatic movement, auto-updating content and flashing follow the pause and flash
  rules in `accessibility.md`, section 6.

## 9. Reduced motion

- Honor `prefers-reduced-motion` for every non-trivial animation, at every intensity.
- Reduced means fewer and gentler, not none. Remove spatial movement, parallax,
  scaling and looping. Keep opacity and color changes that carry meaning, such as
  feedback confirming an action.
- An instant change is often the best alternative.
- State must be fully understandable with all animation removed.
- On native platforms, follow the system setting for reduced motion and prefer the
  platform's own transitions.

## 10. Reviewing motion

- Review live playback or a recording. A screenshot cannot show timing.
- Slow playback to a fifth of normal speed or step frame by frame: check that the
  origin is right, that coordinated properties stay in sync, that there is no flash of
  two overlapping states, and that the easing does not start or stop abruptly.
- Look again later with fresh eyes before calling it done.
- When a motion finding needs fixing, prefer the earliest remedy that works:
  1. Delete the animation.
  2. Reduce it: shorter, smaller, fewer properties.
  3. Fix the easing.
  4. Fix the origin and the starting state.
  5. Make it interruptible.
  6. Move it to cheaper properties.
  7. Adjust enter and exit timing.
  8. Add reduced-motion handling and input gating.
- Report each motion finding as a before, an after, and a reason, with file and line.

## Audit coverage

AUDIT items `ANIM-01` to `ANIM-05`, and `ANIM-06` to `ANIM-13`. A repeated
blocking entrance is `ANIM-01`; an identical entrance on every section is `ANIM-06`.
Related: `PERF-02` and `PERF-03` (stalled input, content hidden by a failed
reveal), `A11Y-01` (alternative input for gestures).
