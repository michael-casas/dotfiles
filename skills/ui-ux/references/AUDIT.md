# UI/UX handoff audit

Run before handing off a build, redesign or review. Record the revision, changed views, brief, audience, primary task and supported platforms.

1. Inspect the rendered result at compact, intermediate and wide supported widths, particularly around layout transitions. Cover each supported theme. Exercise the primary task, cancellation and recovery with realistic data. Include populated, empty, loading, error, disabled, focus and overflow states where reachable.
2. Use screenshots for composition, measured properties for contrast and dimensions, and runtime observation for input, motion and announcements. Inspect the implementation behind each result. A source search identifies candidates. Confirm the effect in the task or, for component contracts, in a representative consumer or isolated fixture.
3. Each checkbox marks a check performed. A hit means the bad behavior is present. Authors fix and retest. Reviewers record evidence and a fix direction when repairs fall outside their scope. A blocker prevents handoff, a major impairs a task or its meaning, and a minor impairs clarity or craft.
4. A non-blocker may have a justified exception only for a deliberate choice backed by a specific brief requirement. Record the requirement, affected task and trade-off. Keep the finding visible as a fail. Blockers cannot receive exceptions. Exclusions built into a criterion determine applicability.

A **default tell** fails where neither the brief nor the existing system asks for the pattern. It can never be a blocker. In the report, name the pattern and the brief or system evidence checked. Waive a hit only through a specific brief-backed exception recorded as a fail. Numerical craft triggers prompt inspection. A trigger alone does not establish a failure.

## Report

State the revision and evidence matrix once. Report every ID. Use **pass** for a verified absence or verified repair, **fail** for an observed hit, and **n.a.** with a reason when the item cannot apply. When evidence is unavailable, leave the result pending and name the missing test. Interactivity promised by the deliverable requires runtime evidence.

| Item ID | Result (pass / fail / n.a.) | Evidence | Fix and retest, or justified exception |
| --- | --- | --- | --- |
| INTER-02 | pass | Saved items, compact dark view. A 2 s delayed request showed loading until a successful zero-row response. | Previously flashed “No items”. Separated pending and empty states and repeated the delayed request. |

Report **ready** only when each applicable item has evidence and every hit has a verified fix or a justified non-blocker exception. List accepted exceptions by ID. Report **blocked** for unresolved failures or **incomplete** for outstanding verification.

## Generic design defaults

- [ ] **SLOP-01** · major · A two-button marketing hero, KPI strip or promotional carousel forces users past a screen of promotion before the first dashboard or settings task.
  - Detect — Name the first task from the brief. On the entry screen, trace what the user must pass before reaching it, including promotional onboarding.
  - Fix — Lead with the relevant action, data or subject.
- [ ] **SLOP-02** · minor · A supplied brand face, palette or logo treatment disappears behind the stock theme on a view that requires that identity.
  - Detect — Compare required identity assets and tokens with the rendered view. Name the missing cue and the stock value that replaced it.
  - Fix — Carry a recognizable feature of the subject into type, palette or composition.
- [ ] **SLOP-03** · minor · A badge or icon tile announces a status the record does not have, such as a “verified” shield on every profile.
  - Detect — Compare each badge with the record or action it describes. Identify the unsupported status.
  - Fix — Remove redundant markers or bind them to an actual distinction.
- [ ] **SLOP-04** · minor · *(default tell)* A purple-to-blue or indigo-to-violet gradient is used as the hero background, the button fill or a glow, where neither the brief nor the existing system asks for it.
  - Detect — Search gradient declarations and accent tokens. Compare the rendered hero, buttons and glows with the brief and approved palette.
  - Fix — Choose the hue and treatment from the project direction.
- [ ] **SLOP-05** · minor · *(default tell)* A cream ground, high-contrast serif headline and clay-colored accent appear together where neither the brief nor the existing system asks for it.
  - Detect — Read the background, display-face and accent tokens. Look for off-white hexes in the `#F4F1EA` to `#FBF8F1` family with a serif heading and an accent near `#D97757` or `#B6553A`.
  - Fix — Rework whichever of ground, face or accent was not chosen for this subject.
- [ ] **SLOP-06** · minor · *(default tell)* A near-black ground carries one neon or acid accent with glowing shadows or edges, where neither the brief nor the existing system asks for it.
  - Detect — Grep colored `box-shadow` with zero offset and large blur, `drop-shadow`, and neon accent tokens on `#0B0B0B` or `#111` grounds.
  - Fix — Choose light or dark from the scene of use; give depth with an offset shadow or tonal steps.
- [ ] **SLOP-07** · minor · *(default tell)* A broadsheet costume (hairline rules everywhere, zero radius, dense newspaper columns, small tracked mono labels) is applied to a subject that is not editorial, where neither the brief nor the existing system asks for it.
  - Detect — Screenshot check: count full-width hairlines and mono micro-labels per viewport and compare with the subject.
  - Fix — Keep a rule or a column only where it organizes real content.
- [ ] **SLOP-08** · minor · *(default tell)* The page structure is a row of three (or more) equal cards, each an icon tile above a title and two lines of text, where neither the brief nor the existing system asks for it.
  - Detect — Screenshot check for same-size cards with a rounded-square icon on top. Grep `grid-cols-3` or a three-track grid whose children share one template.
  - Fix — Order the content by importance and give the leading item more room; use a card only for a real group, comparison or selection.
- [ ] **SLOP-09** · minor · *(default tell)* The hero or a section is the metric template (a big number, a small label, supporting stats, a gradient accent) or a row of identical stat columns, where neither the brief nor the existing system asks for it.
  - Detect — Screenshot check for oversized numerals with captions. Trace each number to supplied data; an untraceable number is also `CONTENT-03`.
  - Fix — Open with the most characteristic thing in the subject's world; show a number only with its source and comparison.
- [ ] **SLOP-10** · minor · *(default tell)* A tracked ALL-CAPS micro-label sits above every section heading, or a pill chip (for example "BETA", "v2.0", "New") sits above the hero headline, where neither the brief nor the existing system asks for it.
  - Detect — Grep `uppercase` with `tracking-` or `letter-spacing` on small text directly before a heading. Count labels against sections.
  - Fix — Delete the label unless it adds information the heading lacks.
- [ ] **SLOP-11** · minor · *(default tell)* Sections or cards carry numbering ("01 / 02 / 03", "001 · Capabilities", "Step 1", "SECTION 01") though the content is not a sequence, where neither the brief nor the existing system asks for it.
  - Detect — Grep `\b0[1-9]\b\s*[/·.—-]` and `(Step|Stage|Phase|Section)\s*0?\d`. Ask whether reordering the items would change their meaning.
  - Fix — Remove the numbers, or keep them only for a real process or timeline.
- [ ] **SLOP-12** · minor · *(default tell)* Template chrome strings appear regardless of subject: meta strings joined by middle dots ("A · B · C"), labels built as "WORD — fragment", a "→" appended to links and buttons, or a colored status dot before items that have no status, where neither the brief nor the existing system asks for it.
  - Detect — In labels, metadata rows, buttons and links (not body prose), grep ` · `, ` — ` and `→`, and look for small rounded dot elements. Check that each dot reports a real state.
  - Fix — Write the label plainly and drop the ornament.
