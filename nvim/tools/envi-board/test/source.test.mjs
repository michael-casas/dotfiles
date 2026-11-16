import test from "node:test";
import assert from "node:assert/strict";
import {
  mkdtempSync,
  writeFileSync,
  mkdirSync,
  symlinkSync,
  rmSync,
  readFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { pinnedSource } from "../source.mjs";
const fixture = () => {
  const root = mkdtempSync(join(tmpdir(), "board-git-"));
  const git = (...args) =>
    execFileSync("git", ["-C", root, ...args], {
      encoding: "utf8",
      env: {
        ...process.env,
        GIT_CONFIG_NOSYSTEM: "1",
        GIT_CONFIG_GLOBAL: "/dev/null",
        GIT_AUTHOR_NAME: "Demo",
        GIT_AUTHOR_EMAIL: "demo@example.invalid",
        GIT_COMMITTER_NAME: "Demo",
        GIT_COMMITTER_EMAIL: "demo@example.invalid",
      },
    }).trim();
  return { root, git };
};
for (const format of ["sha1", "sha256"])
  test(`local ${format} commit pin, literal colon/@ filename, immutable bytes and freshness unknown`, async () => {
    const { root, git } = fixture();
    try {
      git("init", `--object-format=${format}`, "-q");
      mkdirSync(join(root, "src"));
      writeFileSync(join(root, "src/a:b@c.txt"), "first\nsecond\nthird\n");
      git("add", ".");
      git("commit", "-qm", "fixture");
      const commit = git("rev-parse", "HEAD");
      const record = {
        root: "repo",
        path: "src/a:b@c.txt",
        commit,
        lines: { start: 2, end: 3 },
      };
      assert.equal((await pinnedSource(record)).state, "unavailable");
      writeFileSync(join(root, record.path), "different worktree bytes\n");
      const s = await pinnedSource(record, { repo: root });
      assert.equal(s.state, "available", JSON.stringify(s));
      assert.deepEqual(s.lines, ["second", "third"]);
      assert.equal(s.freshness, "unknown");
      assert.equal(git("status", "--porcelain"), "M src/a:b@c.txt");
      assert.equal(
        (
          await pinnedSource(
            { ...record, commit: "0".repeat(commit.length) },
            { repo: root },
          )
        ).state,
        "unavailable",
      );
      assert.equal(
        (
          await pinnedSource(
            { ...record, commit: git("rev-parse", "HEAD^{tree}") },
            { repo: root },
          )
        ).state,
        "unavailable",
      );
      assert.equal(
        (
          await pinnedSource(
            { ...record, lines: { start: 1, end: 20 } },
            { repo: root },
          )
        ).state,
        "unavailable",
      );
      assert.equal(
        (await pinnedSource({ ...record, path: "../outside" }, { repo: root }))
          .state,
        "unavailable",
      );
    } finally {
      rmSync(root, { recursive: true });
    }
  });
test("symlink, binary, submodule, replace refs and textconv cannot substitute source bytes", async () => {
  const { root, git } = fixture();
  try {
    git("init", "-q");
    writeFileSync(join(root, "file.txt"), "original\n");
    writeFileSync(join(root, "binary"), Buffer.from([0, 1, 2]));
    symlinkSync("file.txt", join(root, "link"));
    writeFileSync(join(root, ".gitattributes"), "file.txt diff=hostile\n");
    git("add", ".");
    git("commit", "-qm", "original");
    const first = git("rev-parse", "HEAD");
    const r = {
      root: "repo",
      path: "file.txt",
      commit: first,
      lines: { start: 1, end: 1 },
    };
    git("config", "diff.hostile.textconv", "false");
    for (const path of ["binary", "link"])
      assert.equal(
        (await pinnedSource({ ...r, path }, { repo: root })).state,
        "unavailable",
      );
    writeFileSync(join(root, "file.txt"), "replaced\n");
    git("add", ".");
    git("commit", "-qm", "replacement");
    const second = git("rev-parse", "HEAD");
    git("replace", first, second);
    assert.deepEqual((await pinnedSource(r, { repo: root })).lines, [
      "original",
    ]);
    git("update-index", "--add", "--cacheinfo", `160000,${second},module`);
    git("commit", "-qm", "submodule");
    assert.equal(
      (
        await pinnedSource(
          { ...r, commit: git("rev-parse", "HEAD"), path: "module" },
          { repo: root },
        )
      ).state,
      "unavailable",
    );
  } finally {
    rmSync(root, { recursive: true });
  }
});
test("unknown board version never resolves sources even with host binding", () => {
  const main = new URL("../main.mjs", import.meta.url).pathname;
  const dir = mkdtempSync(join(tmpdir(), "board-opaque-"));
  try {
    const path = join(dir, "opaque.wb.md");
    writeFileSync(
      path,
      '---\n{"format":"envi-whiteboard","version":1,"id":"demo","roots":{}}\n---\n\nopaque\n',
    );
    const r = spawnSync(
      process.execPath,
      [main, "render", "--bind", "repo=" + dir, "--", path],
      { encoding: "utf8" },
    );
    assert.equal(r.status, 0);
    assert.match(r.stdout, /OPAQUE/);
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("pinned CRLF source displays ordinary line endings without mutating committed bytes", async () => {
  const { root, git } = fixture();
  try {
    git("init", "-q");
    git("config", "core.autocrlf", "false");
    writeFileSync(join(root, "lines.txt"), "one\r\ntwo\r\n");
    git("add", ".");
    git("commit", "-qm", "CRLF fixture");
    const record = {
      root: "repo",
      path: "lines.txt",
      commit: git("rev-parse", "HEAD"),
      lines: { start: 1, end: 2 },
    };
    const source = await pinnedSource(record, { repo: root });
    assert.equal(source.state, "available");
    assert.deepEqual(source.lines, ["one", "two"]);
    assert.equal(git("cat-file", "blob", source.blob), "one\r\ntwo");
  } finally {
    rmSync(root, { recursive: true });
  }
});
