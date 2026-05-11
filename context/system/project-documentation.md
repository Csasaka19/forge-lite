# Project Documentation

How to document a project so that a new contributor — human or AI — can be productive without asking. Read before writing a README, an ADR, or a changelog entry.

## README Structure

The README is the front door. Optimize for "someone landed here, what do they do next?"

### Required Sections, in Order

1. **Title and one-line description.** What this project is, in 15 words. Above the fold.
2. **Status badges.** CI, coverage, version, license. Quick signal of health.
3. **Quick start.** Three to five commands that get the project running locally. No prose.
4. **Prerequisites.** Node version, package manager, Docker, system libraries.
5. **Installation.** Detailed setup if quick start isn't enough — env vars, database setup, seed data.
6. **Usage.** Common commands (`npm run dev`, `npm run test`, `npm run build`) with one line each describing what they do.
7. **Architecture.** A paragraph or two on how the system is structured. Link to deeper docs (ADRs, diagrams).
8. **Project structure.** Annotated tree of top-level directories.
9. **Contributing.** Link to `CONTRIBUTING.md`. PR rules, code style, how to file issues.
10. **License.** SPDX identifier. Link to `LICENSE` file.

### Quick Start Template

```markdown
## Quick Start

\`\`\`bash
git clone git@github.com:org/repo.git
cd repo
cp .env.example .env       # fill in any required values
npm install
npm run dev                # http://localhost:3000
\`\`\`

If you get an error, see [Installation](#installation).
```

A new contributor should be able to copy-paste five lines and have it working. If they can't, fix the project, not the README.

### Architecture Section

Don't try to document everything in the README. One paragraph plus pointers:

```markdown
## Architecture

The app is a React frontend served by Vite, talking to a Hono API backed by Postgres.
Auth is JWT-based. State management is React Query for server data and Zustand for
client-only UI state.

See:
- [docs/architecture.md](docs/architecture.md) — system diagram and component breakdown
- [docs/adr/](docs/adr/) — architectural decision records
- [docs/api/](docs/api/) — API reference (generated from OpenAPI)
```

### Length

Aim for 200–400 lines. Longer means people stop reading. Move depth into `docs/`.

### Keep Examples Runnable

Every command in the README must actually work today. CI should test this — at minimum, a job that runs the quick-start sequence on a fresh checkout.

## Architectural Decision Records (ADRs)

ADRs capture _why_ a non-obvious choice was made. Future-you will want to know.

### When to Write One

Write an ADR for any decision that:

- Affects more than one component or team.
- Locks in a technology or pattern that's hard to change later (database choice, auth strategy, language runtime).
- Was contentious — multiple valid options were considered.
- Sets a precedent for future similar choices.

Don't write an ADR for:

- Routine library choices (which date formatter to use).
- Reversible local conventions (file naming inside a feature folder).
- Things already captured elsewhere (the README, a CLAUDE.md).

### Template

Store in `docs/adr/`. Filename: `NNNN-short-title.md` where `NNNN` is a zero-padded sequence number.

```markdown
# ADR 0007: Use Postgres for application database

- Status: Accepted
- Date: 2026-05-11
- Deciders: Clive, Marta

## Context

The app stores transactional data (orders, payments) and relational data
(users → orders → items). Read-heavy with occasional reporting queries.
Team has Postgres operational experience; no one has run MongoDB in prod.

## Decision

Use Postgres 16 as the primary application database, managed via
Prisma. JSON columns for occasional document-shaped data (event payloads).

## Consequences

- Transactional integrity is straightforward (foreign keys, transactions).
- Reporting queries can stay in-database for now; no separate analytics
  store needed until volume forces it.
- Team owns Postgres operations: backups, upgrades, monitoring. Acceptable
  given existing expertise.
- Future move to a managed service (RDS, Supabase) is uncomplicated.

## Alternatives Considered

- **MongoDB.** Rejected: no operational experience; transactional needs
  don't fit document model.
- **SQLite.** Rejected: planned for multi-region eventually.
- **DynamoDB.** Rejected: lock-in to AWS, harder to reason about for
  relational queries.
```

