# Imagery

Concern: icons, illustration, photography, generated imagery, and building an interface
from a picture (a mockup, a screenshot, a generated reference).

Owned elsewhere: image layout and aspect-ratio mechanics are `layout.md`; alt text rules
are `accessibility.md`, section 2; loading metrics are `verification.md`, section 7.

## 1. Whether the surface needs imagery

- Decide from the brief and the subject. A product people look at (food, places,
  objects, people, physical craft) usually needs real pictures of it. A tool, a
  document or a type-led identity may need none.
- A page carried by typography and layout is complete. Do not add images to fill space,
  and do not strip them from a subject that is visual.
- Each image has a structural job: it leads the hierarchy, proves a claim, or shows the
  product. One decisive image beats several incidental ones.
- Show a product with the product: a real screenshot, a working miniature of the real
  component, or a labelled concept image. A misleading stand-in is AUDIT `IMG-01`;
  the div-built fake screenshot is `IMG-06`.

## 2. Sourcing, in order of preference

1. **Supplied assets:** the client's photography, brand files, product screenshots.
2. **Produced for this brief:** generated or commissioned images, made for a specific
   placement at its aspect ratio. Only when an authorized image tool is actually
   available. Never emit a pretend tool call or claim an image was generated when it
   was not.
3. **Licensed stock,** chosen for the subject's actual object or place, not the
   category. Verify that each URL resolves and that the licence covers the use.
4. **Clearly marked placeholders.** When nothing above is possible, reserve the slot at
   the right aspect ratio, label what belongs there, and list every placement in the
   handoff: what is needed, at what size.

Rules for all four:

- Random-photo placeholder services are acceptable only as marked placeholders in a
  draft. They are not subject-matched, licensed or stable, and they are never the
  shipped imagery.
- Never hotlink another site's production assets.
- Record origin and licence for every shipped raster. For a generated image, keep the
  prompt.
- Real logos require the right to use them. A customer logo wall states a factual claim:
  use it only for real customers. For sample brands, a plain wordmark or a simple
  authored mark, labelled as sample.
- People in testimonials and team sections are real, or the section is marked as sample.

## 3. Art direction

- One image treatment across the product: one grade, one framing logic, one material
  vocabulary, one illustration style. Mixed sources are graded to match.
- Take the treatment from the direction's palette. A full-bleed image supports the
  palette and never fights it.
- Text over an image gets a scrim, a solid backing or a reserved calm region, and its
  contrast is measured.
- Use a small set of fixed aspect ratios, repeated for the same role (all cards one
  ratio, all portraits another). Choose crops per breakpoint; a wide hero crop rarely
  survives a phone.
- Match the medium to the content. Photographs, people, objects and lit materials are
  raster. Geometry, diagrams, icons, linework and anything that must scale, move or
  respond are vector or code. Do not approximate a photograph with shapes, and do not
  rasterize what should stay sharp and interactive.
- Authored vector work is first-class when it does geometry: marks, diagrams, patterns,
  data graphics. A vector scene imitating a detailed picture is rarely worth it; use a
  real image or none.

## 4. Icons

- Use the project's existing icon set. For a new project choose one family for its fit
  with the type and the tone, and say why.
- One family, one stroke weight, one size scale, optically aligned to text. The
  library is not the issue; mixing families, or picking one without noticing you picked,
  is.
- Icons are drawn glyphs, not emoji or Unicode symbols, unless the brand's voice is
  emoji.
- Choose the metaphor for the meaning. A familiar icon for a familiar action is correct;
  novelty that slows recognition is not.
- Icons that carry meaning alone have an accessible name and, where space allows, a
  visible label. Decorative icons are hidden from assistive technology.
- An icon earns its place by speeding up scanning or matching a platform convention.
- On native platforms use the platform's symbol set.
- Ship a favicon or app icon that belongs to the brand.

## 5. Delivery

- Give every image intrinsic dimensions or an aspect ratio, so nothing shifts on load.
- Serve responsive sources (`srcset` and `sizes`) in a modern format, sized to their
  rendered size.
- Load the primary above-the-fold image eagerly and with priority. Lazy-load images
  below the fold.
- Write alt text for meaningful images; use empty alt for decorative ones.
- Design the failure: a broken or slow image leaves a sensible background and layout.
- Fonts and images are dependencies with a loading cost, a fallback and a provenance.

