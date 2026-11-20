# Verification

Concern: rendered checks (widths, themes, states), reviewing your own and other people's
work, reporting, and how to run the `AUDIT.md` gate. The bad-practice checklist itself is
`AUDIT.md`; this file is the procedure around it.

## 1. Evidence

Code inspection, a successful build and a screenshot each answer a different question.
None replaces the others.

| Evidence | What it can show | What it cannot |
|---|---|---|
| Source | Tokens, semantics, state handling, hard-coded values | How it looks or feels |
| Build and tests | It compiles; tested behavior holds | Layout, hierarchy, taste |
| Screenshot | Layout, hierarchy, color, type at one moment | Timing, interaction, focus order |
| Live interaction | Flow, states, keyboard, feedback | Real-device performance |
| Recording or slow playback | Motion timing and continuity | |
| Measurement | Contrast, target size, load metrics | Whether the design is right |

### 1.1 Capture matrix

Capture what the change touches, at minimum:

- **Widths:** for responsive web, capture 375, 768 and 1280 CSS px, 320 CSS px for
  reflow, and relevant wide or breakpoint sizes (1440 or more, an intermediate width
  where the layout changes, the user's own viewport when known). For native and
  fixed-size work, capture the supported device classes, orientations or output sizes.
- **Themes:** every supported theme.
- **States:** populated, loading, empty, error, long content, and each interactive state
  that changed (hover, focus, open, selected, disabled, invalid).
- **Flow:** the primary task end to end, plus cancel and back.
- **Preferences:** reduced motion; 200 percent zoom; forced colors where relevant.
- **Native:** each shipped device class, from a simulator, emulator or device; dark
  appearance and a large text size.

### 1.2 Valid captures

- Let entrance animation settle, or disable it, before capturing. An element hidden by
  animation timing looks like a missing element.
- Capture full pages from the top. Wait for a real readiness signal, not a fixed delay.
- Open every capture and confirm it shows what its name claims: no blank regions, no
  half-loaded state, no wrong page.
- Name files by page, state, theme and width, and keep them where findings can cite
  them.
- Keep private data out of screenshots.
- Check the console for errors, failed requests, and missing fonts or images.

### 1.3 When you cannot render

If no browser, simulator or device is available, ask the user for screenshots at the
widths above, or review the source only and say so. State exactly which claims are
unverified. Do not describe the appearance of something you have not seen.

## 2. Self-review during a build

1. Build the whole thing to the plan.
2. Run one batched inspection: the capture matrix, the primary flow, the keyboard path.
3. Compare the render with the brief and with the plan from the direction step. Ask
   what a visitor would remember after one viewport, and whether that is what the plan
   intended.
4. List the findings, order them by section 4, and fix them in one batch.
5. Run one confirming inspection of what changed.
6. Run `AUDIT.md` and report (section 9).

Two inspection rounds is the ceiling for cosmetic polish. Open-ended self-polishing
costs time and tends to dilute a committed direction. A failed non-negotiable
(accessibility, truth, broken task) is outside that ceiling: fix it or disclose it as a
blocker.

Critique as you build, not only at the end. Before handoff, look once more and remove
one decoration that is not doing a job.

## 3. Reviewing someone else's work

A reviewer reports and does not fix, unless asked to.

1. **Read the brief** or the stated goal, and any design documentation. Without a brief,
   ask what the work is for, or state the goal you are assuming.
2. **Read what was built:** every component, page and style file created or changed.
   Note whether shared tokens and components were used, whether anything was duplicated,
   and whether new files follow the project's conventions.
3. **Gather evidence** per section 1.
4. **Form the design judgment first** (section 5), before running mechanical checks.
   Scan results anchor judgment, so the holistic read comes first. When independent
   reviewers are available, run the design read and the mechanical scan separately and
   combine them afterwards.
5. **Run `AUDIT.md`** against the evidence (section 9).
6. **Write the report** (section 6).

Where an independent gate is installed and the task calls for it (see
`the-visionaries` in the routing table in `SKILL.md`), self-review does not replace it.

## 4. Priority and severity

Judge and fix in this order:

1. **Task and truth.** Can the user complete the intended action? Is the content
   accurate?
2. **Accessibility and resilience.** Semantics, keyboard, focus, contrast, states,
   overflow, failure recovery.
3. **Composition.** Hierarchy, density, rhythm, alignment, responsive structure.
4. **Craft.** Typography, component consistency, imagery, motion quality.
5. **Engineering.** Readable code, cleanup, correct data boundaries, measured
   performance.

Severity uses the three levels `AUDIT.md` defines:

| Level | Meaning | Action |
|---|---|---|
| blocker | Prevents a task, excludes users, deceives, or loses data | Fix before handoff. No exception. |
| major | Causes real difficulty, confusion or a clearly generic result | Fix and retest, or record a justified brief-backed exception. Otherwise report blocked. |
| minor | Impairs clarity or craft with little task impact | Fix and retest, or record a justified brief-backed exception. Otherwise report blocked. |

When unsure between two levels, ask whether a user would contact support about it. If
yes, it is at least major.

## 5. The design read

Answer each with evidence: a screenshot, a selector or a file and line.

**Fit**

- Does the composition match the surface (operate, persuade, read, experience)?
- Is it grounded in this subject, or could an unrelated product use it unchanged?
- Does the implementation match the stated direction? Does anything break it: a stock
  component in a distinctive interface, a stray font, an out-of-palette color?
- Does the level of detail match the direction? A minimal design has no leftover
  decoration; a rich one has no empty, unfinished areas.

**Hierarchy and structure**

- Is the most important content the most prominent on each screen?
- Can you trace where the eye goes first, second, third?
- Are interactive elements findable without hunting?
- Is navigation clear, and is the current location shown?

**Consistency**

- Do spacing, color, radius, shadow and type sizes come from a shared set?
- Does one meaning always map to one color, and one role to one component?
- Were existing components reused or needlessly reimplemented?

**States and interaction**

- Does every interactive element have its states? Are loading, empty and error handled?
- Is there feedback for every action? Does motion match the direction and the frequency
  of use?

**Responsiveness**

- Does the layout recompose at each width, or only shrink?
- Is text readable, are targets large enough, and is anything cut off?

**Typography and copy**

- Is the font actually loading? Are measure, line height and scale deliberate?
- Is every string clear, specific and consistent in terminology?

**Themes**

- Is each theme designed, with tokens applied throughout and contrast holding?

**Stress**

- Walk the flow as: a rushed expert using only the keyboard; a first-time visitor who
  does not know the vocabulary; a keyboard and screen-reader user; someone on a phone,
  interrupted mid-task; someone entering the longest, oddest input. Note where each
  stalls.

Use the usability heuristics in `interaction.md` section 6 and the cognitive
load checks in `accessibility.md` section 8 as further prompts.

## 6. The report

For the final gate, use the report format `AUDIT.md` specifies. For a full review, wrap
that audit result in this structure:

```markdown
# Design review: [target]

Reviewed against: [brief or stated goal]
Evidence: [widths, themes, states, tools; list of capture files]
Not verified: [what could not be checked, and why]

## Summary
[Two or three sentences: overall quality and the most important finding.]

## Findings
[Ordered blocker, major, minor. Each: what, where (file:line or capture), why it
matters, and the fix direction. Cite the AUDIT item ID where one applies.]

## Audit result
[The AUDIT.md report.]

## What works
[The strongest parts, specifically. This tells the author what to keep.]

## Open questions
[Decisions that belong to the user.]
```

Rules for the report:

- Every finding cites evidence. No finding rests on "it feels".
- Separate observed fact from heuristic judgment, and do not present a heuristic as user
  research.
- Do not fold a deliberate product choice into the defects; raise it as a question.
- Do not report a count or a score as a pass while a blocker is open.
- State what the review did not cover. A partial review is labelled partial.

## 7. Performance as experienced

Check when the change affects loading, images, fonts or animation. Use the performance
specialist skills in the routing table for diagnosis.

| Measure | Target |
|---|---|
| Largest Contentful Paint | 2.5 s or less |
| Interaction to Next Paint | 200 ms or less |
| Cumulative Layout Shift | 0.1 or less |

These are the "good" thresholds at the 75th percentile of field visits, segmented by
device class. A single lab trace is diagnostic: it can locate a problem, not prove the
field result.

- The largest above-the-fold element loads with priority and is not lazy-loaded.
- Space is reserved for images, embeds and fonts, so content does not jump.
- Heavy code and media below the fold load on demand.
- Report measured numbers only. Emulation is not a real device; say which you used.

## 8. Finishing

- Review the source diff: remove accidental churn, debug output, orphaned styles and
  temporary files.
- Keep any dev server you started available for the user, or stop it; say which.
- Hand off with the structure in `SKILL.md` section 7.

## 9. Running the AUDIT gate

`AUDIT.md` is the checklist of bad behaviors that must not appear in finished work. It
defines its own procedure, severities and report format; where this section and
`AUDIT.md` differ, `AUDIT.md` wins.

1. **When.** After the last change, before every handoff, including a small fix. On a
   redesign, also once against the baseline before changing anything.
2. **Against what.** The rendered result at the widths, themes and states of section 1,
   plus the code. A source search finds candidates; confirm each one in the render.
   For a check whose defect is a component's public contract (a state the interface
   cannot express, an option combination), a consumer fixture and the source are the
   evidence; a screenshot cannot prove that a state is unrepresentable.
