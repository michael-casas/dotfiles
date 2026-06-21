#!/usr/bin/env node
// Validator for task W2.A.1.1: zodToPostgresType maps Zod primitives (RED phase exemplar)
//
// Contract:
//   Exit 0  → task is GREEN
//   Exit 1  → task is RED, errors printed to stdout
//   Exit 2  → task is BLOCKED, preconditions not met
//
// Wired as: pnpm agent:validate:W2.A.1.1
// Lives at: .agent/tools/validate-W2.A.1.1.mjs

import { existsSync, statSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { resolve } from 'node:path';

const PROJECT_ROOT = resolve(process.cwd());
const TASK_ID = 'W2.A.1.1';
const TASK_TITLE = 'zodToPostgresType maps Zod primitives to Postgres column types';
const TDD_PHASE = 'RED';
const WRITE_SURFACE = [
  'packages/zod-pg-mapper/src/lib/zod-mapping/zod-mapping.test.ts',
];

const errors = [];
const checks = [];
const blockers = [];

// ═══════════════════════════════════════════════════════════════════
// Preconditions (exit 2 if any fail)
// ═══════════════════════════════════════════════════════════════════

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

// In RED phase, the implementation file MUST NOT exist yet
const implFile = 'packages/zod-pg-mapper/src/lib/zod-mapping/zod-mapping.ts';
if (existsSync(resolve(PROJECT_ROOT, implFile))) {
  // Not a blocker, but worth warning
  errors.push(`RED phase warning: implementation file ${implFile} already exists — fix should be in test only`);
}

if (blockers.length > 0) {
  console.error(`❌ Validator ${TASK_ID}: BLOCKED`);
  console.error(`   Task: ${TASK_TITLE}`);
  console.error(`   TDD Phase: ${TDD_PHASE}\n`);
  console.error('Blockers:');
  blockers.forEach((b) => console.error(`   - ${b}`));
  process.exit(2);
}

// ═══════════════════════════════════════════════════════════════════
// Scenario 1: Primitive types map to Postgres columns
// ═══════════════════════════════════════════════════════════════════

function runScenario1() {
  const cmd = `pnpm nx test zod-pg-mapper -- --testPathPattern=zod-mapping --testNamePattern="primitive types map"`;
  return execSync(cmd, { cwd: PROJECT_ROOT, encoding: 'utf8', stdio: 'pipe' });
}

try {
  runScenario1();
  if (TDD_PHASE === 'RED') {
    errors.push('Scenario 1: test PASSED during RED phase — implementation has leaked into the test task');
  } else {
    checks.push('Scenario 1: primitive types map to Postgres columns');
  }
} catch (e) {
  const out = (e.stdout || '') + (e.stderr || '');
  if (TDD_PHASE === 'RED') {
    if (out.includes('FAIL') || out.includes('failed') || out.includes('Error')) {
      checks.push('Scenario 1 (RED): test ran and failed as expected');
    } else {
      errors.push(`Scenario 1 (RED): test command ran but did not produce expected failure. Output:\n${out.slice(0, 500)}`);
    }
  } else {
    errors.push(`Scenario 1 (GREEN): test should pass but failed: ${out.split('\n')[0]}`);
  }
}

// ═══════════════════════════════════════════════════════════════════
// Scenario 2: Optional and nullable unwrap
// ═══════════════════════════════════════════════════════════════════

function runScenario2() {
  const cmd = `pnpm nx test zod-pg-mapper -- --testPathPattern=zod-mapping --testNamePattern="optional.*nullable.*unwrap"`;
  return execSync(cmd, { cwd: PROJECT_ROOT, encoding: 'utf8', stdio: 'pipe' });
}

try {
  runScenario2();
  if (TDD_PHASE === 'RED') {
    errors.push('Scenario 2: test PASSED during RED phase — implementation has leaked');
  } else {
    checks.push('Scenario 2: optional and nullable unwrap');
  }
} catch (e) {
  const out = (e.stdout || '') + (e.stderr || '');
  if (TDD_PHASE === 'RED') {
    if (out.includes('FAIL') || out.includes('failed') || out.includes('Error')) {
      checks.push('Scenario 2 (RED): test ran and failed as expected');
    } else {
      errors.push(`Scenario 2 (RED): expected failure but got: ${out.slice(0, 500)}`);
    }
  } else {
    errors.push(`Scenario 2 (GREEN): test should pass but failed: ${out.split('\n')[0]}`);
  }
}

// ═══════════════════════════════════════════════════════════════════
// Scenario 3: Unmapped type throws
// ═══════════════════════════════════════════════════════════════════

function runScenario3() {
  const cmd = `pnpm nx test zod-pg-mapper -- --testPathPattern=zod-mapping --testNamePattern="unmapped.*throws"`;
  return execSync(cmd, { cwd: PROJECT_ROOT, encoding: 'utf8', stdio: 'pipe' });
}

try {
  runScenario3();
  if (TDD_PHASE === 'RED') {
    errors.push('Scenario 3: test PASSED during RED phase — implementation has leaked');
  } else {
    checks.push('Scenario 3: unmapped type throws');
  }
} catch (e) {
  const out = (e.stdout || '') + (e.stderr || '');
  if (TDD_PHASE === 'RED') {
    if (out.includes('FAIL') || out.includes('failed') || out.includes('Error')) {
      checks.push('Scenario 3 (RED): test ran and failed as expected');
    } else {
      errors.push(`Scenario 3 (RED): expected failure but got: ${out.slice(0, 500)}`);
    }
  } else {
    errors.push(`Scenario 3 (GREEN): test should pass but failed: ${out.split('\n')[0]}`);
  }
}

// ═══════════════════════════════════════════════════════════════════
// Lint check (always required)
// ═══════════════════════════════════════════════════════════════════

try {
  execSync('pnpm nx lint zod-pg-mapper', { cwd: PROJECT_ROOT, encoding: 'utf8', stdio: 'pipe' });
  checks.push('Lint: pnpm nx lint zod-pg-mapper exits 0');
} catch (e) {
  errors.push(`Lint failed: ${(e.stderr || e.message).split('\n')[0]}`);
}

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
