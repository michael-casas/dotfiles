import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { realpath } from "node:fs/promises";
import { resolve } from "node:path";
import { safePath, safeText } from "./document.mjs";
const exec = promisify(execFile);
const MAX = 2 * 1024 * 1024;
const env = () => ({
  PATH: process.env.PATH ?? "/usr/bin:/bin",
  HOME: "/nonexistent",
  LANG: "C",
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_NO_LAZY_FETCH: "1",
  GIT_NO_REPLACE_OBJECTS: "1",
  GIT_TERMINAL_PROMPT: "0",
  GIT_OPTIONAL_LOCKS: "0",
  GIT_ATTR_NOSYSTEM: "1",
});

/** Explicit host-bound local objects only. Never show/worktree/textconv/fetch. */
export async function pinnedSource(record, bindings = {}) {
  const unavailable = (reason) => ({
    state: "unavailable",
    reason,
    freshness: "unknown",
    lines: [],
  });
  if (
    !record ||
    !safePath(record.path) ||
    !/^([0-9a-f]{40}|[0-9a-f]{64})$/.test(record.commit) ||
    !Number.isSafeInteger(record.lines?.start) ||
    !Number.isSafeInteger(record.lines?.end) ||
    record.lines.start < 1 ||
    record.lines.end < record.lines.start
  )
    return unavailable("Invalid source record");
  if (!Object.hasOwn(bindings, record.root))
    return unavailable("No explicit trusted root binding");
  try {
    const root = await realpath(bindings[record.root]);
    const git = async (args) =>
      (
        await exec(
          "git",
          [
            "--no-pager",
            "--no-optional-locks",
            "-c",
            "core.hooksPath=/dev/null",
            "-c",
            "core.fsmonitor=false",
            "-c",
            "protocol.allow=never",
            "-C",
            root,
            ...args,
          ],
          { env: env(), encoding: "buffer", timeout: 3000, maxBuffer: MAX },
        )
      ).stdout;
    const top = (await git(["rev-parse", "--show-toplevel"])).toString().trim();
    if ((await realpath(top)) !== root)
      return unavailable("Binding must be the exact Git worktree root");
    const format = (await git(["rev-parse", "--show-object-format"]))
      .toString()
      .trim();
    if (record.commit.length !== (format === "sha256" ? 64 : 40))
      return unavailable("Commit object format mismatch");
    if (
      (await git(["cat-file", "-t", record.commit])).toString().trim() !==
      "commit"
    )
      return unavailable("Pin is not a commit object");
    let tree = (await git(["rev-parse", `${record.commit}^{tree}`]))
        .toString()
        .trim(),
      blob;
    // Descend tree objects by literal path segment; no revision:path grammar,
    // pathspec magic or intermediate symlink/submodule traversal.
    const parts = record.path.split("/");
    for (let i = 0; i < parts.length; i++) {
      const entries = (await git(["ls-tree", "-z", tree]))
        .toString("utf8")
        .split("\0");
      const entry = entries
        .map((e) => e.match(/^(\d+) (\w+) ([0-9a-f]+)\t([\s\S]*)$/))
        .find((e) => e && e[4] === parts[i]);
      if (!entry) return unavailable("Pinned path unavailable");
      const [, mode, type, oid] = entry;
      if (i < parts.length - 1) {
        if (mode !== "040000" || type !== "tree")
          return unavailable("Intermediate path is not a tree");
        tree = oid;
      } else {
        if (!["100644", "100755"].includes(mode) || type !== "blob")
          return unavailable(
            "Source is a symlink, submodule or nonregular object",
          );
        blob = oid;
      }
    }
    const size = Number((await git(["cat-file", "-s", blob])).toString());
    if (size > MAX) return unavailable("Blob exceeds 2 MiB");
    const bytes = await git(["cat-file", "blob", blob]);
    if (bytes.includes(0))
      return unavailable("Binary blob is not a source-line target");
    let text;
    try {
      text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    } catch {
      return unavailable("Non-UTF-8 blob is not a source-line target");
    }
    const lines = text.split(/\r?\n/);
    if (lines.at(-1) === "") lines.pop();
    if (record.lines.end > lines.length)
      return unavailable("Source range exceeds committed blob");
    return {
      state: "available",
      root: safeText(root),
      path: safeText(record.path),
      commit: record.commit,
      blob,
      freshness: "unknown",
      notice: "Immutable committed bytes; current checkout not compared",
      start: record.lines.start,
      lines: lines
        .slice(record.lines.start - 1, record.lines.end)
        .map(safeText),
    };
  } catch {
    return unavailable("Local Git object unavailable; no fetch attempted");
  }
}
