# Secrets Management

How to handle credentials, API keys, and signing material. Read before adding a new integration or rotating a key.

## Never Commit Secrets

A committed secret is a leaked secret. Even after deletion, it remains in git history; even after history rewrite, it remains in clones, mirrors, and caches.

### The Baseline Setup

Every project:

1. `.env` — local-only file with real values. **Never committed.**
2. `.env.example` — same keys, placeholder values. **Always committed.**
3. `.gitignore` lists `.env` and `.env.*` (except `.env.example`).

```
# .gitignore
.env
.env.local
.env.*.local
!.env.example
```

```
# .env.example
DATABASE_URL=postgresql://user:password@localhost:5432/dbname
JWT_SECRET=replace-with-32-byte-random-value
STRIPE_SECRET_KEY=sk_test_...
SENTRY_DSN=
```

`.env.example` documents what's needed. Teammates copy it to `.env` and fill in values.

### Validate at Boot

Fail fast if required env vars are missing or malformed:

```ts
import { z } from 'zod'
import 'dotenv/config'

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']),
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
  STRIPE_SECRET_KEY: z.string().startsWith('sk_'),
  SENTRY_DSN: z.string().url().optional(),
})

export const env = envSchema.parse(process.env)
```

A missing secret should crash the process at start, not at the moment it's first used. Surface failures during deploy, not at 3 a.m. when traffic hits the dependent code path.

### If a Secret Leaks

The fix is **rotation**, not deletion from history. Scrubbing history doesn't help if the value was ever public.

1. **Rotate immediately.** Revoke the leaked key, issue a new one.
2. **Deploy the new value.** Update production secrets, redeploy.
3. **Investigate access logs** for the leaked credential. Look for unfamiliar usage.
4. **Scrub history** with `git filter-repo` if the leak was recent and small. Don't rely on this alone.
5. **Document the incident.** Even if no harm came of it. Patterns inform process.

## CI/CD Secrets

CI needs secrets too: deploy keys, registry credentials, third-party tokens for integration tests. Store them where they belong, not in workflow YAML.

### GitHub Secrets

- **Repository secrets** for project-specific values.
- **Organization secrets** for values shared across repos (registry tokens, common service accounts). Scope to specific repos.
- **Environment secrets** for environment-specific values (staging vs production deploy keys). Pair with Environment protection rules.

```yaml
- name: Deploy
  env:
    DEPLOY_TOKEN: ${{ secrets.PROD_DEPLOY_TOKEN }}
  run: ./scripts/deploy.sh
```

GitHub redacts secret values from logs automatically — but the redaction is naive (substring match). Don't print secrets to logs even when you "know" they'll be redacted. Don't dump full environments (`printenv`, `env | jq`).

### Environment-Specific Secrets

Use GitHub Environments to isolate:

- `staging` environment holds staging credentials.
- `production` environment holds production credentials, with required reviewers and a wait timer.

A workflow targeting the staging environment cannot read production secrets. This is the protection — without it, anyone with write access to the repo can exfiltrate production keys via a malicious PR.

### Prefer OIDC over Long-Lived Keys

For cloud deploys (AWS, GCP, Azure), use **OIDC federation** instead of long-lived access keys. The CI run gets a short-lived token, scoped to the role, with no secret in GitHub at all.

```yaml
permissions:
  id-token: write
  contents: read

- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789012:role/github-deploy
    aws-region: us-east-1
```

No long-lived key means nothing to rotate, nothing to leak, no shared secret to steal.

## Rotation Schedule

All credentials rotate. The question is how often.

