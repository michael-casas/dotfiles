import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  realpathSync,
  mkdtempSync,
  writeFileSync,
  rmSync,
  readFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { diagramProfile } from "../profile.mjs";
import { DiagramRenderer, sandboxPolicy } from "../renderer.mjs";
const fixtures = {
  flowchart: "flowchart LR\n A[Start] --> B{Ready?}\n B -->|yes| C[Ship]\n",
  sequence:
    "sequenceDiagram\n participant A as Alice\n participant B as Bob\n A->>B: Request\n B-->>A: Response\n",
  class:
    "classDiagram\n class Animal {\n +String name\n +move() void\n }\n class Duck {\n +quack() void\n }\n Animal <|-- Duck : extends\n",
  state:
    "stateDiagram-v2\n [*] --> Idle\n Idle --> Running : start\n Running --> [*] : finish\n",
  er: "erDiagram\n CUSTOMER ||--o{ ORDER : places\n CUSTOMER {\n int id PK\n string name\n }\n ORDER {\n int id PK\n }\n",
  gantt:
    "gantt\n title Release\n dateFormat YYYY-MM-DD\n section Build\n Design :d1, 2026-01-01, 2d\n Implement :d2, 2026-01-03, 1w\n",
};
test("all six corpus-profiled families render locally with original source; cache preserves revision", async () => {
  const renderer = new DiagramRenderer();
  try {
    for (const [family, source] of Object.entries(fixtures)) {
      assert.equal(
        diagramProfile(source).supported,
        true,
        `${family}: ${JSON.stringify(diagramProfile(source))}`,
      );
      const start = performance.now();
      const r = await renderer.render(source, { revision: "a" });
      assert.equal(
        r.kind,
        "text-approximate",
        `${family}: ${JSON.stringify(r)}`,
      );
      assert.equal(r.source, source);
      assert.ok(r.lines.length > 0);
      assert.equal(r.family, family);
      assert.ok(performance.now() - start < 5000);
      const warm = await renderer.render(source, { revision: "b" });
      assert.equal(warm.revision, "b");
      assert.deepEqual(warm.lines, r.lines);
    }
  } finally {
    renderer.close();
  }
});
test("complete allowlist rejects unprofiled tokens, configuration/resource channels and lost semantics", async () => {
  const bad = [
    'flowchart LR\n A --> B\n click A "https://example.invalid"',
    "flowchart LR\n A --> B\n invalid @@ syntax",
    "sequenceDiagram\n participant A\n alt valid\n end",
    "stateDiagram-v2\n state A {\n [*] --> B\n }",
    "classDiagram\n namespace Space {",
    "erDiagram\n A ||--o{ B : <b>label</b>",
    "gantt\n dateFormat YYYY-MM-DD HH:mm",
    "gantt\n Task :done, a1, 2026-01-01, 2d",
    "---\nconfig: x\n---\nflowchart LR\nA --> B",
    "%%{init: {}}%%\nflowchart LR\nA --> B",
    "flowchart LR\n A[<img src=x>] --> B",
    "flowchart LR\n A[bad\x1b] --> B",
    "flowchart LR\n A --> B; B --> C",
  ];
  const r = new DiagramRenderer();
  try {
    for (const source of bad) {
      assert.equal(diagramProfile(source).supported, false, source);
      const result = await r.render(source);
      assert.equal(result.kind, "unsupported");
      assert.equal(result.source, source);
      assert.equal(result.lines, undefined);
    }
  } finally {
    r.close();
  }
});
test("limits, incompatible Ruby, closed queue, timeout and output failure never publish partial graphs", async () => {
  assert.equal(
    diagramProfile(
      "flowchart LR\n" +
        Array.from({ length: 501 }, (_, i) => ` A${i} --> A${i + 1}`).join(
          "\n",
        ),
    ).supported,
    false,
  );
  assert.equal(diagramProfile("x".repeat(51201)).supported, false);
  for (const opts of [
    { ruby: "/no/such/ruby" },
    { timeout: 1 },
    { maxOutput: 1 },
  ]) {
    const r = new DiagramRenderer(opts);
    const value = await r.render(fixtures.flowchart);
    assert.equal(value.kind, "error");
    assert.equal(value.lines, undefined);
    r.close();
    r.close();
  }
  const r = new DiagramRenderer();
  r.close();
  assert.equal((await r.render(fixtures.flowchart)).kind, "unsupported");
});
test("actual isolation denies unrelated file read/write and child exec without attempting network", () => {
  const dir = mkdtempSync(join(tmpdir(), "board-isolation-"));
  try {
    const file = join(dir, "sentinel");
    writeFileSync(file, "synthetic sentinel");
    const ruby = realpathSync("/opt/homebrew/opt/ruby/bin/ruby"),
      policy = sandboxPolicy(dirname(dirname(ruby)));
    const run = (code) =>
      spawnSync(
        "/usr/bin/sandbox-exec",
        ["-p", policy, ruby, "--disable-gems", "-e", code],
        { encoding: "utf8", env: { PATH: "/usr/bin:/bin" }, timeout: 3000 },
      );
    assert.notEqual(run(`File.read(${JSON.stringify(file)})`).status, 0);
    assert.notEqual(
      run(`File.write(${JSON.stringify(file)}, 'changed')`).status,
      0,
    );
    assert.notEqual(run('exec "/bin/echo", "child"').status, 0);
    assert.equal(readFileSync(file, "utf8"), "synthetic sentinel");
    assert.ok(!policy.includes("allow network"));
  } finally {
    rmSync(dir, { recursive: true });
  }
});

