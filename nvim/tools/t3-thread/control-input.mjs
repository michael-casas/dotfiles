// Public custom Ink stdin: private Neovim controls never reach useInput.
// This is not mouse interception and enables no terminal reporting modes.
import { PassThrough } from "node:stream";
import { StringDecoder } from "node:string_decoder";
import { decode, flush } from "./control.mjs";

export function createControlInput(source) {
  const stdin = new PassThrough();
  stdin.isTTY = source.isTTY;
  stdin.setRawMode = enabled => source.setRawMode?.(enabled);
  stdin.ref = () => source.ref?.();
  stdin.unref = () => source.unref?.();
  const listeners = new Set();
  const decoder = new StringDecoder("utf8");
  let state, timer, started = false, closed = false;
  function read(chunk) {
    clearTimeout(timer);
    const result = decode(typeof chunk === "string" ? chunk : decoder.write(chunk), state);
    state = result.state;
    for (const event of result.events) {
      if (event.type === "text") stdin.write(event.text);
      else for (const listener of listeners) listener(event.action, event.requestId);
    }
    if (flush(state)) {
      timer = setTimeout(() => {
        const text = flush(state);
        state = undefined;
        if (text && !closed) stdin.write(text);
      }, 50);
      timer.unref?.();
    }
  }
  return {
    stdin,
    onAction(listener) { listeners.add(listener); return () => listeners.delete(listener); },
    start() {
      if (started || closed) return;
      started = true;
      source.on("data", read);
    },
    close() {
      if (closed) return;
      closed = true;
      clearTimeout(timer);
      source.off("data", read);
      listeners.clear();
    },
  };
}
