# Typography

Concern: typeface choice and pairing, the type scale, measure, leading, tracking,
numerals, and font loading. Type carries the personality of the page, so each of these
is decided, not defaulted.

Owned elsewhere: how size, weight and space direct attention is `hierarchy.md`; the
words themselves are `content.md`; type tokens are `tokens.md`.

## 1. Choosing typefaces

- **Existing system first.** If the project has typefaces, use them and improve how they
  are used. Changing a typeface changes identity and wrapping; treat it as a redesign
  decision, never as a low-risk tweak.
- **One family or two.** One well-tuned family is often right, and on Operate and Read
  surfaces it usually is. If two, make them clearly different in structure and give each
  a role only it performs.
- **Choose from the subject.** Pick a face the way you would pick an object from the
  subject's world: for its character, its era, its register. State the reason in the
  plan. "It looks premium" is not a reason, and neither is a category association
  (books so serif, tech so mono).
- **No face is banned and none is mandated.** A widely used neutral sans is a correct
  choice for a neutral tool or an accessibility-first service. The same face chosen
  because it is what you always type is a default. The difference is whether you can
  state the reason. AUDIT `TYPE-04` covers an ungrounded default face; `SLOP-02`
  applies when it replaces a required identity cue.
- **Check availability.** Confirm the font is actually obtainable and licensed for this
  use. Do not assume a commercial font is installed. Confirm it supports the languages
  and the weights the design needs.
- **Monospace** is for code, data that must align, and measurement. Elsewhere it needs a
  reason from the brief.

## 2. Scale and roles

- Define roles, not sizes: display, heading levels, body, label, caption, data. Give
  each role one size, weight, line height and tracking, and reuse it everywhere.
- Make adjacent levels visibly different. A ratio of 1.25 or more between steps suits
  expressive pages; 1.125 to 1.2 suits dense product UI, which has more levels.
- Use more than two weights when the family has them; medium and semibold give
  hierarchy that regular and bold alone cannot.
- Product UI: a fixed rem scale. Marketing and editorial display type may respond to the
  viewport with `clamp()`; body text stays fixed.
- How the scale directs attention (emphasis, reading order, focal points) is owned by
  `hierarchy.md`. This file owns the faces and the metrics.

## 3. Measure, leading and spacing

These are starting ranges. The actual face, script and brief decide; confirm by looking
at the return sweep, collisions, glyph clipping and the fallback font's metrics.

| Setting | Starting range |
|---|---|
| Body line length | 45 to 75 characters. Investigate sustained lines over 80. Serif body may run slightly longer. |
| Body size, web | 16 px (1rem) minimum. 14 px only for secondary text. |
| Body line height | 1.4 to 1.6 for sans; slightly more for serif, for long lines, and for light text on dark |
| Heading line height | 1.05 to 1.3, tighter as size grows |
| Display tracking | Slightly negative, commonly to about -0.03em. Past about -0.04em, check for touching letters. |
| Small caps or all-caps tracking | Slightly positive |
| Tables and compact UI | May exceed 75 characters per row; measure applies to prose |

- Tune line height to the face, the size and the script. Check descenders and accents:
  a display line at line-height 1.0 clips `g j p q y` and stacked diacritics, most
  visibly in italics. Use at least 1.1 and look at the render.
- Light text on a dark ground needs slightly more leading, slightly more tracking, and
  sometimes one weight step heavier.
- Space above a heading exceeds space below it, so the heading belongs to what follows.
- Mark paragraphs with spacing or with first-line indent, not both.
- Balance headings and avoid single-word last lines: `text-wrap: balance` for headings,
  `text-wrap: pretty` for prose, where supported.
- Use tabular numerals where numbers change or align in columns.
- Use typographic quotes and apostrophes in prose.

## 4. Headlines as design

- When type is the visual element, treat the type itself as the design: its scale, its
  break, its weight and its position are the composition.
- Let the content and viewport decide wrapping. Do not delete important words to hit a
  line count; change the size or the measure instead.
- Emphasis inside a headline, if any, comes from the same family. Singling out one word
  in italic, bold or a second color is the commonest generated-page treatment; use it
  only when that word is the point.
- A label above a heading must add information the heading does not carry. Default to no
  label. See AUDIT `SLOP-03`, and `SLOP-10`.
- Sentence case by default. All caps only for short labels where the brief or the
  system calls for it.

## 5. Loading and resilience

- Load only the families and weights used. Self-host or use the framework's font
  loader; avoid blocking text.
- Provide a fallback stack with similar metrics so the swap does not reflow the page.
- Check the render after the font has loaded and with it blocked.
- Preserve browser zoom, user font-size settings and platform text scaling. Never
  disable zoom.
- Test with the longest real heading, a translated string 30 to 40 percent longer, and a
  narrow container.

## Audit coverage

AUDIT items `TYPE-02` and `TYPE-03` (measure, glyphs), and `TYPE-04` to `TYPE-09` and
`TYPE-11`. Clipped glyphs are `TYPE-03`. Related: `SLOP-02` (a face that replaces a required identity cue), `SLOP-03` (false markers),
`SLOP-13` (single-word emphasis), `HIER-01` (roles), `LAYOUT-03` and `A11Y-06`
(resize and spacing), `PERF-01` (font-loading shifts).