| Credential | Default Cadence |
|---|---|
| Database passwords | Quarterly |
| API keys (third-party) | Quarterly or per provider recommendation |
| JWT signing secrets | Semi-annually |
| TLS certificates | Per CA renewal cycle (90 days for Let's Encrypt, auto-renewed) |
| OAuth client secrets | Annually |
| SSH deploy keys | Annually |
| CI/CD tokens | Quarterly |
| Encryption keys (data at rest) | Annually, with key versioning |

### Rotate Immediately

- After any suspected leak.
- When someone with access leaves the team.
- After a compromise of any system that held the credential.
- When you change providers or upgrade auth schemes.

### Rotation Process

1. **Generate the new credential.** Don't reuse old ones.
2. **Add the new credential alongside the old.** Two-key window — both work briefly.
3. **Deploy code/config that uses the new credential.**
4. **Verify** by usage logs that no callers are using the old credential.
5. **Revoke the old credential.**

If your provider doesn't support overlapping keys, plan a short window. Communicate. Don't rotate at peak traffic.

### Track Rotation

Maintain a list (in a private repo or secret manager) of every credential and the next rotation date. Calendar reminders. Treat overdue rotations as a security incident.

## Secret Scanning

Block secrets at the boundary, not after the fact.

### GitHub Secret Scanning

Enable on every repository. Detects committed secrets and alerts (and can revoke for some providers — AWS, Stripe, etc.).

- **Push protection** blocks the push if a secret is detected. Enable it.
- Private repos require GitHub Advanced Security for full coverage; the basic provider-partner detection works on all repos.

### Pre-Commit Hooks

Run a local scanner before commits land. `gitleaks` or `detect-secrets`:

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

Or as a Husky pre-commit hook:

```sh
#!/bin/sh
gitleaks protect --staged --redact
```

Local hooks aren't a substitute for server-side scanning — they're easy to skip with `--no-verify`. Layer both.

### CI Scanning

Scan the full repo on every PR:

```yaml
- uses: gitleaks/gitleaks-action@v2
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

Fail the build on any finding. False positives get added to an allowlist with justification.

## Third-Party Secret Managers

For anything beyond a small team or simple project, move out of `.env` files into a dedicated secrets manager.

### When to Use One

- More than one production instance (multi-region, multi-cluster).
- Compliance requirements (SOC 2, HIPAA, PCI).
- Frequent rotation needed.
- Multiple services sharing the same secret.
- Auditability of who accessed what, when.

### Options

- **HashiCorp Vault** — full-featured, self-hosted or HCP. Pricing scales. Best for complex setups.
- **AWS Secrets Manager** — AWS-native. Automatic rotation for RDS, RDS-compatible. Integrates with IAM.
- **GCP Secret Manager** — same idea, GCP-native.
- **Doppler** — DX-focused, multi-cloud. Easy to start with.
- **Infisical** — open source. Good middle ground.
- **1Password / Bitwarden Secrets Manager** — works well for small teams.

Pick one based on where your infrastructure lives. Don't fragment — one manager for the whole team.

### How They Fit In

The secret manager is the source of truth. Application config pulls at startup (or via sidecar) — never stores plaintext on disk.

```ts
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager'

const client = new SecretsManagerClient({ region: 'us-east-1' })

export async function loadSecrets() {
  const res = await client.send(new GetSecretValueCommand({ SecretId: 'prod/app/main' }))
  return JSON.parse(res.SecretString!)
}
```

For Kubernetes, use the External Secrets Operator or platform-native CSI drivers — secrets land as files or env vars in pods, never on disk.

### Caching

Secret manager calls cost money and add latency. Cache in memory at process start, refresh on a timer or on `SIGHUP`. Don't fetch per-request.

## Principle of Least Privilege

Every credential should grant the minimum access needed. Then less than that.

### API Keys

When creating a key for a third-party service:

- Scope to the smallest permission set. Stripe restricted keys (`rk_...`) over secret keys (`sk_...`) when possible.
- Scope to the smallest resource set. Single bucket, single project, single API.
- Set IP restrictions if the service supports them.
- Set expiry if the service supports it.

### Cloud IAM

- One role per service. Don't reuse roles across unrelated workloads.
- Permissions written explicitly, not via managed policies that grant more than needed.
- Never give a service `*:*` permission "for development." Use a separate dev policy.
- Use IAM Access Analyzer (or equivalent) to find over-permissive policies.

### Service Accounts

- One service account per service, per environment.
- Service account keys never used by humans. Humans authenticate as themselves.
- Disable key creation in production projects unless explicitly required. Prefer workload identity / IRSA / OIDC.

### Database Users

- Separate users for app, migrations, and read-only analytics.
- Application user has no DDL permissions — can't create or drop tables. Migrations run as a separate, elevated user.
- Read-only user for dashboards and reporting. No write, no DDL, no ability to read sensitive tables.

```sql
-- App user
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
REVOKE CREATE ON SCHEMA public FROM app_user;

-- Read-only analytics user
GRANT SELECT ON ALL TABLES IN SCHEMA public TO analytics_user;
```

### Tokens for Humans

Personal access tokens (GitHub, npm, cloud providers):

- Smallest scope that works.
- Shortest expiry the workflow allows.
- Stored in a password manager, not in `.bashrc` or `~/.netrc` unprotected.

## Common Mistakes

- **`.env` committed because "it's just dev values."** Dev values often grant access to dev infrastructure that connects to other systems.
- **Same `JWT_SECRET` across environments.** A token issued in dev works in prod. Use different values.
- **Long-lived AWS access keys for CI.** Steal once, exfiltrate forever. Use OIDC.
- **Reading secrets from `process.env` deep in business logic.** Centralize in one `env.ts` so the surface is auditable.
- **Logging `console.log({ ...config })` and capturing secrets.** Redact at the logger. Never trust manual avoidance.
- **One root admin token used everywhere.** Compromise one service, lose everything. One token per service.
- **Rotation done "when we get around to it."** Calendar it. Track the date. Treat overdue rotations as a finding.
- **Storing the new key alongside the old in `.env` "for safety," forgetting to delete the old.** Both work; the old one is now twice as valuable to an attacker.
- **Pre-commit hook installed but skipped via `--no-verify` regularly.** Add CI-side scanning. Block at the boundary.
- **Production secrets in Slack DMs.** Use a password manager with shared vaults.
- **Service account keys printed to terminal during setup.** Terminal history, IDE buffers, screen-shares — all leak vectors.
- **Granting a service `AdministratorAccess` because "it's easier."** Easier today, breach tomorrow. Spend the hour writing the policy.
- **Vault deployed but only used for some secrets, others still in `.env`.** Fragmented. One source of truth.
- **Secret manager fetched on every request instead of cached.** Latency, cost, and a hard dependency on the manager being up.
