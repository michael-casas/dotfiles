---
name: ui-ux
description: Router and overarching instruction set for any user-interface work. Use when building, restyling, redesigning, extending, reviewing or auditing a UI on any surface - web pages and apps, landing pages, dashboards, forms, navigation, design systems and tokens, mobile and native screens, desktop apps, and HTML artifacts. Covers reading the brief, committing to a visual direction, typography, color and theming, layout and responsiveness, interaction states, forms, motion, accessibility, UX copy, imagery and image-to-UI, and verification of the rendered result. Routes each task type to the right reference and to specialist skills, and ends every task with the mandatory bad-practice audit in references/AUDIT.md. Not for backend-only work, charts alone (use dataviz), or documents and slides.
---

# UI/UX

This file is the router and the instruction set that every UI task follows. It does
not contain the detailed guidance: load the references the routing table names, do the
work, then pass the final gate.

Work as a design lead whose client has already rejected templated proposals. The client
is paying for choices made for this brief: a palette, a typographic voice and a layout
that belong to this subject and could not be mistaken for another product's. Take
aesthetic risk where the brief justifies it, and nowhere else.

## 1. Order of authority

When two instructions conflict, the higher one wins.

1. **Non-negotiables.** Accessibility, factual truth, security and working behavior.
   No brief, taste or deadline overrides them.
2. **The brief.** The user's own words, including a pinned font, palette, era or look.
   Follow a pinned direction exactly, even when it is a look this skill calls a default.
3. **The existing system.** The project's tokens, components, patterns and brand.
   Extend it; do not replace it unless a redesign is authorized.
4. **This skill.** The instructions below and the references.
5. **Your habits.** The choice you would make on any similar project. This one never
   wins. A choice made *because it is the default* is the defect this skill exists to
   remove; the same choice made for a stated reason is fine.

No asset is banned by name. No font, color, radius, icon set, gradient, card or grid is
wrong in itself. What is wrong is reaching for it without a reason, and anything that
objectively harms the user (unreadable contrast, hidden focus, a blocked task).

## 2. Classify before loading anything

State both classifications in one line before designing, for example: "Operate
surface, extend: a bulk-edit panel inside the existing admin."

**Surface: what the visitor came to do.** Classify by the screen, not the company. A
tool's landing page is Persuade; a fashion house's documentation is Read.

| Surface | Visitor's goal | What wins |
|---|---|---|
| **Operate** | Complete a task, watch state, configure, compare | Scanability, predictable controls, visible state, fitting density. Familiarity is a feature. Lead with the task, not a promotional hero; a preview that is the task may lead. |
| **Persuade** | Understand an offer and decide | One idea per section, real proof, a visible primary action. Expression is welcome. |
| **Read** | Understand material | Structure, measure, wayfinding, sustained readability. |
| **Experience** | Explore the work itself | The content leads from the first viewport; the interface recedes but stays usable. |

If a screen spans two, name the primary one and treat the other as secondary. Do not
average them.

**Change: how much is yours to decide.**

| Change | You may decide | You must preserve |
|---|---|---|
| **New** | Direction, system, structure | The brief; platform conventions |
| **Extend** | The new part's content, hierarchy, states | The surrounding visual language and patterns |
| **Refine** | Fixes inside the named scope | Identity, copy, routes, behavior, everything out of scope |
| **Redesign** | The visual system, by agreement | Product truth, content, function, URLs, what must stay recognizable |
| **Review** | Nothing. Report findings. | The work as built |

A missing design document does not make a project new. A narrow fix does not authorize
new branding, copy, navigation or dependencies.

## 3. Instructions for every UI task

Follow these eight in order. Scale the effort to the change: a button fix needs one
line for steps 1 to 3, a new product surface needs all of them in full.

### 3.1 Read the brief and the existing system first

- Identify the subject, the audience and the screen's single primary job. If the brief
  does not say, propose all three in one sentence and confirm.
- Inspect what exists before inventing anything: tokens and theme files, global styles,
  shared components, representative screens, fonts, icon set, assets, dependency
  versions. Read the files that define the visual vocabulary, not only the file tree.
- Ask only what would change the work: one round of at most three related questions.
  Otherwise state the assumption and proceed.

### 3.2 Commit to a direction

- Ground every choice in the subject: its industry, materials, vernacular and the
  audience's own visual world. That is where distinctive choices come from.
- Write a short plan before code: 4 to 6 named colors, the typefaces and their roles, a
  layout concept (one sentence plus an ASCII wireframe), alignment, and the one element
  that should be memorable.
- Test the plan for defaults: ask what you would have produced for any similar brief.
  Wherever the plan matches that, revise it and say what changed and why.
- Spend boldness in one place. Keep everything around it quiet. Remove one decoration
  before shipping.
- On Extend and Refine there is no direction to choose. Inherit it.

### 3.3 Fix structure before decoration

