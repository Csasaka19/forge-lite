# Monorepos & Packages

How to organize multi-package codebases. Read before creating a second repo, splitting a package, or adopting Turborepo.

## Decision Tree: Monorepo vs Polyrepo

Pick polyrepo unless one of the monorepo signals fires.

### Pick a Monorepo When

- **You ship a frontend and a backend that share types or schemas.** Atomic changes across both matter.
- **You have two or more apps** (web + mobile, customer + admin) consuming the same UI library.
- **A change frequently spans services** ("update the API and the client at the same time").
- **You publish multiple npm packages** with related release cycles.
- **You want one CI, one lint config, one Prettier config, one tsconfig base.**

### Stick with Polyrepo When

- **One app, one team, one deploy.** Adding a monorepo adds tooling for nothing.
- **Services have wildly different lifecycles.** A library updated quarterly and a service updated daily don't belong together.
- **Teams have hard ownership boundaries.** Repo-level access control is simpler than path-based.
- **CI cost matters more than dev DX.** A monorepo's CI matrix can grow expensive without good caching.

### Cost Awareness

A monorepo trades **per-repo overhead** (one CI per repo, one config per repo) for **shared tooling overhead** (Turborepo, workspace protocol, pipeline definitions). It only pays off past 2–3 packages or 2+ apps. Below that, polyrepo wins.

## Stack: pnpm + Turborepo

**pnpm workspaces** for package management. **Turborepo** for build/test orchestration with caching.

```bash
npm install -g pnpm
pnpm create turbo@latest my-monorepo
```

Why this combo:

- **pnpm** — fastest install, strict dependency resolution, no phantom dependencies (unlike npm/yarn classic).
- **Turborepo** — incremental builds, content-addressable cache, runs only what changed.

Alternatives: **Nx** (richer plugins, steeper learning curve), **Bazel** (Google-scale, overkill for most), **Lerna** (legacy, use only for existing setups).

## Repo Layout

```
.
├── apps/
│   ├── web/                  # React + Vite customer-facing
│   ├── admin/                # React + Vite admin dashboard
│   ├── mobile/               # Expo / React Native
│   └── api/                  # Hono / Express backend
├── packages/
│   ├── ui/                   # shared component library
│   ├── types/                # shared TypeScript types + Zod schemas
│   ├── utils/                # shared helpers (date, money, validation)
│   ├── config/
│   │   ├── eslint/           # shared ESLint config
│   │   ├── typescript/       # shared tsconfig bases
│   │   └── tailwind/         # shared Tailwind preset
│   └── api-client/           # generated/typed API SDK
├── pnpm-workspace.yaml
├── turbo.json
├── tsconfig.base.json
└── package.json
```

### Naming

- **`apps/`** for deployables (frontend apps, backend services, CLIs).
- **`packages/`** for shared code.
- **`@org/`** scope on every internal package name. `@org/ui`, `@org/types`. Prevents collisions with public registry names.

## pnpm Workspace Config

```yaml
# pnpm-workspace.yaml
packages:
  - "apps/*"
  - "packages/*"
  - "packages/config/*"
```

```json
// root package.json
{
  "name": "my-monorepo",
  "private": true,
  "packageManager": "pnpm@9.0.0",
  "scripts": {
    "build": "turbo run build",
    "dev": "turbo run dev",
    "lint": "turbo run lint",
    "test": "turbo run test",
    "typecheck": "turbo run typecheck"
  },
  "devDependencies": {
    "turbo": "^2.0.0",
    "typescript": "^5.5.0"
  }
}
```

## Internal Package Conventions

### No Build Step (Prefer Source Imports)

Internal packages **don't build to `dist/`**. Apps consume their source directly via TypeScript paths. This is the single biggest DX win in a monorepo — saves the rebuild step on every change.

```json
// packages/ui/package.json
{
  "name": "@org/ui",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "exports": {
    ".": "./src/index.ts",
    "./button": "./src/button.tsx",
    "./styles.css": "./src/styles.css"
  },
  "scripts": {
    "lint": "eslint src",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "react": "catalog:",
    "@org/types": "workspace:*"
  }
}
```

