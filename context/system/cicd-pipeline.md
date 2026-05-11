# CI/CD Pipeline

Continuous integration and deployment standards. GitHub Actions is the default platform. Read before adding a new workflow or changing branching.

## Pipeline Stages

Every change flows through these stages, in order. A failure at any stage halts the pipeline.

1. **Lint** — ESLint, Prettier check. Fast feedback, must pass before anything else.
2. **Type check** — `tsc --noEmit`. Catches type errors before tests run.
3. **Test** — unit + integration tests. Required for merge.
4. **Build** — produce deployable artifact. Fails if lint/test passed but build doesn't.
5. **Deploy to staging** — automatic on merge to `develop`.
6. **Smoke test** — hit critical endpoints against staging. Fail loud if regressed.
7. **Deploy to production** — manual approval, then auto from `main`.
8. **Post-deploy verification** — health check, error rate watch for 5–15 minutes.

Never skip stages. Never let a stage be "advisory" — if it can fail, it must block.

## GitHub Actions Conventions

### File Layout

```
.github/
├── workflows/
│   ├── ci.yml              # runs on every PR and push
│   ├── deploy-staging.yml  # runs on push to develop
│   ├── deploy-prod.yml     # runs on push to main, with approval
│   └── nightly.yml         # cron, e.g. security scans
├── actions/
│   └── setup-node/         # reusable composite action
│       └── action.yml
└── CODEOWNERS
```

One workflow per purpose. Don't combine "CI for PRs" and "deploy to prod" in the same file.

### Reusable Workflows

For logic shared across repos (setup, deploy, notify), extract to a reusable workflow:

```yaml
# .github/workflows/_setup.yml
on:
  workflow_call:
    inputs:
      node-version:
        type: string
        default: '20'

jobs:
  setup:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ inputs.node-version }}
          cache: npm
      - run: npm ci
```

Call from another workflow:

```yaml
jobs:
  ci:
    uses: ./.github/workflows/_setup.yml
```

### Pinning

Pin third-party actions to a full SHA, not a tag. Tags are mutable; SHAs are not.

```yaml
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11  # v4.1.1
```

Renovate keeps these updated automatically.

