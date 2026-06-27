# Monorepo Toolchain Harness Pattern

Proven June 8, 2026 during the Casita Media harness setup. A complete
toolchain-enforcement stack that makes agent-produced code safe to merge.

## Architecture

Six layered ESLint configs + TypeScript strict + Husky pre-commit + commitlint:

```
eslint.config.mjs                    ← root: composes base + secrets
├── eslint.config.base.mjs           ← strictTypeChecked + Nx boundaries + imports
├── eslint.config.web.mjs            ← React + JSX + a11y + Tailwind
├── eslint.config.mobile.mjs         ← React Native + NativeWind
├── eslint.config.test.mjs           ← Jest + Testing Library
├── eslint.config.storybook.mjs      ← Storybook exports
├── eslint.config.e2e.mjs            ← Playwright
└── eslint.config.secret.mjs         ← no-secrets (API key detection)
```

## ESLint Flat Config (v9) Composition Pattern

Each package picks its layers:

```js
// packages/ui/eslint.config.mjs — mobile package
import base from '../../eslint.config.base.mjs';
import mobile from '../../eslint.config.mobile.mjs';
import secret from '../../eslint.config.secret.mjs';
export default [...base, ...mobile, ...secret];
```

```js
// apps/storybook-next/eslint.config.mjs — web app
import base from '../../eslint.config.base.mjs';
import web from '../../eslint.config.web.mjs';
import storybook from '../../eslint.config.storybook.mjs';
import secret from '../../eslint.config.secret.mjs';
export default [...base, ...web, ...storybook, ...secret];
```