### Status Values

- **Proposed** — under discussion.
- **Accepted** — decision made, in effect.
- **Deprecated** — no longer recommended, but still in place.
- **Superseded by ADR-NNNN** — replaced by a later decision. Link both directions.

ADRs are append-only. Don't rewrite history. If a decision changes, write a new ADR that supersedes the old one.

### Index

Maintain `docs/adr/README.md` listing every ADR with its status. Most teams update it manually; tools like `adr-tools` automate.

## CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

```markdown
# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to
Semantic Versioning.

## [Unreleased]

### Added
- New `/health` endpoint for orchestrator probes.

## [1.4.0] - 2026-05-11

### Added
- Radius filter on the machine map (10/25/50/200 km).
- Operator can mark a machine as "under maintenance" from the dashboard.

### Changed
- Default pagination size raised from 20 to 50.

### Fixed
- Geolocation fallback now shows an address-search input instead of
  failing silently.

### Security
- Tightened login rate limit from 10/min to 5/min per IP.

## [1.3.0] - 2026-04-22

...
```

### Categories

In order: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**. Skip categories with no entries.

### Rules

- Newest version on top.
- `[Unreleased]` section at the very top for in-progress changes.
- Each version has a date in `YYYY-MM-DD`.
- Entries are short — one line each. Link to PRs or issues for detail.
- Write for users of the project, not for contributors. "Fixed geolocation fallback" matters; "refactored `useGeolocation` hook" probably doesn't.

### Automation

- `release-please` generates the changelog from Conventional Commits.
- `changesets` lets contributors write changelog entries in their PR; the release process collates them.
- `git-cliff` generates from commit history offline.

Pick one and let it run. Hand-edited changelogs drift.

## Inline Code Documentation

Default: **write no comments.** Identifiers should explain themselves.

### When to Comment

Write a comment when:

- The reason for the code is non-obvious (a workaround, a hidden constraint, a tricky invariant).
- A subtle gotcha would surprise the next reader.
- An external link is necessary (RFC, vendor docs, related issue).

```ts
// Geolocation can hang indefinitely on Firefox if permission was previously
// denied and the user closes the prompt without choosing.
// See https://bugzilla.mozilla.org/show_bug.cgi?id=1656032
const POSITION_TIMEOUT_MS = 5000
```

### When Not to Comment

Don't write a comment when:

- The code already says what the comment says.
- The comment describes _what_ the code does instead of _why_.
- The comment names the calling context ("used by checkout flow") — that rots.
- The comment is the entire PR description copy-pasted.

```ts
// Bad — restates the code
// Increment counter by 1
counter += 1

// Bad — describes the caller
// Called from CheckoutPage when user clicks "Pay"
function processPayment() { ... }

// Bad — tracking metadata, belongs in git
// Added 2026-03-15 by Clive for ticket FORGE-42
```

### JSDoc for Public APIs

If the code is consumed across module boundaries — library exports, public API handlers, shared utilities — write JSDoc.

```ts
/**
 * Compute the great-circle distance between two coordinates in kilometers.
 *
 * Uses the haversine formula, accurate enough for distances under a few
 * thousand km.
 *
 * @example
 * distanceKm({ lat: -1.29, lng: 36.79 }, { lat: -1.30, lng: 36.81 })
 * // => 2.45
 */
export function distanceKm(a: LatLng, b: LatLng): number {
  // ...
}
```

For internal code, types and good names are enough. Don't JSDoc every private helper.

### TODO and FIXME

- `TODO(name): <what>` — only if there's a real next step and a person who owns it.
- `FIXME(name): <what>` — known broken behavior with a workaround.
- `HACK(name): <what>` — intentionally bad solution kept temporarily.

If a TODO has been in the codebase for six months, it's not a TODO. Delete it or turn it into an issue.

## Docs-as-Code

Documentation lives in the repository, is reviewed in PRs, and is built like code.

### Principles

