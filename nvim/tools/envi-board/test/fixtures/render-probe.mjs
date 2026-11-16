import { appendFileSync } from "node:fs";
import childProcess from "node:child_process";
import { syncBuiltinESMExports } from "node:module";
import { DiagramRenderer } from "../../renderer.mjs";
const record = (value) =>
  appendFileSync(process.env.ENVI_BOARD_TEST_RENDER_LOG, value + "\n");
const spawn = childProcess.spawn;
childProcess.spawn = function (command, ...args) {
  if (command === "/usr/bin/sandbox-exec") record("ruby");
  return spawn.call(this, command, ...args);
};
syncBuiltinESMExports();
const render = DiagramRenderer.prototype.render;
DiagramRenderer.prototype.render = function (...args) {
  record("render");
  return render.apply(this, args).then((result) => {
    record("settled:" + result.kind);
    return result;
  });
};
