# Atomic design

Concern: component architecture. The levels of composition (atoms, molecules, organisms,
templates, pages), where a new piece belongs, when a pattern is extracted into a shared
component, how a component's interface is shaped, and how all of this fits an existing
system.

Owned elsewhere: token structure is `tokens.md`; the states a component must define are
`interaction.md`; component accessibility is `accessibility.md`; the visual decisions a
component encodes are `typography.md`, `color.md` and `layout.md`.

## 1. The model

Atomic design is a vocabulary for moving between part and whole. It is not a process to
follow in order, not a folder structure, and not tied to any framework.

| Level | What it is | Common modern name |
|---|---|---|
| Token | A named value. Not functional until a component applies it. Sits below the atom. | Primitive, foundation |
| Atom | The smallest functional unit: a label, an input, a button | Primitive component |
| Molecule | A few atoms working as one unit with one job: a search field with its label and button | Composite |
| Organism | A distinct section built from molecules, atoms or other organisms: a header, a product grid | Section |
| Template | A layout that places components and fixes the content's structure and limits, not its content | Layout |
| Page | A template filled with real, representative content. It tests the system. | Screen, example |

- Use the project's own names for these levels. Teach the mapping once and then speak
  the project's language.
- Work at several levels at once. A page that breaks with real content is fixed in the
  component or token below it, not patched on the page.
- Motion, flows and testing sit beside this model, not inside it.

## 2. Placing a piece

- **Do not debate the level.** If a choice is needed, decide by responsibility: a
  molecule does one job as one unit, even when its parts are library components (the
  search field in section 1); an organism is a distinct section that carries several
  jobs. Then move on.
- **Organize files by job or domain,** unless the project already uses level folders.
  Level folders force a reclassification every time a component grows. Follow the
  project's convention either way.
- **Templates define structure and constraints:** regions, image ratios, the lengths the
  layout tolerates. Real content arrives through pages, stories or examples.
- **Test pages with realistic extremes:** zero, one and many items; the longest and the
  empty string. See `interaction.md`, section 1.4.
- **Components consume semantic or component tokens, never raw values.** See
  `tokens.md`, section 3.

## 3. Working in an existing system

1. **Discover first.** Check the dependencies for a component library, then the shared
   components directory, the component workshop or catalogue, and the tokens. Inventory
   the existing treatments of the element you need.
2. **The existing system is the source of truth.** Extend it in its own idiom: its
   names, its prop conventions, its file layout. Never start a second component kit
   beside it.
3. **Reach for what exists, in this order:**
   1. compose existing components;
   2. add a variant or a slot to the closest existing component;
   3. write a new component.

   Before step 3, list the closest existing components with what each shares and what
   each lacks. If nothing is lacking for one of them, extend that one.
4. **A component entering the shared library must be useful and unique:** it passes the
   promotion test in section 4 and is not a near copy of something that exists. A
   component local to one screen needs neither.
5. **One canonical copy per component.** In an installed library, extend through its
   extension points and do not fork. In a project that owns the component source, edit
   the one copy; do not copy it again.
6. **A wrapper must add something:** defaults, context, behavior or a constraint. A
   wrapper that only renames is removed or replaced by a re-export.
7. **Do not wrap what already carries the design language:** platform controls and
   library components used as intended.
8. **Fixes go to the system.** A defect found on one screen is fixed in the shared
   component or token.
9. **Retire with a pointer.** A deprecated component names its replacement.

## 4. Extracting a shared component

Extract into the shared layer only when all three hold:

- it is used, or is about to be used, in two or more places **for the same reason**;
- it has a role you can name;
- its interface is smaller than its implementation.

Until then, keep it beside the screen that uses it. Promote one step at a time: inline,
then local to the screen, then shared.

- Do not extract on visual similarity alone. Two things that look alike but change for
  different reasons stay separate. Duplication is cheaper than the wrong abstraction.
- When a new need almost fits a shared component, do not add a parameter and a branch.
  If shared code already carries per-caller conditionals, inline it back into its
  callers and extract again from what is actually common.
- Not every request becomes a pattern. Treat a new piece as a one-off until a second
  consumer appears.

## 5. Shaping the interface

- **Variant.** Visual intent is one enumerated option (for example `primary`,
  `secondary`, `destructive`). Never parallel booleans for the same concern, and never
  two options that both set one concern.
- **Size.** A small closed scale that maps to spacing and type tokens, with a default.
- **State.** Disabled, loading, selected, invalid and the pointer and focus states are
  explicit, and impossible combinations cannot be expressed. The full list is in
  `interaction.md`, section 1.2.
- **Content.** Content goes in the framework's child-content or named-slot mechanism.
  Options are for contract and behavior. When options start naming content (a leading
  icon, a subtitle, a footer text), switch to composition or slots.
- **Compound components.** Use a set of cooperating parts when the parts share state
  the caller should not manage: tabs, menus, select, accordion, dialog. Use a single
  component when there is nothing to share.
- **Overrides.** Accept a style override and apply it last. It may change layout
  (margin, width, placement), not identity (color, type, radius). A caller restyling a
  component's identity means a variant is missing.
- **Familiar names.** Reuse the platform's and the library's option names (`value`,
  `disabled`, the change handler) instead of inventing synonyms.
- **Split or vary.** Use a variant when the role and the option set stay the same and
  only the visual intent changes. Split into a separate component when one variant
  needs options the others must not accept.
- **Hard behavior.** When focus management, keyboard interaction and accessibility
  semantics are difficult and the look must vary, build on a behavior-only (headless)
  layer or a proven accessible primitive. Do not hand-roll it.

## 6. Naming

- Name components and variant values by role and purpose: `destructive`, `warning`,
  `card`. Not by appearance (`red`, a "big blue button") and not by location (a
  "homepage hero").
- Do not mix purpose names and appearance names in one option.
- Two layers, two naming rules:
  - **system components** get agnostic, structural names: `Card`, `Carousel`;
  - **domain components** that bind data get names from the data: `ProductCard`, built
    from the agnostic `Card`.

## 7. Responsibility

- A component is concerned with one thing. When it grows a second concern, decompose it.
- **Shared components do not fetch data,** read global stores or call services. They
  receive data and report events. The screen or feature that uses them owns the data.
  This applies to the shared layer only; do not add a container file to every
  component.
- A shared component renders in isolation with supplied data, in each of its states.
- Keep a story, example or fixture for each meaningful variant, size and state beside
  the component.
- Review a component for a split when any of these is true. They are triggers for a
  look, not limits:
  - more than about 8 options beyond its basic contract;
  - three or more booleans that interact;
  - more than one data source;
  - an honest name that needs "and";
  - an internal helper that renders a whole sub-part.

## Audit coverage

AUDIT items `ATOM-01`, `ATOM-03`, `ATOM-04`, `ATOM-09` and `ATOM-10`. Related:
`TOKEN-01` (theme propagation), `INTER-01` to `INTER-05` (state behavior), `A11Y-01` to
`A11Y-03`, and `A11Y-11` for semantics lost in a hand-rolled control.