## 6. Image-first workflow

Use when an image tool is available and the brief is visually led, or when the user asks
to see the design before it is built. The image is a design reference; the deliverable
is working interface code.

### 6.1 Lock a concept before generating

Write down what every image must share:

- palette and accent logic;
- type character and scale rhythm;
- spacing and density;
- corner and line language;
- button and control family;
- image treatment and icon style;
- for apps: platform mode, navigation model, device frame.

Each later image is generated against this record, so image five still belongs to the
same product as image one. Variation is allowed in composition, emphasis and pace. It is
not allowed in identity.

### 6.2 Generate

- One image per section or per screen, at a size where its text is legible. Do not pack
  a whole page into one small image.
- Frame each at the surface's own shape: landscape for desktop sections, portrait at
  device size for phone screens.
- Lead the prompt with the surface's structure (its regions, in order, with their
  scale), then the content, then the concept record. Use the real product name and real
  content. Do not let the image invent commercial claims.
- When a detail is unreadable, generate a fresh, closer image of that part. Do not crop
  and enlarge an old one.
- Generate what resolves a real decision, within a budget the user has approved. More
  images are not more design.
- Generation and other external services receive what you send them. Do not send
  private source, unreleased assets or customer data to one without authorization.
- For an app, the screens form a believable flow: each follows from an action on the
  previous one.

### 6.3 Get agreement

Show the reference and get the user's choice before building, unless they delegated it.
If you choose on their behalf, say so and say why.

## 7. Building from an image

Applies to a generated reference, a supplied mockup or a screenshot.

### 7.1 Read it as a specification

Inspect the image at a legible size and record, in writing, before any code:

| Aspect | What to extract |
|---|---|
| Text | Every readable string: headline, body, labels, button text, navigation |
| Type | Size relationships, weights, line counts, wrapping, tracking, serif or sans |
| Space | Gaps between headline, body and actions; section padding; gutters; card padding |
| Color | Background, surfaces, text levels, accent, borders, shadow tone, image grade |
| Components | Button shape, radius, fill or outline, icon use; card structure; inputs; dividers |
| Structure | Grid, alignment, section order, density, what repeats |
| Medium | Per region: raster, vector, or live interface |

What the image does not show (other states, other widths, hover, focus) is built from
this record, not from a stock kit.

### 7.2 Implement faithfully

- Reproduce the reference at its own width first. Then derive the other breakpoints.
- Keep the reference's spacing rhythm, type character, section order and distinct
  sections. The common failure is drift: a strong reference becomes a generic coded
  layout. Do not simplify a distinctive section into a standard row, compress generous
  spacing, or reintroduce nested containers the reference did not have.
- Interface text and controls are real, semantic, selectable and operable. A picture of
  an interface is not an implementation.
- Three things may differ from the reference: the font (use the closest obtainable
  face), icons (use the project's set), and genuine defects in the image such as
  misspellings or impossible details.
- Fix what is inaccessible in the reference (low contrast, tiny targets, tiny text) and
  say that you did, with the reason.
- When a region cannot be matched in code and it is pictorial, produce it as an asset.
- Resolve ambiguity in this order: keep the visible design language; keep layout and
  spacing logic; keep the component family; generate a closer reference; only then pick
  the simplest faithful option.

### 7.3 Compare

- Screenshot the build at the reference's pixel dimensions and set the two side by side,
  region by region at legible scale. Do not compare against memory, and do not compare
  whole-page thumbnails.
- Judge scale and density as quantities: type at half the weight, or a field at a tenth
  of the coverage, is a different design.
- Then run the checks no image can cover: states, responsiveness, keyboard, contrast.

## 8. References and other people's work

- A reference is evidence for principles: hierarchy, density, rhythm, posture. Take the
  principle and build an original design.
- Do not clone a company's distinctive screens, layouts or identity, and do not
  reproduce copyrighted content, unless the user clearly owns it.
- Distinguish, in the handoff, between a concept image, a real product screenshot, and
  shipped content.

## Audit coverage

AUDIT items `IMG-01` and `IMG-02`, and `IMG-03` to `IMG-08`. Related:
`PERF-01` and `PERF-02` (image loading and shift), `A11Y-14` (text alternatives),
`CONTENT-03` (fabricated endorsements), `DARK-05` (borrowed identity).
