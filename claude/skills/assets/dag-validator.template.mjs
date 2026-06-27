#!/usr/bin/env node
// Validator template for ATDD-DAG tasks.
//
// The atdd-dag-generation skill's `scripts/generate.py` reads this template
// and emits one .mjs file per task ID declared in tasks.md.
//
// Contract:
//   Exit 0  → task is GREEN (all scenarios pass)
//   Exit 1  → task is RED (one or more scenarios failed)
//   Exit 2  → task is BLOCKED (preconditions not met, surface out of scope)
//
// Wired as: pnpm agent:validate:<task-id>
// Lives at: .agent/tools/validate-<task-id>.mjs
//
// The implementer fills in the TODO blocks with the actual assertions
// described in the task body's Given/When/Then scenarios.

import { existsSync, statSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { resolve, relative } from 'node:path';

const PROJECT_ROOT = resolve(process.cwd());
const TASK_ID = '<TASK_ID>';
const TASK_TITLE = '<TASK_TITLE>';
const TDD_PHASE = '<TDD_PHASE>'; // RED | GREEN | REFACTOR | N/A
const WRITE_SURFACE = [
  // '<relative-path-to-file-1>',
  // '<relative-path-to-file-2>',
];

const errors = [];
const checks = [];
const blockers = [];

// ═══════════════════════════════════════════════════════════════════
// Preconditions (exit 2 if any fail)
// ═══════════════════════════════════════════════════════════════════

if (WRITE_SURFACE.length === 0) {
  blockers.push('WRITE_SURFACE is empty — implementer must declare the write surface');
}

for (const file of WRITE_SURFACE) {
  const abs = resolve(PROJECT_ROOT, file);
  if (!existsSync(abs)) {
    blockers.push(`Write surface file missing: ${file}`);
  } else {
    const stat = statSync(abs);
    if (stat.size === 0) {
      blockers.push(`Write surface file is empty: ${file}`);
    }
  }
}

if (blockers.length > 0) {
  console.error(`❌ Validator ${TASK_ID}: BLOCKED`);
  console.error(`   Task: ${TASK_TITLE}`);
  console.error(`   TDD Phase: ${TDD_PHASE}\n`);
  console.error('Blockers:');
  blockers.forEach((b) => console.error(`   - ${b}`));
  console.error('\nThese must be resolved before the task can be evaluated.');
  process.exit(2);
}

// ═══════════════════════════════════════════════════════════════════
// Scenarios
// ═══════════════════════════════════════════════════════════════════
//
// Each scenario block runs the appropriate command and asserts on the result.
// The shape mirrors a Given/When/Then in the task body:
//
//   Given: <state>      ← precondition checks above
//   When:  <action>     ← execSync block per scenario
//   Then:  <assertion>  ← assertions in the try/catch
//
// Phase-aware behavior:
//   RED:    expect the test command to fail; exit 0 if it fails as expected
//   GREEN:  expect the test command to pass; exit 0 only if all pass
//   REFACTOR: same as GREEN, no behavior change allowed
//   N/A:    composition/integration task, no RED/GREEN contract

function runTest(pattern) {
  // TODO: replace with the actual test command for this project
  // Examples:
  //   pnpm nx test <package> -- --testNamePattern="<pattern>"
  //   pnpm jest --testPathPattern=<file> -t "<pattern>"
  //   go test -run "<pattern>" ./...
  const cmd = `echo "PLACEHOLDER: implement test command for ${TASK_ID}"`;
  return execSync(cmd, { cwd: PROJECT_ROOT, encoding: 'utf8', stdio: 'pipe' });
}

// Scenario 1
// Given: <state>
// When:  <action>
// Then:  <assertion>
try {
  const out = runTest('scenario-1-pattern');
  if (TDD_PHASE === 'RED') {
    // RED: a passing test in a RED task is a bug
    errors.push('Scenario 1: test passed during RED phase — implementation may have leaked');
  } else {
    checks.push('Scenario 1: <assertion text>');
  }
} catch (e) {
  if (TDD_PHASE === 'RED') {
    // RED: test failed as expected
    checks.push('Scenario 1 (RED): test ran and failed as expected');
  } else {
    errors.push(`Scenario 1: ${e.message.split('\n')[0]}`);
  }
}

// Scenario 2
// TODO: copy the block above, replace pattern + assertion

// Scenario 3
// TODO: copy the block above, replace pattern + assertion

// ═══════════════════════════════════════════════════════════════════
// Report
// ═══════════════════════════════════════════════════════════════════

console.log(`\n📋 Validator: ${TASK_ID}`);
console.log(`   Task: ${TASK_TITLE}`);
console.log(`   TDD Phase: ${TDD_PHASE}`);
console.log(`   Write Surface: ${WRITE_SURFACE.length} file(s)\n`);

if (checks.length > 0) {
  console.log('✅ Checks passed:');
  checks.forEach((c) => console.log(`   - ${c}`));
}

if (errors.length > 0) {
  console.log('\n❌ Errors:');
  errors.forEach((e) => console.log(`   - ${e}`));
  process.exit(1);
}

console.log(`\n✅ All checks passed — task is ${TDD_PHASE === 'RED' ? 'RED (expected failures)' : 'GREEN'}`);
process.exit(0);
