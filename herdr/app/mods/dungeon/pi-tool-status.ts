// pi extension: report each tool call to the terminal as an OSC 7501 status
// message, the way Claude Code does, so herdr-core (and the dungeon mod) can
// see tool calls. Load per run: pi -e ~/.dotfiles/herdr/app/mods/dungeon/pi-tool-status.ts
// pi's own status reports are unchanged; this only adds `msg` while working.
// @ts-nocheck

const APP = "pi";
let calls = 0;

function report(message: string): void {
  const clean = message.replace(/[\u0000-\u001f\u007f]/g, " ").slice(0, 200);
  const msg = Buffer.from(clean, "utf8").toString("base64");
  process.stdout.write(`\x1b]7501;state=working:app=${APP}:msg=${msg}\x1b\\`);
}

export default function (pi) {
  pi.on("tool_execution_start", (event) => {
    calls += 1;
    report(`${event?.toolName ?? "tool"} #${calls}`);
  });
}