- **Docs in the repo.** Same versioning as code. A PR that changes behavior also changes the doc.
- **Reviewed alongside code.** CODEOWNERS routes doc changes to the relevant reviewers.
- **Generated where possible.** API reference from OpenAPI. Type docs from TypeScript. Don't hand-maintain anything a tool can produce.
- **CI builds the docs.** Broken links, broken examples, broken builds — fail the PR.

### Tooling

- **Static site generator** for public docs: Docusaurus, Astro Starlight, MkDocs, Mintlify, Nextra.
- **Diagram source in the repo.** Use Mermaid (renders in GitHub) or commit `.drawio` / `.excalidraw` source alongside exported PNG.
- **Link checker** in CI (e.g., `lychee`). Broken internal links should fail the build.
- **Spelling/style** (Vale, Alex) optional but valuable on user-facing docs.

### Layout

```
README.md                      # entry point
CONTRIBUTING.md                # contributor guide
CHANGELOG.md                   # release notes
LICENSE
docs/
├── architecture.md
├── api/                       # generated from OpenAPI
├── adr/                       # decision records
│   ├── README.md              # index
│   └── 0001-use-postgres.md
├── guides/                    # how-tos
│   ├── local-setup.md
│   └── deploy.md
└── runbooks/                  # on-call playbooks
    ├── database-restore.md
    └── incident-response.md
```

## Onboarding Documentation

A new developer should be productive in under one day. "Productive" means: environment running, first small change shipped to staging.

### Day-One Checklist

Put this in `docs/onboarding.md` or `CONTRIBUTING.md`:

```markdown
## Day One

- [ ] Clone the repo.
- [ ] Install prerequisites: Node 20, pnpm, Docker Desktop.
- [ ] Copy `.env.example` to `.env`. Ask the team for production-only values
      you actually need; defaults work otherwise.
- [ ] `pnpm install`
- [ ] `docker compose up -d`          # starts Postgres + Redis
- [ ] `pnpm db:migrate && pnpm db:seed`
- [ ] `pnpm dev`                       # http://localhost:3000
- [ ] Confirm you can log in with the seeded admin account
      (`admin@example.com` / `password`).
- [ ] Pick a `good-first-issue` from the issue tracker.
- [ ] Open your first PR.

If anything in this list fails, fix the docs or the project. Don't paper
over it — the next person hits the same wall.
```

### What Newcomers Need to Know

- **Where the code lives** (project structure).
- **How to run it** (commands).
- **How to test it** (test command, where to put new tests).
- **How to deploy** (or not — if it's auto-deployed on merge, say so).
- **Who to ask** (channels, codeowners).
- **Conventions** (commits, branches, PR template).
- **Pitfalls** (known gotchas, environment quirks, third-party service signups).

### What Newcomers Don't Need on Day One

- The full history of every decision.
- A tour of every internal package.
- The complete architecture diagram (link it; don't require reading it).

Surface what's needed _now_. Make the rest easy to find.

## Common Mistakes

- **README that hasn't been updated since project inception.** Run quick start on a fresh checkout quarterly.
- **No `.env.example`.** Newcomers don't know what to set. Always commit the example.
- **Instructions that secretly require Slack DMs.** Document the missing piece, or remove the gate.
- **ADR for every decision.** Noise drowns the important ones. Reserve for non-obvious, hard-to-reverse choices.
- **Changelog updated only at release time, by one person, from memory.** Use Conventional Commits + automation, or `changesets` per-PR.
- **Comments that explain what the code does.** Redundant and lies as the code evolves. Comment _why_.
- **Documentation in a wiki separate from the repo.** Drifts immediately. Pull it into the repo.
- **"See Confluence" with no link, or a link that 404s.** Either include the content or link directly.
- **One enormous `docs/architecture.md` that nobody reads.** Split by concern; link from README.
- **Onboarding that takes a week.** Treat that as a bug. Each blocker is something to automate or document.
- **Auto-generated docs that nobody verifies render correctly.** Build docs in CI; fail PRs on broken builds.
- **Outdated screenshots.** Either don't use screenshots (UI changes faster than docs) or regenerate from a script.
- **Writing docs only after code lands.** They drift. Write README + ADR + changelog entry _as part of_ the PR.
