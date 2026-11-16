// Question-window interaction is pure; main owns request lifetime and the one RPC.
import { editInput } from "./view.mjs";

export const bubbleCount = q => (q?.options?.length || 0) + (q?.allowCustomAnswer !== false ? 1 : 0);
export function selection(requestId, q, previous) {
  const same = previous?.requestId === requestId && previous?.questionId === q.id;
  return {
    requestId, questionId: q.id,
    selected: same ? Math.max(0, Math.min(previous.selected || 0, bubbleCount(q) - 1)) : 0,
    checked: same ? (previous.checked || []).filter(i => i >= 0 && i < (q.options?.length || 0)) : [],
  };
}
export function input(q, current, editor, ch, key = {}) {
  const options = q.options || [], count = bubbleCount(q);
  let next = { ...current };
  const result = extra => ({ selection: next, editor, ...extra });
  if (key.upArrow || (key.ctrl && ch === "p")) {
    next.selected = count ? (next.selected - 1 + count) % count : 0;
    return result();
  }
  if (key.downArrow || (key.ctrl && ch === "n")) {
    next.selected = count ? (next.selected + 1) % count : 0;
    return result();
  }
  const custom = next.selected === options.length && q.allowCustomAnswer !== false;
  const digit = !key.ctrl && !key.meta && /^[1-9]$/.test(ch);
  const toggle = i => {
    const checked = new Set(next.checked);
    if (checked.has(i)) checked.delete(i); else checked.add(i);
    next.checked = [...checked].sort((a, b) => a - b);
  };
  // Once editing a custom answer, digits and spaces are ordinary composer text.
  if (digit && !custom) {
    const i = Number(ch) - 1;
    if (i < count) {
      next.selected = i;
      if (q.multiSelect && i < options.length) toggle(i);
    }
    return result();
  }
  if (ch === " " && !key.ctrl && !key.meta && q.multiSelect && !custom) {
    toggle(next.selected);
    return result();
  }
  if (key.return) {
    if (custom) return editor.value.trim()
      ? result({ answer: editor.value.trim() })
      : result({ error: "Type an answer in the composer." });
    if (q.multiSelect) return next.checked.length
      ? result({ answer: next.checked.map(i => options[i].value ?? options[i].label) })
      : result({ error: "Choose at least one option with Space or 1–9." });
    const option = options[next.selected];
    return option ? result({ answer: option.value ?? option.label }) : result({ error: "No answers available." });
  }
  if (q.allowCustomAnswer !== false) {
    const edited = editInput(editor.value, editor.cursor, ch, key);
    if (edited.value !== editor.value) next.selected = options.length;
    editor = edited;
  }
  return result();
}
