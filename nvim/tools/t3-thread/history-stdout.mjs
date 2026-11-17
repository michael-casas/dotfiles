// Public Ink stdout adapter. Never patch Ink or process.stdout: protect only
// renderer-originated full clears, keeping stream dimensions/events unchanged.
import { CLEAR_HISTORY } from "./history-output.mjs";

export function historyStdout(stdout) {
  let recover = null, planned = false;
  return {
    stream: new Proxy(stdout, {
      get(target, key) {
        if (key === "write") return (data, ...args) => {
          const text = typeof data === "string" ? data : data.toString();
          const recovery = !planned && text.startsWith(CLEAR_HISTORY) ? recover?.() : null;
          if (!recovery) return target.write(data, ...args);
          // Restore before even the live frame: core history must never end
          // with a destructive clear lacking its complete replacement.
          const result = target.write(CLEAR_HISTORY + recovery.output + text.slice(CLEAR_HISTORY.length), ...args);
          target.write("", recovery.flushed);
          return result;
        };
        const value = Reflect.get(target, key, target);
        return typeof value === "function" ? value.bind(target) : value;
      },
    }),
    onClear(handler) { recover = handler; return () => { if (recover === handler) recover = null; }; },
    historyWrite(write, text) {
      planned = true;
      try { write(text); } finally { planned = false; }
    },
  };
}