- [ ] **SLOP-13** · minor · *(default tell)* One word or phrase of a headline is set in italic, bold, a second color, a second family or gradient fill, or the whole headline is gradient-filled text, where neither the brief nor the existing system asks for it.
  - Detect — Grep `background-clip:\s*text|bg-clip-text` and `<em>|<i>|<span` inside `h1`–`h3`. Ask whether that word is the point of the sentence.
  - Fix — Set the headline in one treatment; carry emphasis by wording, size or weight.
- [ ] **SLOP-14** · minor · *(default tell)* Every block is the same card: one radius on everything, the same soft grey shadow (`rgba(0,0,0,.1)`), a 1 px grey border plus a wide soft shadow on a white fill, where neither the brief nor the existing system asks for it.
  - Detect — Grep `shadow-(sm|md|lg)|rgba\(0,\s*0,\s*0,\s*0?\.1\)` and `border` plus `shadow` on the same element. Count distinct radius and shadow values against component roles.
  - Fix — Declare elevation once per element and vary treatment by role; group with space where a card adds nothing.
- [ ] **SLOP-15** · minor · *(default tell)* Cards, callouts or list items carry a colored side stripe (`border-left` or `border-right` wider than 1 px) as decoration, where neither the brief nor the existing system asks for it.
  - Detect — Grep `border-(l|r)-[2-9]|border-left:\s*[2-9]px|border-inline-start:\s*[2-9]px`. Check whether the stripe's color encodes a status.
  - Fix — Remove the stripe, or bind its color to a real state and add a second cue.
- [ ] **SLOP-16** · minor · *(default tell)* Glass panels (`backdrop-filter` blur), floating gradient blobs or radial glow halos are used as decoration with no depth system behind them, where neither the brief nor the existing system asks for it.
  - Detect — Grep `backdrop-filter|backdrop-blur|radial-gradient|blur-(2xl|3xl)`. For each hit, name what it separates or focuses.
  - Fix — Remove the effect, or keep one where it carries a real layer relationship.
- [ ] **SLOP-17** · minor · *(default tell)* Everything is centered: a centered hero over a dark mesh, then centered heading, centered paragraph and centered cards in every section, where neither the brief nor the existing system asks for it.
  - Detect — Grep `text-center|text-align:\s*center` per section. Screenshot check: one vertical axis through the whole page.
  - Fix — Choose the alignment in the plan and hold body text to a readable edge.
- [ ] **SLOP-18** · minor · *(default tell)* Decorative micro-interface fills space: fake system markers and version footers ("v1.4.2", "last sync 4s ago"), locale or weather strips, "Scroll ↓" cues, pills overlaid on images, invented photo-credit captions, or a strip of spaced words ("DESIGN · BUILD · SHIP"), where neither the brief nor the existing system asks for it.
  - Detect — Read every string under about 12 px. Ask what a user does with it; a hit has no answer.
  - Fix — Delete it, or replace it with information the user needs.
- [ ] **SLOP-19** · minor · *(default tell)* The background carries decorative overlays (repeating-gradient stripes, a two-axis grid, crosshairs, noise) unrelated to the subject, where neither the brief nor the existing system asks for it.
  - Detect — Grep `repeating-linear-gradient|feTurbulence|background-image:.*linear-gradient.*linear-gradient|bg-grid`.
  - Fix — Use a plain surface, or a texture taken from the subject's world.
- [ ] **SLOP-20** · minor · *(default tell)* A component library ships in its untouched default theme (default radius, default neutral ramp, default font, default shadows), where neither the brief nor the existing system asks for it.
  - Detect — Compare the shipped tokens with the library defaults and the brief. Identify which stock choices lack support in the project direction.
  - Fix — Set the library's radius, color, type and shadow tokens to the project's direction.
- [ ] **SLOP-21** · minor · *(default tell)* One section layout repeats down the page: three or more consecutive image-left / text-right rows alternating sides, or the same card row section after section, where neither the brief nor the existing system asks for it.
  - Detect — Full-page screenshot. Label each section's layout family and look for three in a row.
  - Fix — Repeat a layout only where the content is truly parallel; otherwise compose each section for its own content.

## Hierarchy

- [ ] **HIER-01** · major · Heading and body share one size and weight, or labels and values share identical styling and alignment, leaving the reader unable to pair them.
  - Detect — Read a populated section and pair each label with its value. Compare computed size, weight and spacing where the pairing is ambiguous.
  - Fix — Differentiate roles with scale, weight, alignment or spacing.
- [ ] **HIER-02** · major · Equal row and section gaps, a heading nearer the preceding block, or borders around every cell make a label or action appear to belong to the wrong group.
  - Detect — Measure the space within and between groups, then trace the heading, values and actions that readers would pair.
  - Fix — Group related elements together and remove boundaries that misrepresent ownership.
- [ ] **HIER-03** · major · A promotional banner or bright secondary button draws attention away from a required warning at the point of decision.
  - Detect — Identify the decision and its prerequisite from the brief. Trace the first visible cues with representative data at two widths. Record the competing element and the warning or action it obscures.
  - Fix — Place the decision and its prerequisite together and reduce competing emphasis.
- [ ] **HIER-04** · major · Two or more primary-styled buttons compete inside one decision context.
  - Detect — Screenshot each view and count filled, accent-colored buttons per card, form or toolbar. Grep the primary variant per view.
  - Fix — Keep one primary and demote the others to secondary or text style. Where the interface must not steer the choice (consent, refusal, cancellation), give the options comparable weight instead; see `DARK-02`.
- [ ] **HIER-05** · minor · *(default tell)* An oversized headline (review trigger: above about 6rem, or four or more lines at 1280 px) sits over small, low-contrast supporting text, where neither the brief nor the existing system asks for it.
  - Detect — Measure the computed `font-size` of `h1` and its line count at 1280 and 375 px; compare with the subcopy's size and contrast.
  - Fix — Plan headline size with its length; raise the supporting text until it reads.
- [ ] **HIER-06** · major · A metric lacks the unit, time period or comparison needed to interpret it, or equally prominent dashboard tiles bury the signal that requires action.
  - Detect — For each large numeral ask "of what, since when, compared with what". Screenshot check: no tile is larger or first for a reason.
  - Fix — Add the missing context beside the number and lead with what changed or needs action.

## Layout and responsiveness

- [ ] **LAYOUT-01** · minor · A blank value shifts a comparison to the wrong row, or misaligned numbers obscure which record or unit they describe.
  - Detect — Compare two real records or plans with different title lengths, missing values and changing digits. Trace each label across both columns.
  - Fix — Align corresponding fields and show missing values explicitly.
- [ ] **LAYOUT-02** · major · A dropdown or popover is clipped by an `overflow: hidden` or scrolling ancestor, a tooltip runs off the viewport edge, a menu opens underneath a sticky header or dialog, or an overlay stays anchored to the wrong control after scroll or resize.
  - Detect — Open the last menu or tooltip near each viewport edge. Scroll its container, resize and zoom with it open. Check both visible bounds and hit testing.
  - Fix — Reposition or constrain the overlay within the available space and correct stacking.
- [ ] **LAYOUT-03** · blocker · Essential content or controls become unreachable when the view narrows or text grows.
  - Detect — For web, test 320 CSS px width and 200% text resizing separately. Follow the task without two-axis page scrolling. Isolate intrinsically two-dimensional content such as maps or comparison grids. On native, test compact windows and supported large text settings. Check fixed-size native labels at the largest text setting.
  - Fix — Reflow groups, allow wrapping and keep required actions reachable.