3. **Scope.** Report every item ID. Mark an item not applicable only with a reason. An
   item you could not check is unverified, never passed.
4. **Each hit.** An author fixes it and repeats the check that found it. A reviewer
   records the open failure, its evidence and a fix direction, and repairs only when
   authorized. The audit is mandatory in both cases. The concern file for the item's
   prefix (`ANIM-` is `animation.md`, `TOKEN-` is `tokens.md`, `NATIVE-` is
   `native-platforms.md`) holds the positive guidance. For the cross-cutting prefixes
   use `discovery.md` section 3 for `SLOP-`, section 7 of this file for `PERF-`, and
   `interaction.md`, `content.md` or `tokens.md` for `DARK-` according to the failed
   check.
5. **Exceptions.** A hit may stand only as a deliberate choice backed by a specific
   requirement in the brief. Record the requirement and the trade-off, and keep the
   finding visible in the report. A blocker can never be excepted. A hit with neither a
   verified fix nor a valid exception means the handoff is reported blocked, whatever
   its severity.
6. **Report** in the format `AUDIT.md` specifies, with its overall status. Do not
   summarize the result as clean while any blocker or unverified item remains.

## Audit coverage

This file is the procedure for running all of `AUDIT.md`. Section 7 corresponds to
`PERF-01` to `PERF-03`, and to `PERF-04` to `PERF-06`.
