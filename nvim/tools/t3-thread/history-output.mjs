// Match DisplayLine's Ink Text styling without feeding committed rows into
// Ink's permanent Static cache. Only the live region remains in the Ink tree.
import chalk from "chalk";
import { inkText } from "./layout.mjs";

export const CLEAR_HISTORY = "\x1b[2J\x1b[3J\x1b[H";
function colour(text, value, background = false) {
  if (!value) return text;
  if (value in chalk) return chalk[background ? `bg${value[0].toUpperCase()}${value.slice(1)}` : value](text);
  if (value.startsWith("#")) return (background ? chalk.bgHex(value) : chalk.hex(value))(text);
  const rgb = /^rgb\(\s?(\d+),\s?(\d+),\s?(\d+)\s?\)$/.exec(value);
  if (rgb) {
    const [r, g, b] = rgb.slice(1).map(Number);
    return (background ? chalk.bgRgb(r, g, b) : chalk.rgb(r, g, b))(text);
  }
  const ansi = /^ansi256\(\s?(\d+)\s?\)$/.exec(value);
  return ansi ? (background ? chalk.bgAnsi256(Number(ansi[1])) : chalk.ansi256(Number(ansi[1])))(text) : text;
}
export function historyOutput(blocks) {
  return blocks.flatMap(block => block.lines.map(line => {
    // Remove only unpainted trailing padding, never a styled surface.
    const spans = line.map(s => ({...s}));
    while (spans.length && !spans.at(-1).bg && !spans.at(-1).inverse) {
      const last = spans.at(-1);
      last.text = last.text.trimEnd();
      if (last.text) break;
      spans.pop();
    }
    return spans.map(s => {
      let text = colour(s.text, s.color);
      text = colour(text, s.bg, true);
      for (const style of ["bold", "underline", "inverse"]) if (s[style]) text = chalk[style](text);
      return inkText(text);
    }).join("") + "\n";
  })).join("");
}