- [ ] **LAYOUT-04** · major · A fixed top margin puts content under the notch, or the keyboard hides the focused input or submit action.
  - Detect — Focus the last field, rotate and submit with the keyboard visible. Collapse and expand browser chrome and check safe areas on devices that have them. Inspect fixed top margins on a device with a cutout.
  - Fix — Use available viewport and inset measurements and scroll focused controls into reach.
- [ ] **LAYOUT-05** · major · Fixed-size buttons, nowrap labels or physical left/right positioning clip translated values, hide their distinguishing text or reverse an RTL task sequence.
  - Detect — Try long names, unbroken identifiers, translated labels and RTL where supported. Compare visual, reading and focus order, including truncation and recovery of full values.
  - Fix — Use flexible sizing, logical alignment and access to the complete value.
- [ ] **LAYOUT-06** · major · A full-height section uses `height: 100vh` (or `h-screen`), so its content or call to action is cut off or jumps under mobile browser chrome.
  - Detect — Grep `100vh|h-screen`. On a phone or emulated mobile browser, scroll so the address bar collapses and expands and watch the section's bottom edge.
  - Fix — Use `min-height` with `svh` or `dvh` for the intended behavior and let content grow.
- [ ] **LAYOUT-07** · major · `overflow-x: hidden` on the page, body or main wrapper masks a child that overflows horizontally, or the page scrolls sideways at 375 px.
  - Detect — Grep `overflow-x:\s*hidden|overflow-x-hidden|overflow:\s*hidden` on root wrappers. Remove it and compare `scrollWidth` with `clientWidth` at 320 and 375 px.
  - Fix — Fix the overflowing child at its source.
- [ ] **LAYOUT-08** · minor · *(default tell)* A card is nested in a card nested in a card, or every section sits inside its own giant rounded wrapper, where neither the brief nor the existing system asks for it.
  - Detect — Inspect the DOM for three or more nested elements that each have a border, background or shadow. Screenshot check for boxes inside boxes.
  - Fix — Keep one framing level per region and group the rest with spacing.
- [ ] **LAYOUT-09** · minor · At narrow widths body text touches the viewport edge, or a full-width text block stretches across a wide screen until adjacent groups lose their visual separation.
  - Detect — Compare gutters and grouping at the narrowest and widest supported widths. Check prose return sweeps under TYPE-02.
  - Fix — Add a page-level maximum width and a minimum side gutter.
- [ ] **LAYOUT-10** · major · The desktop layout is shrunk, not recomposed: multi-column content squeezed into slivers at 375 px, a table cut off with no scroll region, or a side-by-side form that no longer fits.
  - Detect — On responsive web, capture at 375 and 768 px. Look for columns under about 120 px wide, clipped tables and two-axis scrolling.
  - Fix — Stack in priority order, give wide data its own scroll region or a detail view.
- [ ] **LAYOUT-11** · minor · Parallel elements do not line up: buttons at different heights across a row of cards, feature lists starting at different vertical positions in pricing columns, or icons visibly off-center beside text.
  - Detect — Screenshot a row of sibling cards with unequal content and draw a horizontal line through the buttons and through the list tops.
  - Fix — Pin actions to the card bottom and align shared rows across siblings.

## Typography

- [ ] **TYPE-02** · minor · The reading column expands until readers lose their place between lines.
  - Detect — At the widest supported size, count characters in representative prose. Investigate sustained lines over 80 characters and verify the return sweep in the actual script and face.
  - Fix — Constrain the prose measure independently of adjacent media.
- [ ] **TYPE-03** · major · Letterforms collide, lines overlap or a headline breaks inside a word that fits at a usable size.
  - Detect — Inspect accented capitals and descenders with real and fallback faces. Test fixed heading heights, line-height near 1, negative tracking, break-all and narrow unhyphenated columns. Fail on clipping, overlap or broken words.
  - Fix — Adjust measure, tracking, line height or wrapping for the actual text.
- [ ] **TYPE-04** · minor · *(default tell)* The browser default, `system-ui`, or a ubiquitous neutral sans (for example Inter or Roboto) is the only typeface on a surface meant to carry a distinctive voice, with no reason recorded, where neither the brief nor the existing system asks for it.
  - Detect — Read the computed `font-family` of headings and body. Check the plan for a stated reason. Not a hit on product UI, an accessibility-first service, or where the system mandates the face.
  - Fix — Choose a face for this subject and state why, or record the reason the neutral face is right.
- [ ] **TYPE-05** · major · Small body text, labels or inputs become unreadable at the supported viewing distance, or focusing a small iOS web input zooms the form and hides its context.
  - Detect — At a supported phone width, inspect small text in context and focus the smallest input. Investigate body text below 16 CSS px and labels below 12 CSS px. Confirm a reading or focus failure.
  - Fix — Raise the size; cut or disclose content before shrinking text.
- [ ] **TYPE-06** · minor · *(default tell)* Running text is set in all caps, with wide letter-spacing, or fully justified without hyphenation, where neither the brief nor the existing system asks for it.
  - Detect — Grep `uppercase|text-transform:\s*uppercase|text-align:\s*justify|tracking-(wide|wider|widest)` on elements holding more than one line of prose.
  - Fix — Use casing, spacing and start alignment suited to the script and reading task.
- [ ] **TYPE-07** · minor · *(default tell)* The page uses three or more type families, or one-off font sizes outside any scale, where neither the brief nor the existing system asks for it.
  - Detect — List distinct computed `font-family` and `font-size` values on the page. Review trigger: more than two families, or sizes that match no token.
  - Fix — Assign a role to each family and size and consolidate unexplained variations.
- [ ] **TYPE-08** · major · The chosen font does not load or loads badly: text is invisible while it loads, the fallback swap moves the layout, or a missing weight renders as synthetic bold or italic.
  - Detect — Reload with the network throttled and with the font request blocked. Check the Network panel for 404s and compare requested weights with those used.
  - Fix — Load the weights used, set a fallback with close metrics and a non-blocking display strategy.
- [ ] **TYPE-09** · minor · *(default tell)* A monospace face is used for labels and body to look "technical", or a display face is used for buttons, labels and data, where neither the brief nor the existing system asks for it.
  - Detect — Read `font-family` on labels, buttons, table cells and body. A mono face outside code, aligned data or measurement is a candidate.
  - Fix — Keep mono for code and aligned data and the display face for display roles.
- [ ] **TYPE-11** · major · Text that carries meaning is baked into a raster image (a headline, a button label, a table screenshot) where live text could be used.
  - Detect — Inspect raster headings, controls and tables for text that can be represented as live text. Allow essential presentation such as logos and user-customizable presentation.
  - Fix — Set the text as live text over the image.

## Color and contrast

- [ ] **COLOR-01** · blocker · Helper text in light grey, white labels on pale buttons, or text over a photograph falls below the applicable contrast ratio.
  - Detect — Measure the worst composited background in every state and theme, including placeholders. On web require 4.5:1 for normal text or 3:1 from 18 pt regular or 14 pt bold. Exclude logos, incidental text and inactive controls as applicable.
  - Fix — Change foreground, backing surface or image treatment and remeasure.