## TypeScript Strict Mode (tsconfig.base.json)

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "forceConsistentCasingInFileNames": true,
    "verbatimModuleSyntax": true,
    "noFallthroughCasesInSwitch": true,
    "noImplicitOverride": true,
    "noImplicitReturns": true
  }
}
```

Per-package tsconfigs extend `tsconfig.base.json` and add overrides only when
needed (e.g., Storybook, e2e, and test configs).

## Husky + lint-staged

`.husky/pre-commit`:
```bash
pnpm lint-staged
```

Root `package.json`:
```json
{
  "scripts": {
    "precommit": "pnpm lint-staged"
  },
  "lint-staged": {
    "*.{ts,tsx}": ["eslint --fix"]
  }
}
```

## commitlint (Conventional Commits)

Wired into the Husky `commit-msg` hook. Enforces:
- `feat:` new features
- `fix:` bug fixes
- `chore:` maintenance
- `docs:` documentation
- `refactor:` code restructuring
- `test:` test additions/changes

## Nx Module Boundaries

```json
{
  "@nx/enforce-module-boundaries": ["error", {
    "depConstraints": [
      { "sourceTag": "type:app", "onlyDependOnLibsWithTags": ["type:lib", "type:e2e"] },
      { "sourceTag": "type:lib", "onlyDependOnLibsWithTags": ["type:lib"] },
      { "sourceTag": "type:e2e", "onlyDependOnLibsWithTags": ["type:app", "type:lib"] },
      { "sourceTag": "scope:web", "onlyDependOnLibsWithTags": ["scope:shared", "scope:web"] },
      { "sourceTag": "scope:mobile", "onlyDependOnLibsWithTags": ["scope:shared", "scope:mobile"] },
      { "sourceTag": "scope:shared", "onlyDependOnLibsWithTags": ["scope:shared"] }
    ]
  }]
}
```

Each package's `package.json` gets `nx.tags` matching its type and scope.

## Key Learnings from the Session

### ESLint Flat Config Plugin Resolution

ESLint v9 flat config imports plugins as objects, not strings. The common
pitfall is plugins not resolving because:
1. **Wrong CWD** — Nx runs ESLint from the package directory, not the root.
   Running `nx lint <pkg>` vs `npx eslint` from the package dir can give
   different results. Debug with `--print-config` from the correct directory.
2. **pnpm store path** — pnpm's strict store isolation can cause resolution
   failures if the store-dir is non-standard. Pass `--store-dir` explicitly
   or set `pnpm config set store-dir` globally.
3. **Plugin version mismatch** — Some plugins changed export format for flat
   config compatibility. Check `package.json` `main` field and verify the
   default export is an object with a `rules` key.

### Auto-Approval for Edits on cmux

On cmux surfaces, option "2" in the edit approval dialog enables auto-accept
for all edits during the session (equivalent to Shift+Tab on native Claude
Code TUI). Once active (green `⏵⏵` icon), file writes proceed without
gates. Bash commands still require individual approval unless in print mode.

### Pre-existing vs Introduced Issues

When setting up strict tooling on an existing codebase, expect pre-existing
violations. The Nx `externalDependency` warnings (for `rollup`, `next`, etc.)
are standard in Nx workspaces and not caused by the harness itself. Sonnet
identified these correctly and worked around them by running `tsc --noEmit`
directly on individual packages.

## Files Produced

```
eslint.config.mjs                     ← root composition
eslint.config.base.mjs                ← strictTypeChecked + Nx + imports
eslint.config.web.mjs                 ← React + JSX + a11y + Tailwind
eslint.config.mobile.mjs              ← React Native + NativeWind
eslint.config.test.mjs                ← Jest + Testing Library
eslint.config.storybook.mjs           ← Storybook
eslint.config.e2e.mjs                 ← Playwright
eslint.config.secret.mjs              ← no-secrets
packages/*/eslint.config.mjs          ← per-package composition
.husky/pre-commit                     ← lint-staged
.husky/commit-msg                     ← commitlint
nx.json                               ← module boundaries + eslint plugin
tsconfig.base.json                    ← strict mode
```

## Agent Instructions for Future Harness Setups

When setting up a new monorepo toolchain harness:

1. **Start with ATDD spec** — Define green gates before writing configs:
   - tsc --noEmit passes on all packages
   - ESLint runs against all files without crashing
   - Pre-commit hook runs lint-staged
   - Commit message format is enforced
   - Nx module boundaries are configured

2. **Assign to Sonnet** — This is law-making work. Sonnet's "chug" quality
   (staying on problems until solved) is essential for debugging the inevitable
   flat config resolution and plugin compatibility issues.

3. **Install phase** — Install ALL plugins upfront with one command to avoid
   repeated install/approve/install cycles:
   ```bash
   pnpm add -D -w typescript-eslint @nx/eslint @nx/eslint-plugin \
     eslint-plugin-import eslint-plugin-react eslint-plugin-react-native \
     eslint-plugin-react-hooks eslint-plugin-react-refresh \
     eslint-plugin-jsx-a11y eslint-plugin-tailwindcss eslint-plugin-storybook \
     eslint-plugin-jest eslint-plugin-jest-dom eslint-plugin-testing-library \
     eslint-plugin-playwright eslint-plugin-n eslint-plugin-promise \
     eslint-plugin-no-secrets eslint-plugin-perfectionist eslint-plugin-unicorn \
     eslint-config-prettier lint-staged @commitlint/cli @commitlint/config-conventional
   ```

4. **Gate management on cmux** — Watch for approval prompts and respond:
   - Bash commands: send '1' to approve, '2' to approve + don't ask again
   - Edit dialogs: send '2' to enable auto-accept for the session
   - Monitor with `cmux read-screen` looking for `❯` (waiting) vs `✢ Musing…` (working)

5. **Verification order** — After configs are written:
   - `tsc --noEmit` on the strictest package first
   - `npx eslint --print-config <file>` to confirm plugins load
   - `nx lint <pkg>` per package
   - `nx run-many -t lint --all` for workspace-wide
   - Git add + commit to verify pre-commit hook fires

6. **Final diff review** — Always `git diff --stat` before declaring done.
   Revert scope drift (Sonnet sometimes fixes things beyond the ATDD spec).