- Decide the reading order, grouping and primary action before choosing colors.
- Structural devices (borders, numbers, labels, dividers, cards) must encode something
  true about the content. A numbered marker needs a real sequence; a card needs a real
  group, comparison or selection.
- Use the real copy and realistic data from the start, including the longest name, the
  empty field and the 3-digit count.

### 3.4 Design every state

For each screen and each interactive component, design the states that can occur:

- **Data:** loading, empty (first use), no results, partial, populated, overflow
  (longest content, thousands of items), error, offline, permission denied.
- **Control:** default, hover, focus-visible, active, selected, disabled, pending.
- **Flow:** validation, success, failure, recovery, cancel, back, re-entry.

Do not invent states that cannot happen. Do not ship only the successful, populated one.

### 3.5 Treat accessibility and responsiveness as defaults

They are part of the build, never a later pass and never announced as a feature.

- Text contrast at least 4.5:1 (3:1 for large text: 18 pt regular or 14 pt bold and
  up). Visual cues needed to identify a control or its state at least 3:1. The
  exceptions are in `references/accessibility.md`, section 5.
- Every function works by keyboard, with visible focus and a logical order.
- Semantic elements and accessible names on every control. No information by color alone.
- `prefers-reduced-motion` honored. Text zoom to 200% and reflow at 320 CSS px work.
- The layout is recomposed for narrow screens, not shrunk. Pointer targets meet the
  target-size rule in `references/accessibility.md`, section 5.

### 3.6 Match or extend the existing design system

- Use the project's tokens, components and patterns. One system per project.
- When a real, published design system fits the brief, use it through its supported
  components or integration. Add a dependency only within the authorized change scope.
  Do not hand-recreate its CSS, and do not imitate a real brand's identity.
- Add a token only for a value with a repeated meaning. Share a component only when it
  is used in two or more places for the same reason, has a nameable role, and has an
  interface smaller than its implementation.

### 3.7 Use motion only where it explains something

- Motion answers an action, shows what changed, or is the one authored moment a
  Persuade or Experience surface has earned. Otherwise the element simply appears.
- The more often a user sees an interaction, the less it animates.

### 3.8 Verify by looking at the rendered result

A passing build proves nothing about the interface.

- Render it. On the web capture at least 375, 768 and 1280 px wide; on native and
  fixed-size artifacts capture the supported device classes or sizes. Cover every
  supported theme.
- Exercise the primary flow, the keyboard path and each state from 3.4.
- Compare the result with the brief and the plan from 3.2.
- Batch the findings, fix them, and confirm with one more round. Two rounds is the
  ceiling for polish; an unresolved non-negotiable is never polish and is never waived.
- If you cannot render it, say exactly which claims are unverified.

## 4. Routing table

Each reference covers one concern. Choose one change row (new build, extend, redesign,
refine or review), then add each concern row the task touches. Read each listed
reference completely; where a row names a section, that section is enough. The native
row applies to platform-native behavior only: responsive web uses `layout.md` and the
relevant task concerns. Always run the handoff row.

| Task | Load from `references/` |
|---|---|
| **New build** (page, app, screen, artifact) | `discovery.md`, `hierarchy.md`, `layout.md`, `typography.md`, `color.md`, `interaction.md`, `content.md`, `accessibility.md` |
| **Extend** an existing product with a new screen or feature | `tokens.md`, `atomic-design.md`, `hierarchy.md`, `interaction.md`, `content.md`, `accessibility.md` |
| **Redesign or restyle** an existing interface | `redesign.md`, `discovery.md`, `tokens.md`, plus the concern files for what changes |
| **Refine or polish** inside a named scope | `redesign.md` (section 6), plus the concern file for the defect |
| **Design system, tokens, theming** | `tokens.md`, `atomic-design.md`, `color.md`, `typography.md` |
| **Components and component libraries** | `atomic-design.md`, `tokens.md`, `interaction.md`, `accessibility.md` |
| **Color, palette, dark mode** | `color.md`, `tokens.md`, `accessibility.md` |
| **Typography** | `typography.md`, `hierarchy.md` |
| **UX copy, labels, error and empty-state text** | `content.md` |
| **Layout, spacing, responsive behavior** | `layout.md`, `hierarchy.md` |
| **Visual hierarchy, density, emphasis** | `hierarchy.md`, `layout.md`, `typography.md` |
| **Motion, transitions, gestures** | `animation.md`, `accessibility.md` |
| **Forms, tables, dashboards, data-dense or multi-step UI** | `interaction.md`, `hierarchy.md`, `layout.md`, `content.md`, `accessibility.md` |
| **Navigation, information architecture, user flows** | `navigation.md`, `hierarchy.md`, `content.md` |
| **Mobile or native app screens** | `native-platforms.md`, `layout.md`, `navigation.md`, `interaction.md`, `accessibility.md`, `animation.md` |
| **Icons, illustration, photography, generated imagery** | `imagery.md` |
| **Image-to-UI, mockup or screenshot reproduction** | `imagery.md`, `layout.md`, `typography.md`, `color.md` |
| **Exploring options before committing** | `discovery.md` (section 4) |
| **Accessibility pass** | `accessibility.md`, `interaction.md`, `color.md` |
| **Review, critique or audit** of existing work | `verification.md`, then `AUDIT.md`, plus the concern file for each area with findings |
| **Every task, before handoff** | `verification.md`, then `AUDIT.md` |