- [ ] **COLOR-02** · blocker · A necessary control boundary, state indicator or graphical detail disappears into its surroundings.
  - Detect — Measure necessary non-text cues against adjacent colors. On web require 3:1 where WCAG 1.4.11 applies. Check selected, focused and error states. Exclude inactive and unmodified user-agent controls.
  - Fix — Increase contrast or add a sufficiently contrasting shape or mark.
- [ ] **COLOR-03** · major · Links in running text differ from it by color alone, a required or invalid field is marked only in red, status is a red or green dot with no label, or chart series are told apart only by hue.
  - Detect — Inspect links, status, validation and charts without hue. Try to identify each state or series from text, shape or pattern.
  - Fix — Add a persistent non-color cue.
- [ ] **COLOR-04** · major · Switching theme leaves text unreadable, necessary borders invisible or a logo stranded on an unintended opaque tile.
  - Detect — Switch every supported theme and capture the same screens and states. Grep hard-coded `#fff|#000|white|black` in components.
  - Fix — Set surfaces, text, borders and elevation for each theme from tokens and re-measure contrast.
- [ ] **COLOR-05** · minor · Dividers, headings and backgrounds share the action accent so densely that the primary action blends into decoration.
  - Detect — Count uses of the accent token per view and how many are interactive. Compare the accent hue across sections.
  - Fix — Restore a distinct action treatment and reduce emphasis on competing decoration.
- [ ] **COLOR-06** · major · Error and success use the same color and lack a distinguishing label or symbol, or an ordinary brand badge is indistinguishable from a warning.
  - Detect — List each status token and every place its hue appears. Trigger an error next to a brand-colored element and compare.
  - Fix — Differentiate states with labels and distinguishable visual cues.
- [ ] **COLOR-07** · minor · State or boundaries shown only by background color or box-shadow disappear in forced-colors (high-contrast) mode.
  - Detect — Emulate `forced-colors: active`. Check selected, focused and checked states and control edges.
  - Fix — Add a border, outline or icon that survives forced colors.

## Interaction and forms

- [ ] **INTER-01** · major · A placeholder link or empty handler activates without effect, a submitted form gives no feedback, or a disabled button hides its prerequisite.
  - Detect — Find placeholder hrefs and empty handlers. Activate controls with valid and incomplete data and check the response or prerequisite.
  - Fix — Wire the action and expose the current state or missing prerequisite.
- [ ] **INTER-02** · major · “No items” flashes before the first response, a failed request looks empty, or a filtered zero-result list incorrectly invites first-time setup.
  - Detect — Delay the first response, return zero records, filter out all matches, deny access and fail a refresh. Check the message and available next step in each case.
  - Fix — Represent each outcome separately, with setup, reset, retry or permission guidance as applicable.
- [ ] **INTER-03** · blocker · Repeated activation creates duplicate consequential operations, or the UI confirms an operation that failed.
  - Detect — Delay and reject a save or payment in a test fixture. Activate twice, then reload and compare the displayed outcome with the authoritative record.
  - Fix — Guard pending operations, enforce safe retries and reconcile failed optimistic changes.
- [ ] **INTER-04** · major · Routine reversible actions interrupt the task with a blocking acknowledgment.
  - Detect — Perform several ordinary edits. Count dismissals required solely to acknowledge success or confirm changes already recoverable through undo.
  - Fix — Update the affected view and provide undo or unobtrusive confirmation.
- [ ] **INTER-05** · major · Out-of-order responses restore an obsolete selection or show results for the wrong query.
  - Detect — Delay request A, change the query to B, then resolve A last. Compare the visible rows, filter label and active selection.
  - Fix — Discard stale results or bind each response to its originating view state.
- [ ] **INTER-06** · major · A placeholder is the only field label, or the visible label names a different input in the accessibility tree.
  - Detect — Fill every field, inspect its accessible name and activate its visible label. Check format, unit and required status before submission.
  - Fix — Associate a persistent visible label and relevant instructions with the control.
- [ ] **INTER-07** · major · Validation leaves the user guessing which field failed or how to correct it.
  - Detect — Submit an invalid value alongside valid values. Locate the error visually and by screen reader. Correct it and verify that the error clears and valid entries survive.
  - Fix — Associate specific recovery instructions with the field and retain valid input.
- [ ] **INTER-08** · major · The form forces users to retype or memorize information they can safely reuse.
  - Detect — Try pasting a password, using autofill and completing a later step with information already supplied. Check for a genuine security, validity or essential-task exception.
  - Fix — Permit password managers and paste. Prepopulate eligible values or offer selection.
- [ ] **INTER-09** · major · An error, a validation message or a routine confirmation is delivered through the browser's `alert()`, `confirm()` or `prompt()`, away from the input or view the user must act on.
  - Detect — Grep `\b(window\.)?(alert|confirm|prompt)\(`. Trigger each error path and watch for a native dialog.
  - Fix — Show the message inline beside its cause, or in the project's dialog component.
- [ ] **INTER-10** · major · A data view was built only for the populated case: while loading, when empty or on failure it shows a blank area, an endless spinner, or raw values such as `undefined`, `NaN`, `null` or `[object Object]`.
  - Detect — Delay the request, return zero rows and fail it. Grep rendered output for `undefined|NaN|\[object Object\]`.
  - Fix — Design the loading, empty and error state for the view.
- [ ] **INTER-11** · major · A disabled control looks active, a selection looks unselected, or pressing a control gives no visible response during an observable delay.
  - Detect — Hover, press, tab to and disable each control type and capture each. Grep the component for `:hover`, `:active`, `:focus-visible`, `:disabled`.
  - Fix — Define each state the control can be in.
- [ ] **INTER-12** · minor · Validation fires too early or destroys work: a field is marked invalid while the first value is still being typed, or a failed submit clears the form.
  - Detect — Type one character into an email field and watch for an error. Submit with one invalid field and check the others.
  - Fix — Validate on blur or submit, clear an error when fixed, keep all input on failure.
- [ ] **INTER-13** · minor · Inputs use the wrong type: email, phone, number, date or password collected in a plain text field, with no `autocomplete` token, so the wrong keyboard appears and autofill fails.
  - Detect — Grep `<input` and list `type`, `inputmode` and `autocomplete`. Focus each on a phone.
  - Fix — Set the matching `type`, `inputmode` and `autocomplete`.
- [ ] **INTER-14** · minor · *(default tell)* A modal dialog is used for a task that needs neither interruption nor protected focus (simple edits, navigation, routine forms), or modals open on top of modals, where neither the brief nor the existing system asks for it.
  - Detect — List each dialog and what triggers it. Ask whether the page behind must be blocked.
  - Fix — Use inline editing, disclosure, a side panel or a page.
- [ ] **INTER-15** · major · An error the user must act on is shown only in a toast that disappears, or a generic failure toast replaces field-level errors.
  - Detect — Trigger a validation and a server error. Check whether the message persists and sits by its cause after the toast closes.
  - Fix — Keep actionable errors inline and persistent; use toasts for outcomes needing no action.
- [ ] **INTER-16** · minor · A full-screen spinner replaces the whole view between every state, or existing content is wiped while it refreshes.
  - Detect — Trigger a refresh and a pagination load on a populated view and record what remains visible.
  - Fix — Keep prior content during refresh and scope the indicator to the part that is loading.

