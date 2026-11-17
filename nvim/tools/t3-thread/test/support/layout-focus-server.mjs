// Local synthetic T3 only; stdin lifetime belongs to the Lua test harness.
import { startFakeT3 } from "./fake-t3.mjs";
import { snapshot } from "./synthetic-thread.mjs";
const fake = await startFakeT3({ initial: [snapshot()] });
console.log(fake.url);
process.stdin.resume();
process.stdin.on("end", async () => { await fake.close(); });
