# Payload/admin stack grounding notes

Session-grounded context for spec generation in the AES battlefield.

## Current target binding

- `battlefields/atlantis-electrical/apps/admin` → Nx project `admin`
- `battlefields/atlantis-electrical/packages/payload` → Nx project `payload-lib`
- `packages/payload` currently exposes a thin `src/index.ts` re-export over `src/lib/payload.ts`
- `apps/admin` is a generated Next app shell with demo content and a plain root layout

## Seeds and prior art

Use `seeds/payload-seed` as annexation evidence only.

Good concepts to mine:
- Payload admin layout shape
- collection/global/config decomposition
- plugin composition
- admin authentication and preview flow
- e2e coverage around admin routes

Do not copy seed files wholesale into the battlefield.

## Why a separate admin app is required

**Not a preference — a structural constraint.** The AES battlefield has `apps/Aesgoldseed` (React Router v7). Payload v3's admin panel is Next.js-native (mounted as an `app/(payload)/` route group) and cannot be embedded in a React Router v7 app. A separate `apps/admin` (Next.js) is the only architecture that works.

Long-term: Aesgoldseed → `apps/web` (Next.js) migration is a separate annexation phase, deferred until after payload-admin-stack is stable.

## Canonical three-package battlefield

| Package | Role | Runtime | Dependency |
|---------|------|---------|------------|
| `packages/payload` | Headless contract: config, collections, types, access helpers | Payload v3 | Standalone (depends only on `payload`, `@payloadcms/db-postgres`, `@payloadcms/richtext-lexical`, `sharp`) |
| `apps/admin` | Admin portal — thin Next.js host | Next.js 16 | Depends on `packages/payload` AND `@payloadcms/next` (Next coupling only here) |
| `apps/web` | Public site — consumes Payload content via API | Next.js 16 *(post-annex)* | Consumes `packages/payload` at headless layer |

## Coupling rules

- **`@payloadcms/next` belongs ONLY in `apps/admin`.** Never in `packages/payload/payload-lib`. The payload library is a headless domain contract and must not import Next-specific code.
- `packages/payload` exposes: config builder, collection definitions, access helpers, types.
- `apps/admin` exposes: the `(payload)` route group, `withPayload` Next config, `@payload-config` tsconfig alias.
- The seam between them: `@payload-config` tsconfig alias + one npm dep on `@atlantis-electrical/payload`.
- `withPayload` Next plugin is owned by Payload upstream — treated as a black-box adapter.

## Agent north-star

Payload REST/GraphQL is mounted at known paths in `apps/admin`:
- REST: `/api/{collection-slug}`
- GraphQL: `/api/graphql`

Once stable, any agent runtime can create/edit/delete content via the Payload API. This enables the copywriting & SEO agent workflow.

## Planning constraints

- Keep the admin host as standalone/minimally coupled as Payload v3 permits.
- Prefer a thin Payload admin seam over a public web surface.
- Aesgoldseed (RRv7) → apps/web (Next.js) migration is explicitly deferred.
- Spec output should reference exact paths and current Nx identities.
- @payloadcms/next coupling is isolated to apps/admin only.