## Content and copy

- [ ] **CONTENT-01** · major · “Delete” archives a record, or the same action changes from “Remove member” to “Delete account” at confirmation.
  - Detect — Read the control, confirmation and resulting status together. Predict the object, scope and effect before activating it, then compare with the actual result.
  - Fix — Use a specific verb and consistent object name throughout the flow.
- [ ] **CONTENT-02** · minor · A subtitle repeats its heading or an internal table name, enum or error code replaces an explanation users need.
  - Detect — Read the affected screen as a first-time user. Identify copy that repeats the heading or offers no usable distinction between options.
  - Fix — Replace it with concrete user language or remove it.
- [ ] **CONTENT-03** · major · A testimonial, customer logo, star rating, uptime figure or sample chart is presented as product evidence without an approved source or visible sample label.
  - Detect — Trace visible claims to supplied data or approved content. Inspect mock charts and testimonials for clear sample labeling.
  - Fix — Supply verified content, label the example at the point of use or remove the claim.
- [ ] **CONTENT-04** · major · Placeholder content ships: lorem ipsum, "John Doe" / "Jane Smith", "Acme Corp", "Your text here", "TODO", "example.com" addresses.
  - Detect — Grep rendered strings and content files for `(?i)lorem ipsum|john doe|jane (doe|smith)|acme|your (text|title) here|example\.com`. Search visible text, not source comments, for `TODO` and `placeholder`.
  - Fix — Replace placeholders in production. Label intentional examples wherever readers could take them for real content.
- [ ] **CONTENT-05** · major · An error says nothing usable: "Oops! Something went wrong", "An error occurred", "Invalid input", or a raw status code or stack trace as the message.
  - Detect — Grep `(?i)oops|something went wrong|an? error (has )?occurred|invalid input|error:? \d{3}`. Trigger each failure and read the message.
  - Fix — Say what failed, why if known, and what to do next.
- [ ] **CONTENT-06** · minor · Buttons and links do not name their outcome: "Submit", "OK", "Click here", "Learn more" repeated with no object, or "Yes" / "No" on a confirmation.
  - Detect — Grep `>(Submit|OK|Okay|Click here|Learn more|Read more|Yes|No)<`. Read each label out of context.
  - Fix — Use a verb plus object ("Save changes", "Delete project").
- [ ] **CONTENT-07** · minor · *(default tell)* Copy uses the stock vocabulary of generated marketing: "Elevate", "Seamless", "Unleash", "Unlock the power of", "Next-gen", "Revolutionize", "Game-changer", "Supercharge", "Transform your", "In today's fast-paced world", where neither the brief nor the existing system asks for it.
  - Detect — Grep `(?i)elevate|seamless|unleash|unlock (the|your)|next-gen|revolutioni[sz]e|game-chang|supercharge|transform your|fast-paced world|cutting-edge`.
  - Fix — Say what the product does, for whom, with what proof.
- [ ] **CONTENT-08** · major · An empty state is a dead end: "No data", "Nothing here" or a blank panel, with no explanation and no next action.
  - Detect — Open each list, search and dashboard with zero records and with filters that match nothing.
  - Fix — Say what will appear and give the action that starts it, or the way to clear the filters.
- [ ] **CONTENT-09** · minor · *(default tell)* Copy performs instead of informing: craft-flavored labels ("Field notes", "Quietly trusted by"), aphoristic "Not X. Just Y." cadence, a sentence under a heading that only restates it, or exclamation marks on routine success, where neither the brief nor the existing system asks for it.
  - Detect — Read each heading with its first sentence. Grep visible strings for `(?i)quietly|field notes|not .{1,30}\. just ` and for success messages ending in `!`.
  - Fix — Use a plain functional label and delete the restating sentence.
- [ ] **CONTENT-10** · minor · Strings are assembled by hand: "1 items", "item(s)", a hard-coded date or currency format, or a sentence concatenated from fragments.
  - Detect — Render counts of 0, 1 and 2. Grep `\(s\)` and template strings joining text with a count. Switch locale where supported.
  - Fix — Use the platform's plural, date and number formatters and whole-sentence messages.

## Accessibility

- [ ] **A11Y-01** · blocker · Row actions appear only on hover, a menu opens only on hover, a list can be reordered only by dragging, or a slider, map or canvas has no keyboard or single-tap equivalent for a required task.
  - Detect — Complete the flow by keyboard alone, then with taps without dragging. Check menus, charts and reorder controls. For path-dependent tasks, document when the gesture is essential.
  - Fix — Provide equivalent controls with expected activation keys and single-pointer alternatives.
- [ ] **A11Y-02** · blocker · Focus escapes behind an open modal, cannot leave a closed overlay, or lands behind sticky chrome that completely covers the focused control.
  - Detect — Tab forward and backward while opening, using and dismissing overlays. Include sticky chrome at zoom and verify the focused component is not entirely obscured. Check visible focus, background inactivity, a keyboard exit and meaningful return focus.
  - Fix — Use a suitable dialog primitive and repair focus placement, containment and restoration.
- [ ] **A11Y-03** · major · A switch announces the wrong checked state, a tab reports the wrong role, or a save finishes without an accessible status update.
  - Detect — Activate a control with a screen reader. Compare announced role, value and state with the visible result, then listen for the outcome without moving focus.
  - Fix — Expose the actual control state and announce meaningful changes without moving focus.
- [ ] **A11Y-04** · major · Reading or focus order scrambles the task or forces traversal of repeated chrome.
  - Detect — Navigate linearly and by headings or landmarks. Compare with the visible sequence after reflow and test bypass of repeated navigation.
  - Fix — Put meaningful order in the underlying structure and provide a working bypass.
- [ ] **A11Y-05** · major · Small, crowded targets cause adjacent actions to compete for the same tap.
  - Detect — Measure active hitboxes. On web test 24 × 24 CSS px or the SC 2.5.8 spacing test: 24 px diameter circles centered on undersized target bounding boxes must intersect neither other targets nor circles of other undersized targets. Check inline, equivalent-control, unmodified user-agent and essential exceptions. Use applicable native platform guidance on native screens.
  - Fix — Enlarge the hit area or separate adjacent actions.
- [ ] **A11Y-06** · major · User text-spacing overrides clip text or conceal a control.
  - Detect — On applicable web content override line height to 1.5 times font size, paragraph spacing to 2, letter spacing to 0.12 and word spacing to 0.16 together. Apply only properties used in the language and script. Inspect real labels and content.
  - Fix — Remove fixed text bounds and allow the affected region to grow.
- [ ] **A11Y-07** · major · A spoken instruction lacks an equivalent transcript or captions, or a silent visual instruction has no accessible description or equivalent alternative.
  - Detect — Play each meaningful clip muted and audio-only. Check applicable captions, audio-only transcripts, video-only alternatives and audio description for meaningful visuals in prerecorded synchronized media. Account for clearly labeled alternatives to existing text.
  - Fix — Supply the equivalent content appropriate to the medium, including synchronized captions and audio description where required.
- [ ] **A11Y-08** · major · A checkout countdown or session timer ends a required step before the user can disable, adjust or extend an applicable time limit.
  - Detect — Trigger a time limit in a test session. Verify a mechanism to disable, adjust or extend it as applicable under SC 2.2.1. Check the real-time, essential and longer-than-20-hours exceptions.
  - Fix — Provide a compliant timing control and preserve work through reauthentication where possible.
