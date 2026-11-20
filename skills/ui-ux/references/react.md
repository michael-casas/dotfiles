# React

Concern: implementing an interface in React: component contracts, state, effects, data
and async behavior, rendering boundaries, and performance.

**Scope.** Load this file only when the project already uses React or the brief asks
for it. Nothing here applies to native, server-rendered-only or other-framework work,
and nothing here is a reason to choose React. The stack-neutral rules these build on are
in `interaction.md`, section 7, and `atomic-design.md`.

## 1. Read the project first

- Check the installed React version, the framework around it (if any), the router, the
  data layer, the styling method and the component primitives. Keep their contracts.
- React does not imply a meta-framework or server components. Use server and client
  boundaries only when the installed framework provides them.
- Use the APIs of the version that is installed, not the newest ones you know.

## 2. Components and props

- Build each component around one recognisable visual or interaction concept.
- A presentational component renders what it is given and reports events through
  callbacks. Fetching, navigation and workflow belong where the project already puts
  them. Do not add a controller or container file that only passes values through.
- Split a component when ownership, reuse or complexity calls for it. Line count alone
  is not a reason.
- Keep the public props few and meaningful. Model exclusive choices as one variant or a
  discriminated union, never as boolean flags that can contradict each other.
- Use native attribute names for native behavior.
- Give each label and its control a stable, unique id, generated once per instance.
- Key list items by a stable identifier from the data. An array index is a valid key
  only for a list that never reorders, filters, inserts or deletes.
- A wrapper around a library primitive forwards its ref and passes through its
  accessibility attributes and event handlers.
- Keep types readable: name the props type, avoid `any`, and let the type show which
  combinations are legal.

## 3. State

- Keep one source of truth for each fact.
- Compute a value during render when it can be derived from props or state. Do not copy
  props, or a filtered or sorted version of data, into state unless the copy must
  deliberately diverge over time (a draft being edited, for example).
- Keep state in the component that uses it. Lift it only when two components truly
  share it.
- Use a reducer when transitions between states are complex enough to need names. Do
  not add a global store to avoid passing a few props.
- State that should survive reload or be shared by link belongs in the URL, under the
  rule in `navigation.md`, section 4.

## 4. Effects

- An effect synchronizes the component with something outside React: a subscription, a
  timer, an observer, a browser API, a third-party widget.
- An effect is the wrong tool for three things: responding to a user event (use the
  handler), computing a value from props or state (compute it in render), and loading
  data that the framework or data library can load.
- List every dependency the effect reads. Do not silence the dependency check.
- Every effect that starts something returns a cleanup that stops it: timers,
  observers, listeners, subscriptions, animation instances, in-flight requests.
- Check behavior under development double-invocation (Strict Mode): an effect that
  breaks when mounted, unmounted and mounted again has a missing or asymmetric cleanup.

## 5. Data and async

- Load and mutate through the project's query library, router loaders or server
  mechanisms. Do not hand-roll fetching beside them.
- Ignore or cancel a response that arrives after its request is obsolete, and one that
  arrives after the component has gone.
- Guard a mutation against being sent twice. Pending state is true exactly while the
  work is in flight.
- On failure keep what the user entered, and reconcile any optimistic update visibly.
- Decide cancellation and retry per request. Do not retry automatically something that
  is not safe to repeat.

The states these produce are designed in `interaction.md`, sections 1 and 2.

## 6. Rendering boundaries and security

- Server-only modules, credentials and secrets never reach a client bundle.
- The server render and the first client render produce the same markup. Keep random
  values, the current time, locale-dependent formatting and browser-only globals out of
  that first render.
- Where server rendering or server components exist, mark the smallest leaf that needs
  the browser as client-side, not a whole page.
- Treat HTML that came from users or third parties as untrusted. Do not inject it
  without sanitizing.
- Hiding or disabling a control is not access control. The server enforces permission;
  the interface only reflects it.
- A form has real validation and a real failure path, not only a success message.

## 7. Performance

- Do not set React state on every pointer-move or scroll frame. Drive continuous values
  with CSS, a ref, or the motion library's values on the element that owns them.
- Measure before adding memoization, virtualization or a cache. Fix the measured
  bottleneck: asset size, code delivery, an expensive layout, a slow interaction.
- Do not add an animation, data or icon library when the installed one can do the job.
  Libraries may coexist, but two of them must not drive the same animated property or
  the same lifecycle. See `animation.md`, section 6.

## 8. Maintenance

- Every import resolves to an installed dependency. Check the dependency file first.
- Types check and the project's lint rules pass.
- Put tests at behavior seams: what the user does and sees, not implementation detail.
  Do not weaken a test to make a change pass.
- No abstraction without a present use, no commented-out alternatives, and no dependency
  upgrades unrelated to the task.

## Audit coverage

`AUDIT.md` has no React-specific prefix. The items these rules most often prevent are
`ATOM-03` (contradictory option flags), `ATOM-04` (state shared between instances),
`INTER-03` (duplicate operations), `INTER-05` (out-of-order responses), `INTER-10`
(populated-case-only views), `ANIM-02` (motion out of sync after interruption),
`PERF-02` (stalled input), `A11Y-11` (non-semantic controls), `INTER-17` (rows keyed by
position), `INTER-18` (work left running after a view closes) and `PERF-07` (server and
client renders that disagree).