The consuming app needs to be able to compile TS — for Vite/Next/Expo, that's the default.

For packages **published to npm**, you do need a build step. Use `tsup` or `tsc` to emit `dist/`, and point `exports` at the built files.

### TypeScript Paths

`tsconfig.base.json` at the root:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "jsx": "react-jsx",
    "skipLibCheck": true,
    "esModuleInterop": true,
    "isolatedModules": true,
    "resolveJsonModule": true
  }
}
```

Each app extends and adds paths only when needed (with `exports` field, paths are usually unnecessary):

```json
// apps/web/tsconfig.json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "paths": { "@/*": ["./src/*"] }
  },
  "include": ["src"]
}
```

### Workspace Protocol

Internal deps use `workspace:*`. pnpm resolves these to the local package; on publish, it rewrites to a real version.

```json
"dependencies": {
  "@org/ui": "workspace:*",
  "@org/types": "workspace:*"
}
```

### Catalog (pnpm 9+)

Pin shared dependency versions in one place:

```yaml
# pnpm-workspace.yaml
catalog:
  react: ^19.0.0
  react-dom: ^19.0.0
  typescript: ^5.5.0
  zod: ^3.23.0
```

Packages reference `"react": "catalog:"` instead of pinning individually. Bump once, all packages move together.

## Turborepo Pipeline

`turbo.json`:

```json
{
  "$schema": "https://turbo.build/schema.json",
  "ui": "tui",
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**", "!.next/cache/**"],
      "inputs": ["src/**", "package.json", "tsconfig.json"]
    },
    "lint": {
      "dependsOn": ["^lint"],
      "inputs": ["src/**", ".eslintrc*", "eslint.config.*"]
    },
    "test": {
      "dependsOn": ["^build"],
      "outputs": ["coverage/**"]
    },
    "typecheck": {
      "dependsOn": ["^typecheck"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    }
  }
}
```

### Reading the Config

- **`dependsOn: ["^build"]`** — `^` means "this task in upstream packages first." Build dependencies before building me.
- **`outputs`** — what Turbo caches. List every directory the task produces.
- **`inputs`** — what changes invalidate the cache. Default is all files; narrow when you know better.
- **`cache: false`** — for long-running tasks like `dev`.
- **`persistent: true`** — Turbo doesn't wait for it to exit before considering it "started."

### Run Tasks

```bash
pnpm turbo build                       # all packages
pnpm turbo build --filter=@org/web     # one package + its deps
pnpm turbo build --filter='...@org/ui' # everything that depends on ui
pnpm turbo lint test --parallel        # multiple tasks in parallel
```

## CI/CD with Turbo Cache

The big win: only rebuild what changed.

### GitHub Actions

```yaml
name: CI
on: [pull_request, push]

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 2 }            # Turbo needs the previous commit for diff
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'pnpm' }
      - run: pnpm install --frozen-lockfile
      - run: pnpm turbo lint test typecheck build
        env:
          TURBO_TOKEN: ${{ secrets.TURBO_TOKEN }}
          TURBO_TEAM: ${{ vars.TURBO_TEAM }}
```

### Remote Cache

Turbo Remote Cache (free for OSS, paid for orgs) shares the cache across CI runs and developers. The first PR builds; every subsequent run reuses results.

Self-hosted alternatives: `ducktors/turborepo-remote-cache` (S3-backed).

### Affected Builds

```bash
pnpm turbo build --filter='[origin/main]'
```

Builds only packages with changed files since `origin/main`. Combine with conditional deploy steps so unchanged apps don't redeploy.

## Shared Component Library

`packages/ui/` is the most common shared package. Conventions:

```
packages/ui/
├── src/
│   ├── index.ts
│   ├── button.tsx
│   ├── card.tsx
│   ├── input.tsx
│   ├── lib/
│   │   └── cn.ts                # className helper
│   └── styles.css               # Tailwind base + tokens
├── package.json
└── tsconfig.json
```

### Tailwind

Share a preset, not a config. Each app extends the preset:

```ts
// packages/config/tailwind/preset.ts
export default {
  theme: { extend: { /* tokens */ } },
  plugins: [],
} satisfies Partial<import('tailwindcss').Config>