- [ ] **A11Y-09** · major · Additional hover or focus content blocks reading or disappears before it can be used.
  - Detect — Trigger author-controlled additional content, move the pointer onto it, and dismiss it without moving focus or pointer if it obscures other content. Check persistence until dismissal, trigger removal or invalidation, and the input-error exception to dismissibility.
  - Fix — Make the additional content hoverable, persistent and dismissible where applicable.
- [ ] **A11Y-10** · blocker · Focus outlines are removed (`outline: none` or `outline: 0`) with no replacement focus style.
  - Detect — Grep `outline:\s*(none|0)|outline-none` and check for a matching `:focus-visible` rule. Tab through every control and watch for the indicator.
  - Fix — Restore visible focus, with 3:1 against adjacent colors where SC 1.4.11 applies.
- [ ] **A11Y-11** · blocker · A clickable div, span or placeholder anchor supplies the only path to a required action and keyboard users cannot activate it.
  - Detect — Grep `<(div|span)[^>]*on[Cc]lick|href="#"|tabindex="[1-9]` for candidates. Reach and operate each action by keyboard. Check Enter for links and Enter and Space for buttons. Record the action that cannot be completed.
  - Fix — Use `button`, `a[href]` or the native control.
- [ ] **A11Y-12** · blocker · A viewport restriction prevents users on a supported device from enlarging text to 200% and the interface provides no equivalent resizing mechanism.
  - Detect — Grep `user-scalable\s*=\s*(no|0)|maximum-scale\s*=\s*1(\.0)?\b`. Pinch-zoom on a phone.
  - Fix — Remove the restriction.
- [ ] **A11Y-13** · major · A missing document language, generic page title, or heading chosen only for its size misidentifies the page or gives assistive technology the wrong section structure.
  - Detect — List headings and landmarks from the accessibility tree. Check `document.documentElement.lang` and `document.title` per route.
  - Fix — Order headings by structure, add landmarks, set language and a unique title.
- [ ] **A11Y-14** · major · Names and alternatives are missing or junk: `<img>` with no `alt`, `alt="image"` or a filename; an icon-only button with no accessible name; a decorative image announced.
  - Detect — Grep `<img(?![^>]*\balt=)|alt="(image|photo|picture|icon|[^"]+\.(png|jpe?g|svg|webp))"`. List buttons and links whose accessible name is empty.
  - Fix — Write alt text for meaning, empty alt for decoration, and a name for every icon-only control.
- [ ] **A11Y-15** · major · Audio plays automatically, or video autoplays with sound, with no immediate way to stop it.
  - Detect — Load each page with sound on. Grep `autoplay` without `muted`.
  - Fix — Start muted or paused and give a visible control.

## Design tokens

- [ ] **TOKEN-01** · major · A local white fill, per-element dark override or competing variable set leaves a component in the old palette after the theme switches.
  - Detect — Change the canonical role in a preview or switch between supported themes. Compare two consumers of that role, including overlays and states, and trace the divergent value.
  - Fix — Bind both consumers to the authoritative semantic role through the project’s theme mechanism.
- [ ] **TOKEN-02** · major · Components contain hard-coded color, spacing, radius or font-size literals although the project has tokens for them.
  - Detect — Find literal colors and lengths in components. Confirm that an established token owns the same semantic role. An incidental numeric match is insufficient.
  - Fix — Replace the literal with the semantic token.
- [ ] **TOKEN-03** · major · Two independently editable theme files define the same role and changing the authoritative definition leaves some consumers on the old value.
  - Detect — Trace both definitions, change one in a preview, and inspect consumers. Generated outputs and platform adapters may share one authority.
  - Fix — Extend the existing source in its own format and remove the parallel one.
- [ ] **TOKEN-04** · minor · An overlay uses a local z-index such as 9999 that bypasses the established layer scale and places menus above a blocking dialog.
  - Detect — Grep `z-index:\s*\d{3,}|z-\[?\d{2,}`. List distinct values and compare with the layer tokens.
  - Fix — Define the layers once (sticky, dropdown, overlay, modal, toast, tooltip) and reference them.
- [ ] **TOKEN-05** · minor · Values sit off the scale: one-off spacing (13 px, 27 px), several near-identical greys, radii or shadows that differ by a step.
  - Detect — Collect distinct computed spacing, color, radius and shadow values on the changed screens and compare with the scale.
  - Fix — Snap to the nearest token, or add a token if the value has a repeated meaning.
- [ ] **TOKEN-06** · minor · The same component role has a different radius, height, padding or shadow in different places (pill buttons on one screen and square ones on another, with no rule).
  - Detect — Screenshot each instance of a role (primary button, input, card) across screens and compare computed styles.
  - Fix — State one rule per role in the tokens and apply it everywhere.

## Atomic design

- [ ] **ATOM-01** · major · A locally styled raw button, a call-site override or a second component kit loses focus, pending or theme behavior already supplied by the shared control.
  - Detect — Exercise both consumers with the same input. Compare the changed component with its existing equivalent in all supported themes, interaction states and platform conventions. Trace divergent values or behavior to their definitions.
  - Fix — Reuse the shared primitive or extend its semantic tokens and states.
- [ ] **ATOM-03** · major · A button accepts both loading and enabled activation flags, so it announces a pending operation while dispatching it again.
  - Detect — Render supported option combinations. Three interacting flags or roughly eight options are optional review triggers. Show the conflicting combination and its output.
  - Fix — Encode mutually exclusive intentions as one choice and separate independent state.
- [ ] **ATOM-04** · major · Independent instances interfere because a reusable presentation component owns unrelated feature state.
  - Detect — Mount two instances with different records. Trigger a load, failure or reset in one and inspect the other. Confirm the dependency causing the interference.
  - Fix — Move feature-specific state to its owner and pass each instance its own data and events.
- [ ] **ATOM-09** · major · A template substitutes fixture content or a fixed record count for supplied data.
  - Detect — Render the same template with zero, one and many distinct records. Trace any invented, repeated or omitted record to its source.
  - Fix — Pass the real collection through the template and keep example data in fixtures.
- [ ] **ATOM-10** · major · A shared control cannot express a required state through its supported interface.
  - Detect — Use a minimal consumer to reproduce a real calling flow, such as a pending save. Check whether the consumer must bypass the API to communicate that state.
  - Fix — Expose the required state and demonstrate it with a representative fixture.

## Animation

- [ ] **ANIM-01** · major · Decorative entrances or stagger delays hold a routine task hostage.
  - Detect — Re-enter a frequent flow and activate its last action immediately. Time the interval until it can respond. Investigate routine transitions over 300 ms, especially cumulative delays.
  - Fix — Make content actionable immediately and shorten or omit repeated entrances.
- [ ] **ANIM-02** · major · Rapid reversal or interruption leaves motion out of sync with the control.
  - Detect — Open, close and reopen a panel mid-transition. Release a drag early. Compare final position, focus and hit area with the actual state.
  - Fix — Interrupt from the current position and settle into the latest requested state.
- [ ] **ANIM-03** · major · Large nonessential movement persists under reduced-motion settings.
  - Detect — Search motion rules and preference hooks, then enable reduced motion before opening the view. Repeat parallax, zoom and transitions and record nonessential travel that persists.
  - Fix — Remove nonessential travel and retain a stable cue to the resulting state.
