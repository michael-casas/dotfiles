#!/usr/bin/env node
// ~/.dotfiles/opencode/agent/__tests__/tier-files.test.mjs
//
// TDD validation for the 5 opencode tier files (t0..t3). Each tier
// file is a thin YAML frontmatter; this test asserts:
//   1. file exists and is >50 bytes
//   2. frontmatter parses (YAML valid)
//   3. `model:` is set and matches the filename-derived expectation
//   4. `permission:` block contains the required keys
//   5. `permission.bash:` has `"*": deny` as the catch-all
//   6. `description:` mentions the tier number
//
// Exit code: 0 = all green, 1 = any failure.

import { readFile, stat, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parse as parseYaml } from "yaml";

const __dirname = dirname(fileURLToPath(import.meta.url));
const AGENT_DIR = resolve(__dirname, "..");

// filename → expected model string (opencode-go/<id>)
const TIER_MODEL = {
  "t0-dsv4.md": "opencode-go/deepseek-v4-flash",
  "t1-m2-7.md": "opencode-go/minimax-m2.7",
  "t2-kk2-7c.md": "opencode-go/kimi-k2.7-code",
  "t3-mm3-oc.md": "opencode-go/minimax-m3",
  "t3-mm3.md": "opencode-go/minimax-m3",
};

const REQUIRED_PERMISSION_KEYS = [
  "read",
  "grep",
  "glob",
  "list",
  "bash",
];

function extractFrontmatter(src) {
  // matches ---\n ... \n---  (no body needed for tier files but tolerate body)
  const m = src.match(/^---\n([\s\S]*?)\n---\n?/);
  return m ? m[1] : null;
}

const results = [];
let failed = 0;

for (const [filename, expectedModel] of Object.entries(TIER_MODEL)) {
  const fp = join(AGENT_DIR, filename);
  const tierName = filename.replace(/\.md$/, "");
  const tierNumber = tierName.match(/^t(\d+)/)?.[1] ?? "?";

  const checks = [];
  const fail = (msg) => { checks.push({ ok: false, msg }); failed++; };
  const pass = (msg) => { checks.push({ ok: true, msg }); };

  // 1. exists + >50 bytes
  if (!existsSync(fp)) { fail(`file does not exist: ${fp}`); results.push({ tierName, checks }); continue; }
  const s = await stat(fp);
  if (s.size <= 50) { fail(`file is ${s.size} bytes, must be > 50`); results.push({ tierName, checks }); continue; }
  pass(`exists and is ${s.size} bytes (>50)`);

  // 2. frontmatter parses
  const src = await readFile(fp, "utf8");
  const fm = extractFrontmatter(src);
  if (fm === null) { fail("no frontmatter delimiters found"); results.push({ tierName, checks }); continue; }
  let doc;
  try { doc = parseYaml(fm); } catch (e) { fail(`YAML parse error: ${e.message}`); results.push({ tierName, checks }); continue; }
  if (!doc || typeof doc !== "object") { fail("frontmatter is empty or not a mapping"); results.push({ tierName, checks }); continue; }
  pass("frontmatter parses as YAML mapping");

  // 3. model: matches expected
  if (doc.model === undefined) { fail("`model:` field missing"); }
  else if (doc.model !== expectedModel) { fail(`\`model:\` is "${doc.model}", expected "${expectedModel}"`); }
  else { pass(`\`model:\` = "${doc.model}"`); }

  // 4. permission: required keys
  if (!doc.permission || typeof doc.permission !== "object") { fail("`permission:` block missing"); }
  else {
    for (const k of REQUIRED_PERMISSION_KEYS) {
      if (!(k in doc.permission)) fail(`\`permission.${k}\` missing`);
    }
    if (Object.keys(REQUIRED_PERMISSION_KEYS).every(k => k in (doc.permission ?? {}))) {
      pass("`permission:` has all required keys");
    }
  }

  // 5. permission.bash: has "*": deny
  const bash = doc.permission?.bash;
  if (!bash || typeof bash !== "object") { fail("`permission.bash:` block missing"); }
  else if (bash["*"] !== "deny") { fail(`\`permission.bash["*"]\` is "${bash["*"]}", expected "deny"`); }
  else { pass("`permission.bash[\"*\"]: deny`"); }

  // 6. description: mentions tier number
  if (typeof doc.description !== "string") { fail("`description:` missing or not a string"); }
  else if (!doc.description.includes(`Tier ${tierNumber}`)) {
    fail(`\`description:\` does not mention "Tier ${tierNumber}"`);
  } else { pass(`description mentions "Tier ${tierNumber}"`); }

  // 7. tools: has webfetch + websearch
  if (!doc.tools || typeof doc.tools !== "object") { fail("`tools:` block missing"); }
  else if (!("webfetch" in doc.tools) || !("websearch" in doc.tools)) {
    fail("`tools:` missing webfetch or websearch");
  } else { pass("`tools:` has webfetch + websearch"); }

  // 8. file is <= 180 lines (relaxed from 80 once charters grew to
  //    include the full body sections: your-purpose, CORE LAW, TIER LADDER
  //    POSITION, WHEN TO USE, WHEN NOT TO USE — required by
  //    fill-opencode-tier-charters spec)
  const lineCount = src.split("\n").length;
  if (lineCount > 180) { fail(`file is ${lineCount} lines, must be <= 180`); }
  else { pass(`file is ${lineCount} lines (<=180)`); }

  // 9. body has the required sections from the spec
  const REQUIRED_BODY_SECTIONS = [
    "## Your purpose",
    "## CORE LAW",
    "## TIER LADDER POSITION",
    "## WHEN TO USE",
    "## WHEN NOT TO USE",
  ];
  for (const s of REQUIRED_BODY_SECTIONS) {
    if (!src.includes(s)) fail(`body missing required section: ${s}`);
  }
  if (REQUIRED_BODY_SECTIONS.every((s) => src.includes(s))) {
    pass("body has all 5 required sections");
  }

  // 10. t3 variants are distinct: t3-mm3 has task allow (campaign),
  //     t3-mm3-oc has task deny (opencode envelope)
  if (tierName === "t3-mm3") {
    const taskPolicy = doc.permission?.task;
    if (taskPolicy?.["*"] !== "allow") fail("t3-mm3 must have `permission.task[\"*\"]: allow` (campaign variant)");
    else pass("t3-mm3 task policy = allow (campaign)");
  }
  if (tierName === "t3-mm3-oc") {
    const taskPolicy = doc.permission?.task;
    if (taskPolicy?.["*"] !== "deny") fail("t3-mm3-oc must have `permission.task[\"*\"]: deny` (envelope variant)");
    else pass("t3-mm3-oc task policy = deny (envelope)");
  }

  results.push({ tierName, checks });
}

// Report
console.log("");
for (const r of results) {
  const allOk = r.checks.every((c) => c.ok);
  console.log(`${allOk ? "✓" : "✗"} ${r.tierName}.md`);
  for (const c of r.checks) {
    console.log(`    ${c.ok ? "✓" : "✗"} ${c.msg}`);
  }
}
console.log("");
const totalChecks = results.reduce((n, r) => n + r.checks.length, 0);
const passedChecks = results.reduce((n, r) => n + r.checks.filter((c) => c.ok).length, 0);
console.log(`Summary: ${passedChecks}/${totalChecks} checks passed across ${results.length} tier files.`);

process.exit(failed === 0 ? 0 : 1);