// apps/web/tailwind.config.ts (Tailwind v3) or v4 @config directive
import preset from '@org/config-tailwind'
export default { presets: [preset], content: ['./src/**/*.{ts,tsx}', '../../packages/ui/src/**/*.{ts,tsx}'] }
```

**Critical**: `content` paths must include `packages/ui/src`. Otherwise Tailwind doesn't see the classes used in shared components and purges them.

### Storybook

Storybook is great for design-system development; **optional for Phase 1.** Set it up once the component library has > 10 components and external consumers. Premature Storybook adds maintenance overhead.

When you do add it, put it at `packages/ui/.storybook/` and serve from `pnpm --filter @org/ui storybook`.

## Dependency Management

### Hoisting

pnpm hoists deduplicable deps to the root by default. Override per-package as needed in `.npmrc`:

```ini
public-hoist-pattern[]=*eslint*
public-hoist-pattern[]=*prettier*
```

This makes shared tools available everywhere without explicit installs.

### Phantom Dependencies

pnpm prevents accidentally importing transitive deps. If `apps/web` imports `lodash` without listing it in `package.json`, pnpm errors. This is a feature — fix the package.json.

### Updating

```bash
pnpm update --recursive --latest          # all packages, latest within semver
pnpm update --recursive --interactive     # pick what to update
pnpm dlx npm-check-updates -u --workspaces # cross-package version sync
```

Renovate or Dependabot for automated PRs. Configure to group minor and patch updates.

## Versioning & Release

Two patterns:

- **Fixed**: all packages share one version. Lerna's old default. Simpler when everything releases together.
- **Independent**: each package has its own version. Better when consumers depend on specific packages.

**Changesets** is the modern tool:

```bash
pnpm dlx changeset                    # contributors write a changeset per PR
pnpm dlx changeset version            # bump versions and update changelog
pnpm dlx changeset publish            # publish to npm
```

In CI, the Changesets GitHub Action opens a "Version Packages" PR aggregating pending changesets — merge it to publish.

## When NOT to Monorepo

- **Solo developer, one app.** Tooling overhead with no benefit.
- **Two services with no shared code.** Just two repos. Easier.
- **Public OSS with very different release cycles.** Polyrepo gives each its own audience and CI.
- **Mixed languages with no shared tooling.** A Go service and a React app don't benefit from being in the same repo.
- **Teams unwilling to learn Turbo/pnpm workspaces.** Forcing it produces resentment and broken caches.

If you start polyrepo and outgrow it, merging two repos with history is possible (`git filter-repo` + `git subtree`). Don't preemptively monorepo "in case."

## Common Mistakes

- **Polyrepo when the same types are duplicated across three repos.** Drift, then bugs.
- **Monorepo with no caching.** Every CI run rebuilds everything; CI minutes balloon. Add Turbo cache.
- **Building internal packages to `dist/` unnecessarily.** Slows dev. Consume source directly.
- **Tailwind missing `packages/ui/src` in `content`.** Shared components render unstyled in apps.
- **Mixed package managers (`npm install` in one app, `pnpm install` in another).** Lockfile chaos. Pick one, enforce with `packageManager` field.
- **No `private: true` on internal packages.** Risk of accidentally publishing them.
- **Versions hand-edited in every package.json.** Use a catalog (pnpm 9+) or workspace protocol.
- **Adding Storybook on day one.** Maintenance burden before the library is mature.
- **`workspace:^` instead of `workspace:*`.** Caret-style breaks when you publish. `*` resolves cleanly.
- **CI without `fetch-depth: 2`.** Turbo can't diff from main, falls back to full builds.
- **Different ESLint/TS configs per package.** Drift. Share via `packages/config`.
- **Hoisted dep used without declaring it in `package.json`.** Works in dev, breaks on isolated installs. Declare every dep you import.
- **Renaming a package without updating every `workspace:*` consumer.** Broken local resolution. Use refactor tools or grep carefully.
- **`pnpm install` in one package's directory instead of the root.** Subtle lockfile drift. Always install from root.
- **Treating Turbo as magic.** Read the cache keys when something refuses to rebuild — `outputs` or `inputs` is usually misconfigured.