- [ ] **ANIM-04** · blocker · An effect exceeds the general or red flash threshold and flashes more than three times in one second.
  - Detect — Inspect recordings for more than three flashes in any one-second window. If present, require a verified assessment against general and red flash thresholds before clearance.
  - Fix — Remove the flash or reduce frequency below the trigger.
- [ ] **ANIM-05** · major · An automatic carousel, marquee or background video keeps moving beside other content without a pause, stop or hide control when one is required.
  - Detect — Observe automatic motion alongside other content for more than five seconds. Try to pause, stop or hide it. Exclude essential motion. For automatic updates alongside other content, test pause, stop, hide or frequency controls regardless of duration unless updating is essential.
  - Fix — Provide accessible playback or update controls and preserve the user’s choice.
- [ ] **ANIM-06** · minor · *(default tell)* The same fade-and-slide-up entrance plays on every section as it scrolls in, or every card lifts on hover, where neither the brief nor the existing system asks for it.
  - Detect — Scroll the page once and count identical entrances. Grep one reveal class or one in-view wrapper applied to all sections.
  - Fix — Keep one authored moment and let the rest simply appear.
- [ ] **ANIM-07** · minor · `transition: all` is used, or layout properties (`width`, `height`, `top`, `left`, margin, padding) are animated where a transform would do, producing visible jank.
  - Detect — Grep `transition:\s*all|transition-all` and transitions on layout properties. Record the animation with CPU throttling and look for dropped frames.
  - Fix — List the properties transitioned and move the change to `transform` and `opacity`.
- [ ] **ANIM-08** · minor · *(default tell)* An element enters from `scale(0)`, or a popover, menu or tooltip grows from its own center instead of from its trigger, where neither the brief nor the existing system asks for it.
  - Detect — Grep `scale\(0\)|scale-0`. Slow playback to a fifth of normal speed and watch the origin of each anchored surface.
  - Fix — Enter from about 0.95 with opacity and set `transform-origin` to the trigger.
- [ ] **ANIM-09** · minor · *(default tell)* Bounce or elastic easing is applied to routine product controls (menus, dialogs, toggles), where neither the brief nor the existing system asks for it.
  - Detect — Grep cubic-bezier curves with a control value above 1, and spring settings with high bounce, on routine controls.
  - Fix — Use a plain ease-out; keep bounce for playful brands and drag release.
- [ ] **ANIM-10** · minor · Hover motion is not gated to hover-capable pointers, so a transform sticks after a tap on touch screens.
  - Detect — Grep `:hover` rules that set `transform` outside `@media (hover: hover)`. Tap the element on a touch device.
  - Fix — Gate hover effects with `(hover: hover) and (pointer: fine)`.
- [ ] **ANIM-11** · major · Scrolling is hijacked: native scroll replaced by an inertia library, sections pinned with no fallback, or wheel input converted to horizontal movement, so keyboard, touch or find-in-page stop behaving normally.
  - Detect — Scroll by wheel, keyboard (Space, Page Down), touch and scrollbar drag. Grep scroll listeners that write state each frame and smooth-scroll libraries.
  - Fix — Keep native scrolling; use scroll-linked motion only where it carries meaning, with a fallback.
- [ ] **ANIM-12** · minor · *(default tell)* Cursor effects are added to an ordinary interface: a custom cursor, cursor trails, magnetic buttons, tilt-on-hover cards, where neither the brief nor the existing system asks for it.
  - Detect — Grep `cursor:\s*(none|url)` and pointer-move handlers that set transforms.
  - Fix — Remove them; keep the system cursor.
- [ ] **ANIM-13** · minor · *(default tell)* Decorative loops run forever: pulsing dots on things with no live status, a blinking cursor after a headline, shimmer on loaded content, more than one marquee, where neither the brief nor the existing system asks for it.
  - Detect — Grep `animation:.*infinite|animate-(pulse|ping|bounce|spin)`. For each, name the live state it reports.
  - Fix — Remove the loop or bind it to a real state, and stop it when off screen. Pause control is `ANIM-05`.

## Navigation

- [ ] **NAV-01** · major · A detail view has neither a meaningful title nor a current-location cue, or a dead-end error screen offers no route back.
  - Detect — Enter a detail view directly and from a filtered list. Inspect the title and active destination. Use the platform back action and verify the expected context and list position.
  - Fix — Identify the destination and preserve navigation history and relevant state.
- [ ] **NAV-02** · major · A promised task or destination cannot be found through the visible navigation.
  - Detect — Start at the intended entry point for each primary role and follow labels to the requested outcome, including after the menu collapses. Cite the missing or misleading step.
  - Fix — Expose a route using the audience’s vocabulary and task priority.
- [ ] **NAV-03** · major · A supported deep link or reload silently opens a different object or view.
  - Detect — Open a shareable filtered view, copy its address, and open it in a fresh authorized session. Compare object, filters and page. Test an expired or missing object.
  - Fix — Restore supported non-sensitive view state and explain unavailable destinations.
- [ ] **NAV-04** · major · Leaving a recoverable step silently discards unfinished work.
  - Detect — Edit a draft with disposable data. Navigate back, cancel leaving if offered, then reopen. Compare retained input with the flow’s stated save or discard behavior.
  - Fix — Preserve the draft or offer a clear choice before discarding changes.
- [ ] **NAV-05** · major · At a narrow width, the nav clips labels, wraps over the task, or drops destinations with no accessible replacement.
  - Detect — On responsive web, capture the navigation at 375, 768 and 1024 px. Compare the reachable destinations with the 1280 px set.
  - Fix — Move the same destinations into a menu, bar or drawer at that width.

## Native platforms

- [ ] **NATIVE-01** · major · The platform’s expected Back or dismissal action strands the user or exits the wrong level.
  - Detect — On each affected native target open a detail and a dismissible sheet. Invoke the supported system gesture or Back action. Record the resulting screen, selection and any unintended exit.
  - Fix — Integrate with the native navigation stack and preserve the expected dismissal behavior.
- [ ] **NATIVE-02** · major · The system navigation bar, header or tab bar is hidden and rebuilt by hand (a text title with a custom back button, a floating pill tab bar), losing back-swipe, large-title or scroll-to-top behavior.
  - Detect — Grep for the header-hidden option and custom tab-bar styling. On device, try back-swipe and tapping the status bar.
  - Fix — Configure the platform's navigation components.
- [ ] **NATIVE-03** · major · A custom picker hides the active field behind the keyboard or a dismissible sheet ignores its platform dismissal gesture.
  - Detect — Open each picker and compose flow. Check keyboard overlap, drag-down and system Back.
  - Fix — Use a keyboard-aware picker and support the expected dismissal for dismissible surfaces. Provide an explicit accessible exit for protected flows.
- [ ] **NATIVE-05** · minor · *(default tell)* One platform wears the other's conventions (iOS chevrons, large titles or iOS switches on Android; a floating action button or ripple in an iOS-idiom app), where neither the brief nor the existing system asks for it.
  - Detect — Compare navigation, switches, pickers and dialogs on each target with that platform's components. A documented platform-neutral design is not a hit.
  - Fix — Use each platform's idiom, or document the neutral treatment.
