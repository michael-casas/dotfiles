# Discovery

Concern: reading the brief and the existing system, committing to a visual direction,
and exploring variants before committing.

Owned elsewhere: composition by surface is `hierarchy.md`; information architecture and
flows are `navigation.md`; changing an existing product is `redesign.md`.

## 1. Discovery, scaled to risk

| Change | Discovery to do |
|---|---|
| Small fix or refinement | Inspect the target and its nearest neighbors. No brief, no questions. |
| New screen in an existing product | Resolve the task, the content, the states. Inherit the look. |
| New surface or redesign | Resolve everything in 1.1 before choosing anything visual. |

### 1.1 What to resolve

1. **Actor and situation.** Who arrives, from where, in what state of mind, on what
   device, how often.
2. **Job.** The one thing they must understand or do, and the observable outcome that
   counts as success.
3. **Cost of error.** What goes wrong if they misread or mis-tap. High cost means more
   confirmation, clearer state and less novelty.
4. **Material.** The real content, data, proof and assets the screen must carry, with
   minimum, typical and maximum sizes.
5. **Constraints.** Platform, framework, brand commitments, accessibility level,
   performance budget, localization, legal copy.
6. **Boundaries.** Which existing choices does the brief protect? Give one example of a
   change the audience would reject.

### 1.2 Reading the existing project

Look for each of these before proposing anything:

- Token and theme definitions: CSS custom properties, a utility-framework config, a
  component-library theme, token JSON.
- Shared component directories and any component workshop.
- Font loading and the icon set in use.
- Routes, layouts and page templates that show the established patterns.
- The UI dependencies and their versions.

What exists is the starting vocabulary. A brief extends it.

### 1.3 Asking

- Ask one round of at most three related questions, and only questions whose answers
  change the work. For each, offer your recommended answer.
- Do not ask for CSS values or offer a menu of named aesthetics. Ask about people,
  tasks, content and boundaries.
- If the brief already answers it, or the default is obvious, state the assumption and
  proceed.
- When no one can answer, mark the assumptions in the handoff.

### 1.4 The design contract

Before substantial implementation, write this in at most ten lines:

- Primary task and success condition.
- Highest-priority content and the primary action.
- Surface and change classification.
- Existing commitments, and what is authorized to change.
- Visual direction, stated as concrete composition and type choices.
- States that matter, responsive behavior, and the purpose of any motion.
- Assumptions, available assets, open blockers.
- What is out of scope.

A small fix needs one line. Keep the contract where you will re-read it during the build.

## 2. Structure before direction

Structure is decided before visual direction. Before section 3, settle:

- the composition that fits the surface: `hierarchy.md`, section 1;
- navigation, flows and first use: `navigation.md`.

## 3. Visual direction (new builds and authorized redesigns)

### 3.1 Derive it from the subject

1. Write one sentence saying what only this product can claim, and what a visitor
   should be convinced of before scrolling.
2. Collect raw material from where the audience already spends its attention: the
   things they handle, the places they work, what they read, the diagrams and signs
   they rely on. Gather several, and make sure they do not all come from one kind of
   source.
3. Write down the look most products of this kind end up with, and the look you would
   get by simply reversing it. Set both aside; neither is a decision.
4. Develop the most promising material into whole directions, each with a palette, type,
   a layout idea and one signature element.

Do not pick a direction by randomizing, rotating through a list, or avoiding what you
"used last time". Variety comes from the subject, not from dice.

### 3.2 Write the plan

- **Color:** 4 to 6 named values with roles. Choose a strategy first; see
  `color.md`.
- **Type:** the families and what each is for. See `typography.md`.
- **Layout:** one sentence, plus an ASCII wireframe of the first viewport and one later
  section. State the alignment: left, centered or justified.
- **Signature:** the one memorable element, and what stays quiet around it.
- **Principles:** two or three rules that make this page unlike a neighbor's.

### 3.3 Test the plan against defaults

Run these checks and revise whatever fails. State what you changed and why.

- **Similar-prompt test.** Work a neighboring brief in your head. Wherever the two plans
  coincide, that part is a default.
- **Category test.** If someone could guess the look from the product category alone,
  or from "the category, but avoiding the obvious", it is not yet specific.
- **Swap test.** If an unrelated product could use the composition unchanged, it is not
  grounded.
- **Skeleton test.** Remove the copy. The bare structure should still show what the
  section is and what matters most.

The recognisable defaults of generated design are named in AUDIT: `SLOP-01` to
`SLOP-03`, and the named looks and treatments in `SLOP-04` to `SLOP-21`, `TYPE-04`,
`TYPE-09`, `ANIM-06` and `IMG-06`. Each fails only where neither the
brief nor the existing system asks for it. Where the brief leaves an axis free, do not
spend that freedom on one of them.

### 3.4 Calibrate expression to the surface

- Operate and Read: expression lives in precise details (type tuning, spacing, state
  design, one accent). The tool should disappear into the task.
- Persuade and Experience: the direction may own the composition. Commit fully; a
  half-committed direction reads as noise.
- Either way, a dense tool must not become an airy marketing page, and an expressive
  portfolio must not become an admin panel.

### 3.5 The first viewport

- Open with the most characteristic thing in the subject's world, in the form that suits
  it: a headline, an image, a live demo, an interactive moment.
- On a Persuade surface, check that a newcomer can say what the product is, why they
  would care and how to proceed after a brief look. Check where the primary action
  falls at the supported sizes; reaching it should not depend on scrolling past
  decoration.
- Decide the headline's size, its length and the accompanying asset as one decision. A
  headline stacked into many short lines is a starting signal to revisit size or
  measure, not a fixed line limit.
- Where it can, let the page show the product working instead of describing it again.

## 4. Variants

Use when the user wants to see options, or when several directions are viable and the
choice is theirs.

- Produce two or three, built and viewable. Do not describe them.
- Each takes a different stance on one axis: density, emphasis (content, action or
  tool first), layout model, or aesthetic. Variants that differ only in color are one
  variant.
- Name each by its stance, not a number.
- For each, record: the principle behind it, the key choices, what it is strong at, what
  it is weak at, who it suits.
- Make each interactive enough to judge: the primary action responds, one state
  transition works, hover and focus are real.
- Open every variant in a browser and fix what is broken before showing it.
- Present them side by side with your recommendation and its reason. When the user
  chooses, consolidate into one direction and discard the rest.

Do not run a variant round for a fix, or for a feature inside an established system.

## Audit coverage

AUDIT items `SLOP-01` to `SLOP-03` (task displacement, identity, false structure), and
`SLOP-04` to `SLOP-21` for the named default looks and treatments. Related:
`HIER-03`, `NAV-02`, `CONTENT-03`.
