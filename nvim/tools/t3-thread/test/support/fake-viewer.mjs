// Synthetic stand-in for `hc attach` replaying a terminal's history.
//
// It models the *hypothesised* herdr-core boundary for BATDD-T3STRIKE-01..03:
// cells the program left at the default background are serialized with the
// negotiated colour as an explicit background. History painted before the
// viewer attaches uses terminal.run's display.bg (FAKE_RUN_BG); history after
// attach uses this terminal's answer to OSC 11. Intentional code and bubble
// surfaces keep their own colours. Whether the real core does this is NOT
// proven here; only the colour Neovim negotiates is production behaviour.
//
// env: FAKE_MARKER, FAKE_RUN_BG (#rrggbb), FAKE_CODE_BG, FAKE_BUBBLE_BG,
//      FAKE_LOG (file receiving every byte typed into the terminal)
import fs from "node:fs";

const marker = process.env.FAKE_MARKER || "M";
const log = process.env.FAKE_LOG;
const out = (s) => process.stdout.write(s);
const rgb = (hex) => {
  const n = parseInt(String(hex || "#000000").slice(1), 16);
  return `${(n >> 16) & 255};${(n >> 8) & 255};${n & 255}`;
};
const answers = {};

if (process.stdin.isTTY) process.stdin.setRawMode(true);
process.stdin.on("data", (d) => {
  const s = d.toString("latin1");
  // OSC colour answers are terminal replies, not typed keys.
  const typed = s.replace(/\x1b\](1[012]);(rgb:[0-9a-f/]+)(?:\x1b\\|\x07)/gi, (_, code, value) => {
    answers[code] = value;
    return "";
  });
  if (log && typed) fs.appendFileSync(log, typed);
});

function block(label, bg, n) {
  for (let i = 0; i < n; i++) out(`\x1b[48;2;${rgb(bg)}m\x1b[2K${label}_${marker}_${i}\x1b[0m\r\n`);
  out(`\x1b[48;2;${rgb(bg)}m\x1b[2K\x1b[0m\r\n`); // an erased separator row
}
function surfaces() {
  out(`\x1b[48;2;${rgb(process.env.FAKE_CODE_BG)}m  CODE_${marker}  \x1b[0m\r\n`);
  out(`\x1b[48;2;${rgb(process.env.FAKE_BUBBLE_BG)}m  BUBBLE_${marker}  \x1b[0m\r\n`);
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));
block("PRE", process.env.FAKE_RUN_BG, 12);
surfaces();
out("\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b]12;?\x1b\\");
for (let t = 0; t < 150 && !(answers["10"] && answers["11"] && answers["12"]); t++) await wait(10);
// Unanswered queries fall back to black, as terminals' programs do.
const hex = (v) => {
  const m = /^rgb:([0-9a-f]{2})[0-9a-f]*\/([0-9a-f]{2})[0-9a-f]*\/([0-9a-f]{2})/i.exec(v || "");
  return m ? `#${m[1]}${m[2]}${m[3]}`.toLowerCase() : "#000000";
};
out(`OSC_${marker} fg=${hex(answers["10"])} bg=${hex(answers["11"])} cursor=${hex(answers["12"])}\r\n`);
block("POST", hex(answers["11"]), 12);
for (let i = 0; i < 30; i++) out(`tail ${marker} ${i}\r\n`);
out(`READY_${marker}\r\n`);
setInterval(() => {}, 1 << 30);
process.on("SIGTERM", () => process.exit(0));