test("vendored merminal tree matches pinned release manifest", async () => {
  const { createHash } = await import("node:crypto");
  const manifest = JSON.parse(
    readFileSync(new URL("../vendor/manifest.json", import.meta.url)),
  );
  assert.equal(manifest.version, "0.1.0");
  assert.equal(
    manifest.gemSha256,
    "91567f6de0bb5c9d11069acad1fc0eee2bf135a23ad38785ff4f3e61a2de23db",
  );
  for (const [path, hash] of Object.entries(manifest.files))
    assert.equal(
      createHash("sha256")
        .update(
          readFileSync(
            new URL("../vendor/merminal-0.1.0/" + path, import.meta.url),
          ),
        )
        .digest("hex"),
      hash,
      path,
    );
});

test("renderer reuses uncolored no-fit output across width/theme changes without another Ruby job", async () => {
  const renderer = new DiagramRenderer();
  try {
    const first = await renderer.render(fixtures.flowchart, {
      width: 80,
      theme: "nord",
      revision: "a",
    });
    assert.equal(first.kind, "text-approximate");
    renderer.ruby = "/no/such/ruby"; // A second backend launch cannot succeed.
    const cached = await renderer.render(fixtures.flowchart, {
      width: 140,
      theme: "gruvbox-dark",
      revision: "b",
    });
    assert.equal(cached.kind, "text-approximate");
    assert.equal(cached.revision, "b");
    assert.deepEqual(cached.lines, first.lines);
    assert.equal(renderer.cache.size, 1);
  } finally {
    renderer.close();
  }
});

test("deterministic engine rejections share the bounded input cache without bookkeeping leaks", async () => {
  const rejected = "flowchart LR\n A[First] --> B\n A[Second] --> C\n";
  const renderer = new DiagramRenderer();
  try {
    const first = await renderer.render(rejected, { revision: "a" });
    assert.equal(first.kind, "error");
    assert.equal(first.retryable, false);
    assert.equal(
      renderer.cache.size,
      1,
      "engine rejection occupies the bounded cache",
    );
    const bytes = renderer.cacheBytes;
    renderer.ruby = "/no/such/ruby";
    const second = await renderer.render(rejected, { revision: "b" });
    assert.deepEqual({ ...second, revision: "a" }, first);
    assert.equal(second.revision, "b");
    assert.equal(renderer.cacheBytes, bytes);
  } finally {
    renderer.close();
  }
});

test("transient deadline and unavailable runtime failures retry and recover on the same input", async () => {
  for (const options of [
    { timeout: 1 },
    { ruby: "/no/such/ruby" },
    { maxOutput: 1 },
  ]) {
    const renderer = new DiagramRenderer(options);
    const ruby =
      process.env.ENVI_BOARD_RUBY ?? "/opt/homebrew/opt/ruby/bin/ruby";
    try {
      const first = await renderer.render(fixtures.flowchart);
      assert.equal(first.kind, "error");
      assert.equal(first.retryable, true);
      assert.equal(
        renderer.cache.size,
        0,
        "transient failures must not poison input cache",
      );
      renderer.timeout = 5000;
      renderer.ruby = ruby;
      renderer.maxOutput = 16 * 1024 * 1024;
      const recovered = await renderer.render(fixtures.flowchart);
      assert.equal(recovered.kind, "text-approximate");
      const cached = await renderer.render(fixtures.flowchart);
      assert.deepEqual(
        cached,
        recovered,
        "cache hits expose only public result fields",
      );
      assert.equal("_size" in cached, false);
    } finally {
      renderer.close();
    }
  }
});

test("signal-killed renderer is not a deterministic rejection and retries", async () => {
  const renderer = new DiagramRenderer();
  try {
    const pending = renderer.render(fixtures.flowchart);
    assert.ok(renderer.child);
    renderer.child.kill("SIGKILL");
    const first = await pending;
    assert.equal(first.kind, "error");
    assert.equal(first.retryable, true);
    assert.equal(renderer.cache.size, 0);
    assert.equal(
      (await renderer.render(fixtures.flowchart)).kind,
      "text-approximate",
    );
  } finally {
    renderer.close();
  }
});
