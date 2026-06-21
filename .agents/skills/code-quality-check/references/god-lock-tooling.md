# GOD-LOCK Tooling: Biome vs ESLint

## The Split

GOD-LOCK uses **Biome** as the primary linting and formatting tool across the mothership and all Battlefields. ESLint is secondary, reserved for module-boundary enforcement and framework-specific rules.

| Concern | Primary Tool | Secondary Tool |
|---------|-------------|----------------|
| Formatting | Biome | — |
| General linting (unused vars, style, imports) | Biome | — |
| Cross-module dependency constraints | ESLint (`@nx/enforce-module-boundaries`) | — |
| Framework-specific rules (Next.js, React) | ESLint | — |
| Staged-file auto-fix | Biome (`lint-staged`) | — |

## The Plugin

A custom Nx plugin `@god-lock/biome` lives at `plugins/biome/`. It registers per-project targets when a `biome.json` exists at the project root:

| Target | Command |
|--------|---------|
| `biome` | `pnpm exec biome check --write {projectRoot}` |
| `biome-check` | `pnpm exec biome check {projectRoot}` |
| `biome-format` | `pnpm exec biome format --write {projectRoot}` |
| `biome-ci` | `pnpm exec biome ci {projectRoot}` |

The plugin is registered in `nx.json` with these target names.

## Root Config

The workspace root `biome.json`:
- Has `$schema` and `vcs.enabled: true`
- Defines the workspace law (formatter rules, linter rules, ignore patterns)
- Is consumed by `lint-staged`: `"*": "pnpm exec biome check --write --no-errors-on-unmatched"`
- **Does NOT generate Nx targets** because the plugin skips root (`root === "."`)

## Package-Level Config

Every new package/library MUST have its own `biome.json` to participate in the Biome pipeline. If the root config has `$schema` (which marks it as a root config in Biome 2.x), nested configs must explicitly opt out:

```json
{
  "root": false
}
```

Without `"root": false`, Biome exits with:

```
× Found a nested root configuration, but there's already a root configuration.
```

A package-level config may also extend or override specific settings:

```json
{
  "root": false,
  "files": {
    "includes": ["**"]
  }
}
```

## ESLint Remaining Role

ESLint is still registered in `nx.json` via `@nx/eslint/plugin` with `targetName: "lint"`. Its job:

1. `@nx/enforce-module-boundaries` — `depConstraints` by `scope:*` tags
2. Framework plugins: `@next/eslint-plugin-next`, `eslint-plugin-react`, etc.

When auditing code quality, always run **Biome first**, then ESLint. Do not treat `pnpm nx lint` as the primary lint gate.

## Quick Verification

```bash
# Primary gate
pnpm nx biome-check <project>

# Secondary gate
pnpm nx lint <project>

# Direct biome invocation (when Nx target not yet registered)
pnpm exec biome check <projectRoot>
```

## Common Mistakes

- Creating `eslint.config.mjs` but forgetting `biome.json` — the package silently skips the primary lint pipeline.
- Running `pnpm nx lint` as the only lint check — misses formatting and general lint violations.
- Adding `$schema` to a package-level `biome.json` without `"root": false` — triggers the nested-root error.
