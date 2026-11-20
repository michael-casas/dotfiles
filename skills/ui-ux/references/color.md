# Color

Concern: palette, color strategy, semantic color, contrast, theming and dark mode.

Owned elsewhere: where color values live and how themes remap them is `tokens.md`;
color as a means of emphasis is `hierarchy.md`; chart palettes belong to the `dataviz`
skill when it is available.

## 1. Strategy before swatches

Choose how much color the surface carries before choosing hues.

| Strategy | Meaning | Suits |
|---|---|---|
| Restrained | Neutrals plus one accent | Operate and Read surfaces; the default there |
| Committed | One saturated color owns 30 to 60 percent of the surface | Persuade, Experience, a single hero screen in a product |
| Full palette | 3 or 4 named roles | Brands with range; data-rich editorial |
| Drenched | The surface is the color | A campaign, a launch, a statement page |

- Take hue from the subject and the direction, never from a category habit.
- Let the strongest color own a region or a role. Scattered small accents read as noise.
- Reserve the action color for actions, current selection and state. Do not spend it on
  decoration, or the primary action stops being findable.
- Keep one accent, one neutral family and one palette for the whole product. A second
  accent needs a role the first cannot play.
- A neutral may be tinted toward the brand hue when that creates cohesion. A true gray,
  a true black and a true white are all valid when chosen. Pick each on purpose.
- On a colored surface, derive secondary text from that surface's hue or from the
  foreground color, and check its contrast. Generic gray on color washes out.
- Gradients, glass, grain and glow are materials. Use one when it comes from the
  subject's world or does a job (depth, focus, atmosphere behind a photograph), keep it
  in the palette, and keep text readable over it.

## 2. Building the palette

- Define 4 to 6 named values with roles first, then expand to ramps as needed.
- Use the project's existing color space. For a new web palette OKLCH makes lightness
  and chroma steps predictable. Reduce chroma near the lightest and darkest ends.
- Prefer explicit colors to stacks of translucent overlays; alpha makes contrast depend
  on what is underneath.
- Status colors keep one meaning throughout, and follow platform and domain convention.
  Pair each with a second cue: icon, label, shape or position.
- For data colors and chart palettes, use the `dataviz` skill when it is available.

## 3. Contrast

| Pair | Minimum (WCAG 2.2 AA) |
|---|---|
| Body text | 4.5:1 |
| Large text: 18 pt regular or 14 pt bold and larger | 3:1 |
| Visual cues needed to identify a control, its state or a meaningful graphic | 3:1 |
| Placeholder text, helper text, disabled-looking but active text | 4.5:1 |

Logos, incidental text, inactive controls and unmodified browser controls are exempt.
`accessibility.md`, section 5, owns the criteria and their exceptions.

- Measure computed, composited colors, including alpha and text over images. Do not
  judge from a thumbnail.
- Check every state: hover, focus, active, selected, error, and every theme.
- Text over imagery needs a scrim, a solid backing or a guaranteed-contrast region.

## 4. Themes and dark mode

- **Scope.** Which themes ship is a project decision. Follow the brief and the existing
  product; when neither says, respect the system preference if the stack makes that
  cheap, and otherwise ship one well-made theme. Every theme that ships is designed and
  verified. Structure tokens so adding a theme later is a remap, not a rewrite.
- **Choosing light or dark for a single-theme surface.** Decide from the scene of use:
  who, where, under what light, for how long. Not from the product category.
- **Dark is designed, not inverted.** Set surface elevation explicitly (raised surfaces
  are lighter). Lower the contrast of large text slightly, raise the lightness of
  accents until they pass contrast, and replace shadows with tonal steps or darker,
  more transparent shadows.
- **Mechanics.** Support both a system-preference query and an explicit attribute on the
  root, with the explicit choice winning. All colors come from tokens; a hard-coded hex
  will not switch.
- **One theme per page.** Sections stay inside the page's theme family. A section that
  inverts the theme is a deliberate, single composition device or it does not happen.
- Also check forced-colors mode and, where glass is used, a solid fallback for
  reduced-transparency preferences.

## Audit coverage

AUDIT items `COLOR-01` to `COLOR-03` (contrast and redundant cues), and `COLOR-04` to
`COLOR-07`. Related: `SLOP-04` to `SLOP-06` for default palettes and `SLOP-02` for a missing
required identity cue; `TOKEN-01` for theme propagation.
