// Preloaded (NODE_OPTIONS --import) into OLD clients during E2 only: records
// each successful websocket upgrade (HTTP 101 on /ws) as "<pid> <epoch ms>" in
// $T3UPD_UPGRADES, from undici's diagnostics channel. No URLs or tickets.
import fs from "node:fs";
import diagnostics from "node:diagnostics_channel";

const file = process.env.T3UPD_UPGRADES;
if (file) diagnostics.channel("undici:request:headers").subscribe(({ request, response }) => {
  if (String(request.path).split("?")[0] === "/ws" && response?.statusCode === 101)
    try { fs.appendFileSync(file, `${process.pid} ${Date.now()}\n`); } catch {}
});
