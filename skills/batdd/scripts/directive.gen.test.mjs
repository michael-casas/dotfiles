import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

test('directive CLI generates faithfully, rejects invalid input, and preserves existing output', () => {
  const script = fileURLToPath(new URL('./directive.gen.mjs', import.meta.url));
  const input = {
    id: 'DIR-001', title: 'Preserve literal input', class: 'fix',
    objective: 'Keep $& and $` literal.\nPreserve the second line.',
    currentBehavior: 'Retries duplicate records.', requiredBehavior: 'Retries return one record.',
    impact: 'Duplicate work.', context: 'Public submission flow.', repository: '/repo',
    requiredContext: 'AGENTS.md and TESTING.md', authorizedScope: 'Submission and its tests.',
    protectedBoundaries: 'Authorization policy.', baselineExceptions: 'none',
    deliveryAuthority: 'No commit, push, or merge.'
  };
  const run = (value, args = ['-']) => spawnSync(process.execPath, [script, ...args], {
    input: typeof value === 'string' ? value : JSON.stringify(value), encoding: 'utf8', cwd: tmpdir()
  });
  const generated = run(input);
  assert.equal(generated.status, 0, generated.stderr);
  assert.ok(generated.stdout.includes(input.objective));
  assert.ok(generated.stdout.includes('Scope: none\nBreaking change: no'));
  assert.equal((generated.stdout.match(/GHERKIN_REQUIRED/g) || []).length, 1);
  assert.ok(generated.stdout.includes('## Independent Review — Single Pass to Purity'));
  assert.ok(!generated.stdout.includes('{{'));
  for (const invalid of ['{', [], null, { ...input, objective: '' },
    { ...input, impact: 3 }, { ...input, class: 'Fix' },
    { ...input, gherkin: 'Feature: forbidden' }, { ...input, title: 'a\nb' },
    { ...input, objective: '{{title}}' }]) {
    const result = run(invalid);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    assert.ok(result.stderr.includes('directive.gen:'));
  }
  const dir = mkdtempSync(join(tmpdir(), 'directive-gen-'));
  try {
    const source = join(dir, 'input.json');
    const output = join(dir, 'directive.md');
    writeFileSync(source, JSON.stringify(input));
    assert.equal(run('', [source, output]).status, 0);
    assert.equal(readFileSync(output, 'utf8'), generated.stdout);
    writeFileSync(output, 'Previously patched Gherkin');
    assert.notEqual(run('', [source, output]).status, 0);
    assert.equal(readFileSync(output, 'utf8'), 'Previously patched Gherkin');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
