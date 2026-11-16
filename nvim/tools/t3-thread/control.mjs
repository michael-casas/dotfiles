// Private CSI protocol shared with hcmux/t3.lua. No printable shortcut: these
// reports are consumed before Ink sees stdin, including unknown/malformed ones.
const PREFIX = "\x1b[>777;";
// Ink 5 drops Home/End from its public key object. Normalize only these known
// unmodified terminal keys to the equivalent line-editing controls. Keep this
// byte map narrow: Cmd mappings need measured V1 evidence, not a meta guess.
const EDIT_KEYS = new Map([
  ...["\x1b[H", "\x1bOH", "\x1b[1~", "\x1b[7~"].map(bytes => [bytes, "\x01"]),
  ...["\x1b[F", "\x1bOF", "\x1b[4~", "\x1b[8~"].map(bytes => [bytes, "\x05"]),
]);
const ordinaryPrefix = tail => [...EDIT_KEYS.keys()].some(bytes => bytes.startsWith(tail));
// "dismiss" = what a bare Esc did: close a dialog, the model picker or a menu; never interrupts.
const ACTIONS = ["model", "compact", "yes", "cancel", "interrupt", "dismiss"];
export const sequence = action => {
  const index = ACTIONS.indexOf(action);
  if (index < 0) throw new Error(`Unknown T3 control: ${action}`);
  return `${PREFIX}${index + 1}u`;
};
export function decode(chunk, state = {}) {
  const input = (state.pending || "") + String(chunk);
  const events = [];
  let at = 0, text = "", pending = "", discard = state.discard || false;
  const emitText = () => {
    if (text) events.push({ type: "text", text });
    text = "";
  };
  while (at < input.length) {
    if (discard || input.startsWith(PREFIX, at)) {
      emitText();
      const start = at;
      if (!discard) at += PREFIX.length;
      while (at < input.length && input[at] !== "u") at++;
      if (at === input.length) {
        if (discard || at - start > 32) discard = true;
        else pending = input.slice(start);
        break;
      }
      const report = input.slice(start, ++at);
      const match = !discard && /^\x1b\[>777;([1-6])u$/.exec(report);
      discard = false;
      if (match) events.push({ type: "action", action: ACTIONS[Number(match[1]) - 1] });
      continue;
    }
    const tail = input.slice(at);
    const editKey = [...EDIT_KEYS.keys()].find(bytes => input.startsWith(bytes, at));
    if (editKey) {
      emitText();
      events.push({ type: "text", text: EDIT_KEYS.get(editKey) });
      at += editKey.length;
      continue;
    }
    if (PREFIX.startsWith(tail) || ordinaryPrefix(tail)) { pending = tail; break; }
    text += input[at++];
  }
  emitText();
  return { events, state: { pending, discard } };
}
export function flush(state = {}) {
  // Once private '>' is recognized, never release its bytes as composer text.
  return state.pending && ordinaryPrefix(state.pending) ? state.pending : "";
}
export function escapeAction({ model, menu } = {}) {
  return model ? "close-model" : menu ? "close-menu" : "ignore";
}
function compactReason(context) {
  if (!context.threadId) return "no thread is open";
  if (context.conn !== "live") return "T3 is not connected";
  if (context.working) return "a turn or request is active";
  if (context.busy) return "another action is pending";
  if (!context.compactAvailable) return "this provider does not advertise /compact";
  return null;
}
export function compact(dialog, action, context) {
  if (action === "open") {
    const reason = compactReason(context);
    return { dialog: {
      kind: "compact",
      allowed: !reason,
      text: reason ? `Cannot compact: ${reason}. Press any key to dismiss.` : "Compact this thread? y/n",
    } };
  }
  if (dialog && action === "yes" && dialog.allowed && !compactReason(context))
    return { dialog: null, send: "/compact" };
  return { dialog: null };
}

function interruptNotice(context) {
  if (!context.working) return "Nothing to interrupt. Press any key to dismiss.";
  if (context.conn !== "live") return "Cannot interrupt: T3 is not connected. Press any key to dismiss.";
  if (context.busy) return "Cannot interrupt: another action is pending. Press any key to dismiss.";
  return null;
}
export function interrupt(dialog, action, context) {
  if (action === "open") {
    const reason = interruptNotice(context);
    return { dialog: { kind: "interrupt", allowed: !reason, text: reason || "Interrupt the agent? y/n" } };
  }
  if (dialog?.allowed && action === "yes") {
    const reason = interruptNotice(context);
    if (reason) return { dialog: { kind: "interrupt", allowed: false, text: reason } };
    return { dialog: null, stop: true };
  }
  return { dialog: null };
}
