#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs';

const usage = 'Usage: node directive.gen.mjs <input.json | -> [output.md]\nReads JSON from a file or stdin; writes Markdown to stdout or a new file.\nGherkin must be patched by the author before worker delivery.';

try {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === '--help') {
    console.log(usage);
  } else {
    if (args.length < 1 || args.length > 2) throw new Error(usage);
    const data = JSON.parse(readFileSync(args[0] === '-' ? 0 : args[0], 'utf8'));
    if (!data || typeof data !== 'object' || Array.isArray(data)) {
      throw new Error('Input must be a JSON object.');
    }
    const template = readFileSync(new URL('../templates/DIRECTIVE.md', import.meta.url), 'utf8');
    const fields = [...new Set([...template.matchAll(/\{\{(\w+)\}\}/g)].map(match => match[1]))];
    for (const key of Object.keys(data)) {
      if (!fields.includes(key)) throw new Error(`Unknown parameter: ${key}. Gherkin is authored separately.`);
    }
    const values = { scope: 'none', breakingChange: 'no', ...data };
    for (const field of fields) {
      if (typeof values[field] !== 'string' || !values[field].trim()) {
        throw new Error(`Parameter ${field} must be a nonempty string.`);
      }
      if (/\{\{|GHERKIN_REQUIRED/.test(values[field])) {
        throw new Error(`Parameter ${field} contains a reserved template marker.`);
      }
    }
    if (!['fix', 'feat', 'refactor', 'perf', 'test', 'docs', 'build', 'ci', 'chore', 'revert'].includes(values.class)) {
      throw new Error('Parameter class must be a Conventional Commit type listed in the template.');
    }
    for (const field of ['id', 'title', 'scope', 'breakingChange']) {
      if (/[\r\n]/.test(values[field])) throw new Error(`Parameter ${field} must be a single line.`);
    }
    const result = template.replace(/\{\{(\w+)\}\}/g, (_, field) => values[field]);
    if (args[1]) writeFileSync(args[1], result, { flag: 'wx' });
    else process.stdout.write(result);
  }
} catch (error) {
  console.error(`directive.gen: ${error.message}`);
  process.exitCode = 1;
}
