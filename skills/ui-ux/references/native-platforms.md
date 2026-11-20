# Native platforms

Concern: interfaces that ship as native apps on iOS, Android and other native targets,
and mobile screens designed to those conventions. This concern is added to the listed
set because platform rules cut across layout, navigation, interaction and color.

When a platform specialist skill is installed (see the routing table in `SKILL.md`), it
governs the specifics. These are the platform-agnostic rules.

Owned elsewhere: responsive web layout is `layout.md`; native accessibility settings are
`accessibility.md`, section 9; motion is `animation.md`.

## 1. Rules

- **Decide the platform mode first:** iOS conventions, Android conventions, or a
  deliberate, documented platform-neutral treatment. Do not mix one platform's patterns
  into the other.
- **The platform's guidelines govern structure, navigation and interaction** on every
  surface. Brand expresses through the layer the platform leaves open: tint and color
  roles, type accent, motion personality, content.
- **Use platform components** for navigation bars, tab bars, sheets, switches, pickers,
  alerts and menus. Configure the system navigation; do not rebuild it. Reinventing a
  standard control for flavor costs gestures, accessibility and trust.
- **System gestures stay alive:** back-swipe and system Back, pull to refresh where
  expected. A dismissible surface responds to the platform's Back or dismissal gesture.
  A flow that deliberately blocks dismissal to protect unsaved input offers an
  accessible, explicit way to finish or leave.
- **Respect system regions:** safe areas, status bar, home indicator, display cutouts,
  the keyboard. The focused field and the submit action stay visible above the keyboard.
- **Use semantic system colors and text styles** so the app follows dark mode, increased
  contrast and the user's text size. Hard-coded hex and fixed point sizes break there.
- **Touch targets, text scaling and system preferences** follow `accessibility.md`,
  sections 5 and 9.
- **Adapt by size class,** not device model. A phone layout stretched across a tablet is
  a failure; restructure into split views, rails or multi-column layouts. Support both
  orientations unless the task truly requires one.
- **Porting from the web means reconforming:** replace web navigation with the
  platform's model, web-shaped controls with platform controls, hover with touch-first
  affordances.
- **Across a set of screens,** hold one system constant: palette, type rhythm, spacing,
  radius, icon style, navigation model, component family. Vary composition and emphasis
  by screen purpose. The screens should form a believable flow in which each follows
  from an action on the previous one.
- **Verify on a simulator, emulator or device,** never a browser. Check dark appearance
  and a large text size. Simulators give breadth; gestures and performance need
  hardware. Say which produced the evidence.

## Audit coverage

AUDIT item `NATIVE-01` (system navigation and dismissal), and `NATIVE-02`, `NATIVE-03` and
`NATIVE-05` to `NATIVE-07`. Related: `LAYOUT-04` for insets and keyboard, `LAYOUT-03` for
large-text clipping, `TOKEN-01` for theme propagation, `A11Y-03` and `A11Y-05`
(semantics, hit areas). `NATIVE-05` is a minor default tell where neither the brief nor
the existing system asks for the borrowed platform treatment.
