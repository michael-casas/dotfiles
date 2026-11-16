import { spawn, execFile, execFileSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { createHash } from "node:crypto";
import { diagramProfile, PROFILE } from "./profile.mjs";
import { safeText } from "./document.mjs";
const dir = dirname(realpathSync(fileURLToPath(import.meta.url)));
const quote = (s) => JSON.stringify(s);

export function sandboxPolicy(rubyPrefix) {
  return `(version 1)(deny default)(allow process-exec (literal ${quote(realpathSync(resolve(rubyPrefix, "bin/ruby")))}))(allow process-info*)(allow file-read-metadata)(allow sysctl-read)(allow mach-lookup)(allow file-read* (literal "/") (subpath "/System/Library") (subpath "/usr/lib") (subpath "/usr/share/locale") (subpath "/private/var/db/dyld") (literal "/dev/null") (literal "/dev/urandom") (subpath ${quote(rubyPrefix)}) (subpath ${quote(resolve(dir, "vendor"))}) (literal ${quote(resolve(dir, "render-job.rb"))}))`;
}

/** One bounded child at a time, bounded queue/cache; caller guards generations. */
export class DiagramRenderer {
  constructor({
    ruby = process.env.ENVI_BOARD_RUBY ?? "/opt/homebrew/opt/ruby/bin/ruby",
    timeout = 5000,
    maxOutput = 16 * 1024 * 1024,
  } = {}) {
    this.ruby = ruby;
    this.timeout = Math.min(5000, timeout);
    this.maxOutput = Math.min(16 * 1024 * 1024, maxOutput);
    this.cache = new Map();
    this.cacheBytes = 0;
    this.queue = [];
    this.closed = false;
  }
  render(source, { revision = "" } = {}) {
    const p = diagramProfile(source),
      fallback = (reason) => ({
        kind: "unsupported",
        reason,
        source,
        revision,
      });
    if (!p.supported) return Promise.resolve(fallback(p.reason));
    // The backend is color:false, fit:nil: geometry and palette do not affect bytes.
    const key = createHash("sha256")
      .update(JSON.stringify(["merminal-0.1.0", PROFILE, source]))
      .digest("hex");
    if (this.cache.has(key))
      return Promise.resolve({ ...this.cache.get(key), revision });
    if (this.closed || this.queue.length >= 64)
      return Promise.resolve(fallback("renderer closed or queue full"));
    return new Promise((resolve) => {
      this.queue.push({ source, p, key, revision, resolve });
      this.next();
    });
  }
  next() {
    if (this.child || this.closed) return;
    const job = this.queue.shift();
    if (!job) return;
    const finish = (result) => {
      if (job.finished) return;
      job.finished = true;
      clearTimeout(job.timer);
      clearInterval(job.memory);
      this.child = null;
      // Cache settled failures too; resize/reopen must not repeatedly run bad input.
      if (!this.closed) {
        const size = Buffer.byteLength(JSON.stringify(result));
        while (
          this.cache.size >= 64 ||
          this.cacheBytes + size > 8 * 1024 * 1024
        ) {
          const key = this.cache.keys().next().value;
          if (!key) break;
          this.cacheBytes -= this.cache.get(key)._size;
          this.cache.delete(key);
        }
        if (size <= 8 * 1024 * 1024) {
          this.cache.set(job.key, { ...result, _size: size });
          this.cacheBytes += size;
        }
      }
      job.resolve({ ...result, revision: job.revision });
      this.next();
    };
    const failed = (reason) =>
      finish({ kind: "error", reason, source: job.source });
    let argv;
    try {
      if (process.platform !== "darwin") throw Error("isolation unavailable");
      const ruby = realpathSync(this.ruby),
        prefix = dirname(dirname(ruby));
      // Probe trusted runtime only, never document input. Minimal environment
      // excludes RUBYOPT/RUBYLIB/GEM_HOME and any caller credentials.
      const version = execFileSync(
        ruby,
        ["--disable-gems", "-e", "print RUBY_VERSION"],
        { env: { PATH: "/usr/bin:/bin" }, timeout: 1000, encoding: "utf8" },
      );
      const [major, minor] = version.split(".").map(Number);
      if (major < 3 || (major === 3 && minor < 3)) throw Error("Ruby too old");
      argv = [
        "-p",
        sandboxPolicy(prefix),
        ruby,
        "--disable-gems",
        resolve(dir, "render-job.rb"),
      ];
    } catch {
      failed(
        "isolated merminal unavailable (macOS sandbox and Ruby >=3.3 required)",
      );
      return;
    }
    const child = spawn("/usr/bin/sandbox-exec", argv, {
      cwd: dir,
      env: { PATH: "/usr/bin:/bin", LANG: "en_US.UTF-8" },
      stdio: ["pipe", "pipe", "pipe"],
    });
    this.child = child;
    const chunks = [];
    let bytes = 0,
      diagnostic = false,
      killed = false;
    child.stdout.on("data", (chunk) => {
      bytes += chunk.length;
      if (bytes > this.maxOutput) {
        killed = true;
        child.kill("SIGKILL");
      } else chunks.push(chunk);
    });
    child.stderr.on("data", () => {
      diagnostic = true;
    });
    job.timer = setTimeout(() => {
      killed = true;
      child.kill("SIGKILL");
    }, this.timeout);
    job.timer.unref();
    // macOS has no usable RLIMIT_AS/DATA; sample only the exact owned pid.
    // This is a resident-memory policy, not an instantaneous allocation cap.
    job.memory = setInterval(() => {
      execFile(
        "/bin/ps",
        ["-o", "rss=", "-p", String(child.pid)],
        { timeout: 500, env: { PATH: "/usr/bin:/bin" } },
        (error, out) => {
          if (!error && Number(out.trim()) > 256 * 1024) {
            killed = true;
            child.kill("SIGKILL");
          }
        },
      );
    }, 100);
    job.memory.unref();
    child.stdin.on("error", () => {});
    child.on("error", () => failed("renderer launch failed"));
    child.on("close", (code) => {
      if (this.closed || killed || code !== 0 || diagnostic)
        failed(
          killed
            ? "renderer time/output limit"
            : "renderer failed or emitted diagnostics; partial output discarded",
        );
      else {
        const output = safeText(Buffer.concat(chunks).toString("utf8"));
        finish({
          kind: "text-approximate",
          source: job.source,
          sourceHash: createHash("sha256").update(job.source).digest("hex"),
          family: job.p.family,
          lines: output.replace(/\n$/, "").split("\n"),
          engine: "merminal-0.1.0",
          profile: PROFILE,
        });
      }
    });
    child.stdin.end(job.source);
  }
  close() {
    if (this.closed) return;
    this.closed = true;
    this.child?.kill("SIGKILL");
    for (const j of this.queue)
      j.resolve({
        kind: "error",
        reason: "renderer closed",
        source: j.source,
        revision: j.revision,
      });
    this.queue = [];
    this.cache.clear();
    this.cacheBytes = 0;
  }
}
