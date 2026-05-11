# Git Workflow

Branching, commits, and merging conventions. Read before opening a PR or pushing a new branch.

## Branch Naming

Every branch has a prefix that signals intent. Reviewers and CI use the prefix; pick the right one.

- `feature/<short-name>` — new functionality. `feature/machine-map`, `feature/operator-dashboard`.
- `fix/<short-name>` — bug fix. `fix/offline-geolocation-fallback`.
- `chore/<short-name>` — maintenance with no behavior change. `chore/bump-deps`, `chore/eslint-config`.
- `refactor/<short-name>` — internal restructuring, no behavior change. `refactor/extract-machine-service`.
- `docs/<short-name>` — documentation only. `docs/api-getting-started`.
- `test/<short-name>` — adding or fixing tests. `test/order-flow-integration`.
- `hotfix/<short-name>` — urgent production fix branched from `main`. `hotfix/payment-double-charge`.

Rules:

- Lowercase, kebab-case, no spaces.
- Keep names under 50 characters. The slug is for humans skimming a branch list, not a description.
- Include the issue number when one exists: `feature/123-machine-map`.
- Never include personal initials or dates in branch names — the prefix and slug carry the meaning.

## Commit Message Format

Use [Conventional Commits](https://www.conventionalcommits.org/). Tools and humans both parse them.

```
<type>(<scope>)?: <subject>

<body>

<footer>
```

### Types

- `feat` — new feature visible to users.
- `fix` — bug fix.
- `docs` — documentation only.
- `style` — formatting, missing semicolons, no code change.
- `refactor` — code change that neither fixes a bug nor adds a feature.
- `perf` — performance improvement.
- `test` — adding or fixing tests.
- `build` — build system or external dependencies (npm, Docker).
- `ci` — CI configuration.
- `chore` — anything else that doesn't modify src or test files.
- `revert` — reverts a prior commit.

### Scope (optional)

The area of the codebase touched. `feat(map)`, `fix(auth)`, `chore(deps)`. Skip if the change is broad or there's no obvious scope.

### Subject

- Imperative mood: "add" not "added" or "adds." Read as: "if applied, this commit will _add_..."
- Lowercase first letter.
- No trailing period.
- Under 72 characters.

### Body (optional)

Explains _why_, not what. The diff shows what. Wrap at 72 columns. Separate from subject with a blank line.

### Footer (optional)

- `Closes #123`, `Fixes #45` — link issues.
- `BREAKING CHANGE: <description>` — flags a breaking API change. Also bump the major version.
- `Co-Authored-By: Name <email>` — credit pair/mob programmers.

### Examples

```
feat(map): add radius filter with 10/25/50/200 km options

Users with sparse machine coverage need to widen the search beyond the
default 10 km. Buttons sit above the list and persist selection in the URL
query string for shareable links.

Closes #87
```

```
fix(auth): reject expired refresh tokens

The token verifier was checking signature but not `exp`. A leaked
refresh token would have worked indefinitely.

BREAKING CHANGE: clients holding refresh tokens older than 7 days must
re-authenticate.
```

```
chore(deps): bump react to 19.0.1
```

## Commit Granularity

One logical change per commit, not one file per commit and not one feature per commit.

### Right size

- Touches one concern (a function, a route, a config).
- Compiles and passes tests on its own.
- Can be reverted independently without dragging unrelated work.
- Reviewable in under 5 minutes.

### Too small

- "fix typo," "fix another typo," "fix one more typo" — squash before pushing.
- One file changed at a time when the change spans multiple files. Group them.

### Too big

- "implement entire dashboard" — split into commits per page, per service, per migration.
- Mixing a refactor and a feature in one commit. Land the refactor first, then the feature on top.

### Rebasing Before Push

Clean up local history with `git rebase -i` _before_ pushing to a shared branch. Once pushed for review, prefer adding new commits and letting the squash-merge collapse them at PR time.

```bash
git rebase -i origin/develop    # squash WIP commits, reorder, reword
```

Never rebase a branch others have pulled. If you must, communicate first.

## Merge Strategy

### Feature Branches → `develop` (or `main` in GitHub Flow)

**Squash merge.** Each PR becomes one commit on the target branch. Keeps history linear and readable.

- Edit the squash commit message before merging — the default is the PR title plus a list of WIP commits, which is rarely the right narrative.
- The squashed message follows Conventional Commits format.

### Release Branches → `main`

**Regular merge (with merge commit).** Preserves the release branch's history so you can see the set of features included in each release.

```bash
git checkout main
git merge --no-ff release/1.4.0
```

### Hotfix Branches → `main` and Back

1. Branch from `main`: `git checkout -b hotfix/critical-bug main`.
2. Fix, PR, squash-merge to `main`.
3. Deploy.
4. Merge `main` back into `develop` so the fix isn't lost on the next release.

### Never

- `--force-push` to a shared branch (`main`, `develop`, anyone's open PR you don't own).
- Merge without a PR.
- Bypass branch protection. If you find yourself wanting to, the protection is probably correct.

## Branch Protection Rules

Configure on the host (GitHub, GitLab). Apply to `main` always, `develop` whenever it exists.

Required for both `main` and `develop`:

- Require a pull request before merging.
- Require at least 1 approving review.
- Dismiss stale approvals when new commits are pushed.
- Require status checks: `lint`, `typecheck`, `test`, `build`.
- Require branches to be up to date before merging.
- Restrict who can push directly (admins only, used only for emergencies).
- Block force pushes.
- Block deletions.

Additional for `main`:

- Require linear history (forces squash or rebase merges).
- Require signed commits if the team has GPG/SSH signing set up.
- Limit deployment workflow access through `Environments`.

## Tagging for Releases

Use [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`.

- **MAJOR** — incompatible API change.
- **MINOR** — backwards-compatible feature.
- **PATCH** — backwards-compatible bug fix.

Tag releases on `main`:

```bash
git tag -a v1.4.0 -m "Release 1.4.0"
git push origin v1.4.0
```

- Always use annotated tags (`-a`). Lightweight tags lack metadata.
- Prefix with `v`: `v1.4.0`, not `1.4.0`. Conventional and easier to grep.
- Tag the merge commit on `main`, not an intermediate commit.
- For pre-releases: `v1.4.0-rc.1`, `v1.4.0-beta.2`. Semver-compatible.

Automate tagging where possible:

- `release-please` (Google) generates release PRs from Conventional Commits.
- `changesets` (npm-friendly) works well for monorepos.
- `semantic-release` for fully automated releases.

## .gitignore Conventions

A baseline `.gitignore` for every project:

```
# Dependencies
node_modules/
.pnp
.pnp.js

# Build output
dist/
build/
out/
.next/
.nuxt/
.svelte-kit/

# Environment
.env
.env.local
.env.*.local
!.env.example

# Logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*

# Test artifacts
coverage/
.nyc_output/

# IDE and editor
.vscode/
!.vscode/settings.json
!.vscode/extensions.json
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Misc
.cache/
.parcel-cache/
.turbo/
```

Rules:

- Always commit `.env.example`. Always ignore actual `.env` files.
- Never commit `node_modules/`. If someone does, remove with `git rm -r --cached node_modules` and add the line.
- Tool-specific files (`.vscode/`, `.idea/`) are ignored by default but allow shared config (`settings.json`, `extensions.json`) with explicit un-ignores.
- Build output is ignored. The artifact comes from CI, not from a developer's machine.

If a sensitive file was committed, removing it from `.gitignore` is not enough. The history still contains it. Rotate the leaked secret immediately, then use `git filter-repo` or `bfg-repo-cleaner` to scrub history, then force-push (coordinated with the team).

## Handling Large Files

Git is bad at binaries. The repo grows forever, clones get slow, diffs are meaningless.

Default rule: **don't commit binaries.**

- Compiled artifacts → CI builds them.
- Images and fonts used by the app → commit only when small (< 100 KB) and stable. Larger or churning → object storage + reference by URL.
- Large datasets → not in git. Use object storage (S3, GCS) with a manifest in the repo.
- Documentation diagrams → commit the source (`.drawio`, `.excalidraw`) and the exported PNG/SVG if it's reasonably small.

### Git LFS

When binaries genuinely need version control (design source files, ML model weights, audio assets), use Git LFS:

```bash
git lfs install
git lfs track "*.psd" "*.fbx" "*.weights"
git add .gitattributes
```

Caveats:

- LFS isn't free at scale. Check provider quotas before adding hundreds of GBs.
- Some clones (CI, deploy scripts) may need explicit LFS hooks. Test the deploy path.
- Don't add LFS to an existing repo retroactively without coordinating — old commits still reference inline blobs.

## Monorepo vs Polyrepo

### Polyrepo (default)

Each service or library has its own repo. Independent lifecycle, independent CI, independent deploys.

Pick polyrepo when:

- Services are owned by different teams.
- They have different release cadences and don't share much code.
- One service's CI shouldn't slow down another's.
- You're a small team and tooling overhead matters more than cross-cutting refactors.

### Monorepo

All services and shared packages in one repo. Shared types, shared CI, atomic cross-service changes.

Pick monorepo when:

- Multiple services share types or utilities and you want atomic updates.
- You frequently change two repos in lockstep ("update API and client at the same time").
- You're willing to invest in tooling (Nx, Turborepo, pnpm workspaces) to keep builds fast.

### When in Doubt

Start polyrepo. Splitting a monorepo later is feasible; merging polyrepos later is more painful. Don't pre-optimize for a structure you don't need yet.

If you do go monorepo, decide upfront:

- Workspace manager (pnpm workspaces / npm workspaces / Yarn).
- Build orchestrator (Turborepo, Nx).
- Versioning strategy (independent versions per package via Changesets, or single version via Lerna).
- CI strategy that runs only what changed (Turborepo's `--filter`, Nx's `affected`).

## Common Mistakes

- **`git push --force` to a shared branch.** Rewrites history under collaborators. Use `--force-with-lease` if you must, after coordinating.
- **Committing `node_modules/`, `.env`, or build output.** Bloats history, leaks secrets.
- **Commits like "wip," "fix," "more fixes," "actually fix it this time."** Squash before pushing for review.
- **One giant commit at the end of a feature.** Impossible to review or revert pieces. Commit as you go.
- **Mixing refactor and feature in one commit.** Reviewers can't tell which line changed behavior and which didn't.
- **Branch named `clive-stuff` or `temp-3`.** Useless to anyone scanning the branch list.
- **Tagging mid-branch instead of on `main`.** The tag walks history into commits that aren't released.
- **Lightweight tags without `-a`.** No metadata, no message, won't show up cleanly in tooling.
- **Skipping the issue link in the PR description.** Future-you has no idea why this change shipped.
- **Force-pushing to main "just to fix a typo in the commit message."** Use a new commit, or accept the typo. History is immutable once shared.
- **Letting a feature branch live for two months.** Merge conflicts and review fatigue compound. Land work in days, not weeks.
- **Committing secrets, then "removing" them in a follow-up commit.** They're still in history. Rotate the secret, then scrub.
- **Merging a PR with red CI.** The protection rules exist to prevent this. Don't override them without a documented reason.