`AUDIT.md` mirrors these concerns. Its item IDs are prefixed by concern: `ANIM-`,
`LAYOUT-`, `HIER-`, `ATOM-`, `TYPE-`, `COLOR-`, `TOKEN-`, `INTER-`, `NAV-`, `CONTENT-`,
`IMG-`, `A11Y-`, `NATIVE-`, plus the cross-cutting `SLOP-` (defaults reached for without a reason),
`PERF-` (performance as experienced) and `DARK-` (deceptive patterns). When an audit
item fails, the file for its prefix holds the positive guidance. `NATIVE-` is
`native-platforms.md`. The cross-cutting prefixes have no file of their own: for
`SLOP-` use `discovery.md` section 3, for `PERF-` use `verification.md` section 7, and
for `DARK-` use `interaction.md`, `content.md` or `tokens.md` according to the failed
check.

### Specialist skills

These stay separate. Use one only when it is installed in the current environment and
the task matches. When it applies, its platform rules outrank this skill's general ones;
this skill's order of authority and final gate still apply.

| When the task involves | Use | For |
|---|---|---|
| An independent review gate before UI work is called done | `the-visionaries` | A multi-reviewer gate on taste, structure and behavior. `AUDIT.md` is the self-check; this is the independent one. |
| Expo or React Native | `expo-native-ui`, `expo-ui`, `expo-animation`, `expo-router`, `expo-design-system` | Platform controls, native motion, navigation, and the in-app token theme |
| A component workshop | The Storybook skills (`stories`, `storybook-*`) | Writing stories and running the workshop |
| Browser-driven accessibility checks, when Chrome DevTools tooling is available | `a11y-debugging` | Accessibility-tree, focus, tap-target and contrast checks |
| Load or rendering performance | `debug-optimize-lcp`, `chrome-devtools` | Measuring and fixing Core Web Vitals |
| Charts, graphs, dashboards of data | `dataviz` | Chart form, color and marks |
| A page published as a claude.ai Artifact | `artifact-design`, `artifact-diagramming` | The artifact page contract and diagrams |
| A project that keeps a Google `DESIGN.md` | `design-md` | Authoring and linting that token file |
| Generating raster images | The environment's image-generation skill or tool | Producing the asset. `imagery.md` says what to produce. |
| Driving a simulator, emulator or desktop app | The environment's device or desktop-control skill | Capturing real native screens for step 3.8 |

Never assume one of these exists. If the task needs one that is absent, say so and
continue with this skill's general guidance.

## 5. Working rules

- **Truth.** Never invent prices, customers, testimonials, metrics, benchmarks or
  capabilities. Sample content is allowed when it is realistic and marked as sample
  wherever a reader could mistake it for fact. Never report a check you did not run.
- **Scope.** Change what was asked. Do not migrate frameworks, swap styling libraries,
  rename routes or add dependencies as a side effect. Check the dependency file before
  importing anything.
- **Stack.** Guidance here is framework-agnostic. Use the project's installed stack and
  its idioms.
- **Evidence over assertion.** Do not describe the result as premium, polished or
  award-level. Show what was built and what was verified.

## 6. Final gate (mandatory)

Before handing off any UI work, including a small fix:

1. Open `references/AUDIT.md` and read how to run it. `references/verification.md`
   section 9 gives the procedure around it.
2. Run every applicable checklist item against the **rendered result** at the widths and
   themes from 3.8, and against the code.
3. For each hit, when you are the author: fix it and retest, or record a justified
   exception. An exception is valid only when it is a deliberate choice the brief
   supports, and never for a blocker item. Otherwise the handoff is reported blocked.
   When you are reviewing only: record each open failure with its evidence and fix
   direction, and do not repair unless authorized.
4. Re-check every item you fixed.
5. Report the result in the format `AUDIT.md` specifies.

The work is not finished until this report exists. For a Review task the audit report is
the deliverable. If `AUDIT.md` cannot be run in full (no renderer, no device), run what
can be run and list the items left unchecked as unverified, not as passed.

## 7. Handoff

Report, in this order:

1. What was built or changed, and the classification from section 2.
2. The few design decisions that matter, each with its reason from the brief.
3. What was verified and how: widths, themes, states, keyboard path, evidence paths.
4. The audit report from section 6.
5. What remains unverified, assumed, or out of scope, and any content the user must
   replace (sample data, missing assets).
