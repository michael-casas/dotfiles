// Synthetic terminal peer for real Neovim mode/mouse tests; never runs hc/T3.
import { decode } from "../../control.mjs";
process.stdin.setRawMode(true);
let state;
let overlay = true;
process.stdout.write("Synthetic terminal ready\r\n");
process.stdin.on("data", chunk => {
  const result = decode(chunk.toString(), state);
  state = result.state;
  for (const event of result.events) {
    if (event.action === "escape") {
      process.stdout.write(`\x1b]7502;envi-t3-escape=${event.requestId};overlay=${overlay ? 1 : 0}\x1b\\`);
      overlay = false;
    }
  }
});