- [ ] **NATIVE-06** · major · A phone layout is stretched across a tablet, or orientation is locked to avoid fixing the landscape layout.
  - Detect — Run on a tablet class and rotate. Check the orientation setting in the app configuration against the task.
  - Fix — Restructure by size class and support both orientations unless the task requires one.
- [ ] **NATIVE-07** · minor · *(default tell)* The same scale-down press effect is applied to every touchable, including full-width list rows, where neither the brief nor the existing system asks for it.
  - Detect — Press a list row, a button and a card. Grep one shared press-scale applied to all touchables.
  - Fix — Highlight rows; scale or dim buttons only.

## Imagery and icons

- [ ] **IMG-01** · major · A broken image, stretched diagram, stand-in product or crop that cuts off the subject conceals information needed for the task.
  - Detect — Load the final asset at each supported aspect ratio. Compare the visible product, subject or chart with the actual record and approved reference. Force a load failure.
  - Fix — Use the correct asset and focal point, with a meaningful fallback.
- [ ] **IMG-02** · minor · The same icon signals different actions, or the icon changes meaning between platforms.
  - Detect — Compare repeated controls side by side. Check the rendered glyph and what activation does, especially for platform-dependent emoji and mirrored arrows.
  - Fix — Use a consistent metaphor for each action and label unfamiliar controls.
- [ ] **IMG-03** · major · An unresolved grey placeholder, rotating random-photo URL or expired external image stands in for a required final asset.
  - Detect — Grep `picsum|unsplash\.com|placehold|placeholder\.com|dummyimage`. List image hosts in the Network panel.
  - Fix — Replace the temporary slot with an approved final asset and verify it loads.
- [ ] **IMG-04** · minor · *(default tell)* Emoji or Unicode symbols stand in for interface icons (tab icons, button icons, feature bullets, empty-state art), where neither the brief nor the existing system asks for it.
  - Detect — Search markup for emoji code points in buttons, tabs, list markers and headings. Compare rendering on two platforms.
  - Fix — Use the project's icon family.
- [ ] **IMG-05** · minor · *(default tell)* Icons from different families, or with different stroke weights or fill styles, are mixed in one view, where neither the brief nor the existing system asks for it.
  - Detect — List icon imports per screen. Screenshot a toolbar or navigation and compare stroke width and corner style.
  - Fix — Use one family at one weight and size scale.
- [ ] **IMG-06** · minor · *(default tell)* The product is shown by a fake screenshot assembled from styled `<div>`s (a mock dashboard, terminal or task list), or by an illustration built from primitive shapes imitating a picture, where neither the brief nor the existing system asks for it.
  - Detect — Inspect the hero visual's DOM: a tree of rectangles with invented data and no real component behind it is a hit.
  - Fix — Use a real screenshot, a working miniature of the real component, or a labelled concept image.
- [ ] **IMG-07** · minor · In a comparable series, mismatched crops or grades obscure the subject, or the same avatar misidentifies different people.
  - Detect — Screenshot each image grid. Compare ratios and treatment; compare avatar sources across distinct names.
  - Fix — Fix one ratio and one treatment per role and give each person their own image.
- [ ] **IMG-08** · minor · *(default tell)* A generic stock photograph (a handshake, a staged "diverse team", a laptop on a desk) fills the hero or team section in place of the actual subject, where neither the brief nor the existing system asks for it.
  - Detect — For each photograph ask what in it belongs to this product, place or team.
  - Fix — Use an image of the real subject, or none.

## Perceived performance

- [ ] **PERF-01** · major · An image with no reserved dimensions, a late banner, a font swap or data arriving above the fold pushes a visible control out from under the pointer or moves the text being read.
  - Detect — Cold-load or refresh with delayed images, fonts and data. Track a visible control’s position before and after each arrival.
  - Fix — Reserve the final footprint and keep usable content stable during refresh.
- [ ] **PERF-02** · major · Nonessential work delays readable content or visibly stalls input.
  - Detect — On a representative slower device or profile, record cold entry, scrolling and a primary action. Identify long frames, blocked input or assets delaying the first useful view in the trace.
  - Fix — Prioritize essential content, right-size assets and remove measured main-thread work.
- [ ] **PERF-03** · major · Essential content stays invisible after a reveal effect or optional script fails.
  - Detect — Prevent the enhancement from running. Inspect the resting screen and try the primary task wherever the underlying content remains available.
  - Fix — Render essential content visibly by default and layer the optional reveal onto it.
- [ ] **PERF-04** · major · The primary image arrives late because it was lazy-loaded or oversized, or it pushes content down because no layout space was reserved.
  - Detect — Find the largest-contentful-paint element in a performance trace. Check `loading`, `width` and `height` attributes and compare natural size with rendered size.
  - Fix — Load it eagerly with priority, give it dimensions, and serve responsive sources.
- [ ] **PERF-05** · major · Rendering every row of a large list stalls scrolling or filtering on a supported device.
  - Detect — Load the largest realistic data set. Count DOM nodes and time scrolling and filtering.
  - Fix — Paginate or virtualize the slow list and repeat the same interaction.
- [ ] **PERF-06** · minor · A viewport-wide scrolling blur, grain layer or persistent will-change causes long frames or excessive layer allocation in a representative trace.
  - Detect — Grep `backdrop-filter|filter:\s*blur|will-change`. Record scrolling on a mid-range phone profile and look for long frames.
  - Fix — Confine the effect to a small fixed layer and remove standing `will-change`.

## Dark patterns and deceptive UX

- [ ] **DARK-01** · blocker · Marketing consent is preselected, a fee appears only after commitment, or a card-backed trial starts renewal without disclosing the recurring price.
  - Detect — Follow acceptance and refusal in a safe test account. Check defaults, full price, recurrence, data use and the moment of commitment against the recorded outcome.
  - Fix — Disclose material terms before commitment and require an explicit choice.
- [ ] **DARK-02** · blocker · “Cancel” loops through retention offers without an exit, or refusal is concealed behind a faint link or misleading, shaming label.
  - Detect — Follow the exit path from the same starting point as acceptance. Reload and verify the subscription, permission or preference actually changed. Compare the weight and wording of accept and decline.
  - Fix — Provide a discoverable exit and persist and confirm the requested change.
- [ ] **DARK-03** · blocker · A delete, send or pay action fires on a single activation with no confirmation and no undo, a destructive button sits beside and looks like the routine one, or the confirmation does not name what will be lost.
  - Detect — Use disposable data. Check whether the affected object and consequence are evident and whether review, confirmation or recovery protects the commitment.
  - Fix — Name the consequence and supply confirmation or a reliable recovery path.
- [ ] **DARK-04** · blocker · A countdown restarts on reload, “Only 2 left” contradicts inventory, or a crossed-out reference price was never charged.
  - Detect — Repeat the offer after the countdown expires or a new session starts. Compare its deadline, inventory and reference price with authoritative offer data.
  - Fix — Remove the pressure cue or bind the claim to verifiable terms.
- [ ] **DARK-05** · blocker · The interface presents another organization’s identity as its own or implies an unauthorized affiliation.
  - Detect — Compare logos, distinctive product chrome and identity claims with the brief and approved assets. Identify the misleading attribution.
  - Fix — Remove borrowed identity cues and use the product’s authorized system.
