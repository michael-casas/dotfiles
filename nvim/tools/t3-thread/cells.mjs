// Shared composer/rendering display-cell metrics. Offsets elsewhere remain UTF-16.
const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });
export const graphemes = (s) => [...segmenter.segment(s)].map((g) => g.segment);
export const wide = (n) =>
  n >= 0x1100 &&
  (n <= 0x115f ||
    n === 0x2329 ||
    n === 0x232a ||
    (n >= 0x2e80 && n <= 0xa4cf && n !== 0x303f) ||
    (n >= 0xac00 && n <= 0xd7a3) ||
    (n >= 0xf900 && n <= 0xfaff) ||
    (n >= 0xfe10 && n <= 0xfe19) ||
    (n >= 0xfe30 && n <= 0xfe6f) ||
    (n >= 0xff00 && n <= 0xff60) ||
    (n >= 0xffe0 && n <= 0xffe6) ||
    (n >= 0x1f000 && n <= 0x1faff) ||
    (n >= 0x20000 && n <= 0x3fffd));
export function cellWidth(g) {
  if (/^[\p{Mark}\u200d\ufe0f]+$/u.test(g)) return 0;
  // Match Ink's emoji measurement even for text-default symbols (✳, ↪).
  if (
    g.includes("\ufe0f") ||
    g.includes("\u20e3") ||
    (g.codePointAt(0) > 0x7f && /\p{Emoji}/u.test(g))
  )
    return 2;
  return wide(g.codePointAt(0)) ? 2 : 1;
}
export const displayWidth = (s) =>
  graphemes(s).reduce((n, g) => n + cellWidth(g), 0);