### Standard CI Workflow

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main, develop]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm' }
      - run: npm ci
      - run: npm run lint

  typecheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm' }
      - run: npm ci
      - run: npx tsc --noEmit

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm' }
      - run: npm ci
      - run: npm run test -- --coverage
      - uses: actions/upload-artifact@v4
        with: { name: coverage, path: coverage/ }

  build:
    needs: [lint, typecheck, test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm' }
      - run: npm ci
      - run: npm run build
      - uses: actions/upload-artifact@v4
        with:
          name: build-${{ github.sha }}
          path: dist/
          retention-days: 14
```

Always use `concurrency` to cancel superseded runs on the same branch. Saves money and shortens feedback loops.

## Branch Strategy

- `main` — production. Every commit on `main` is deployable. Protected branch.
- `develop` — integration. Merges from feature branches happen here. Auto-deploys to staging.
- `feature/<short-name>` — feature work. Branch off `develop`, merge back via PR.
- `fix/<short-name>` — bug fixes targeting `develop`.
- `hotfix/<short-name>` — urgent fixes targeting `main`. Merge to `main`, then back-merge to `develop`.

For small projects without a separate staging environment, GitHub Flow (just `main` + feature branches) is fine. Document which you use.

### Protected Branch Rules

Both `main` and `develop`:

- Require PR before merge.
- Require status checks: `lint`, `typecheck`, `test`, `build`.
- Require branches to be up to date before merge.
- Require at least 1 approving review.
- Dismiss stale approvals when new commits are pushed.
- Restrict who can push directly (admin only, used only for emergencies).

`main` only:

- Require linear history (no merge commits).
- Require signed commits.

## Pull Request Rules

- One logical change per PR. If you can't describe it in a sentence, split it.
- Title follows commit convention: `feat: add machine map`, `fix: handle offline geolocation`.
- Description includes: what changed, why, how to verify, screenshots for UI.
- All CI checks must pass.
- At least 1 review approval.
- Squash merge by default — keeps `main` and `develop` history linear and readable.
- Delete the branch after merge (auto-enable in repo settings).

### Draft PRs

Open a draft PR early to share work in progress. Don't waste a reviewer's time on a half-finished PR — mark it ready for review when CI is green and you'd stake your name on it.

## Automated Testing Gates

These must pass for a PR to be mergeable. None are optional.

- **Lint** — ESLint with zero errors. Warnings are reviewed but don't block.
- **Type check** — `tsc --noEmit` with zero errors.
- **Unit tests** — all pass. Coverage threshold (default 70%) enforced by CI. Drop the threshold per-project only with team agreement.
- **Build** — production build completes without error.
- **Format** — `prettier --check` if Prettier is configured.

Optional but encouraged:

- **Visual regression** for UI-heavy projects.
- **Bundle size budget** to catch accidental dependency bloat.
- **Dependency audit** — `npm audit --audit-level=high` fails CI.

## Build Artifacts

What CI produces and how to handle it.

- **What to save**: the deployable output. For a Vite frontend, `dist/`. For a Node service, the compiled `dist/` or a Docker image.
- **Naming**: include the commit SHA. `build-${{ github.sha }}` or image tag `myapp:${{ github.sha }}`.
- **Retention**: 14 days for ordinary builds, 90 days for release tags. Older artifacts can be rebuilt from the commit.
- **Source of truth**: the artifact built once in CI is the artifact deployed everywhere. Never rebuild for production — same bytes that passed tests must reach prod.

## Deployment Strategy

### Staging

- Trigger: push to `develop`.
- Action: build, then deploy the artifact to the staging environment.
- No manual approval — speed matters here.
- Notification: post to team channel with the commit, deployer, and URL.

```yaml
name: Deploy Staging
on:
  push:
    branches: [develop]

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm' }
      - run: npm ci
      - run: npm run build
      - name: Deploy
        run: ./scripts/deploy.sh staging
        env:
          DEPLOY_TOKEN: ${{ secrets.STAGING_DEPLOY_TOKEN }}
```

### Production

- Trigger: push to `main` (typically from merging a release PR).
- **Manual approval required.** Configure GitHub Environments with required reviewers.
- Action: download the staging-validated artifact, deploy, run smoke tests.
- Notification: post deployment start and result.

```yaml
name: Deploy Production
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://app.example.com
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/deploy.sh production
        env:
          DEPLOY_TOKEN: ${{ secrets.PROD_DEPLOY_TOKEN }}
      - run: ./scripts/smoke-test.sh https://app.example.com
```

### Smoke Tests After Deploy

After every deploy, hit critical paths and fail loud if they regress.

- Health endpoint returns 200.
- Login flow works end-to-end against a test account.
- Critical read endpoint returns sane data.

Keep smoke tests under 60 seconds. They run on every deploy.

## Rollback Procedure

Decide before you need it. Two strategies, pick one per project:

### Revert and Redeploy

Best for: simple deploys, single-artifact apps.

1. `git revert <bad-commit>` on `main`.
2. Push. The deploy workflow runs and ships the reverted state.
3. Verify with smoke tests.

### Redeploy Previous Artifact

Best for: containerized apps, anything with versioned image tags.

1. Identify last-known-good tag from deployment log.
2. Trigger `deploy-prod` workflow with that tag as input (`workflow_dispatch` with inputs).
3. Verify.
4. Open a follow-up PR to revert the bad commit on `main`.

Document the rollback command in the repo's `README.md` so it's findable at 2 a.m.

## Secrets in CI

- Store all secrets in GitHub Secrets (repo or organization scope). Never commit them. Never put them in workflow YAML.
- Reference via `${{ secrets.NAME }}`. GitHub redacts them in logs automatically — but don't `echo` them, just to be safe.
- Scope minimally: use environment-scoped secrets so production credentials aren't readable from staging workflows.
- Rotate quarterly and after every personnel change. Track rotation dates.
- For long-lived deploy keys, prefer OIDC federation (e.g., AWS, GCP) so CI gets short-lived credentials and no long-lived secret exists.

```yaml
- name: Configure AWS
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789012:role/github-deploy
    aws-region: us-east-1
```

Never log values that could contain secrets. Avoid `env: | jq` or `printenv` in steps — those dump everything.

## Common Mistakes

- **Skipping CI on "trivial" PRs.** The PR isn't trivial; the assumption is wrong half the time.
- **Mutating tags on third-party actions.** `actions/checkout@v4` will silently change. Pin to SHA.
- **Different artifact built for staging vs prod.** Promotes the wrong bytes to prod. Build once, deploy many times.
- **No `concurrency` block.** Old runs continue after a force-push, burning minutes and confusing dashboards.
- **Long-running tests with no parallelization.** Shard tests across runners.
- **Deploying directly from a developer's machine.** Untraceable. Always deploy from CI.
- **Manual production deploys "just this once."** Becomes "always" within a quarter. Resist.
- **Storing secrets in repo variables instead of secrets.** Variables aren't redacted in logs.
- **No environment protection rules.** Anyone with write access can deploy to prod. Add required reviewers.
- **Squash-merging without rewriting the commit message.** "Update PR #123" tells future-you nothing. Edit the squash commit body to the actual change description.
- **Force-pushing to a shared branch.** Loses other people's work. Protect with branch rules.
- **Letting `develop` and `main` drift for weeks.** Cut releases regularly. Long-lived divergence makes merges painful.
