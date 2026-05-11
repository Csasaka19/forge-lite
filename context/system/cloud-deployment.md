# Cloud Deployment

Hosting and infrastructure standards. Read before choosing a platform or shipping to a new environment.

## Deployment Target Decision Tree

Pick the simplest platform that meets the requirements. Don't reach for Kubernetes when Vercel ships the same outcome in ten minutes.

### Static Site + Serverless Functions

**Use: Vercel or Netlify.**

When it fits:
- Frontend is React/Next/Vite/Astro.
- Backend is light: form handlers, auth callbacks, light API routes.
- Traffic is bursty or unknown; cold starts under 1s are acceptable.

What you get: instant global CDN, preview deploys per PR, free SSL, custom domains, environment variables. Almost no infrastructure to maintain.

What you give up: long-running processes, websockets at scale, large background jobs, control over runtime.

### Full-Stack PaaS

**Use: Railway, Render, Fly.io.**

When it fits:
- You need a long-running Node/Express/Hono server.
- You need a managed Postgres/Redis alongside.
- Your traffic doesn't require fine-grained autoscaling.
- The team is 1–10 people, no dedicated infra engineer.

What you get: deploy from a Git push, managed databases, custom domains, SSL, scaling knobs, modest free tiers. Heroku-style developer experience.

What you give up: per-second cost optimization, deep AWS-specific service integrations.

### Cloud Providers (AWS / GCP / Azure)

**Use when:** you've outgrown the above. Compliance requires it. You need services not available elsewhere (specific ML APIs, large data pipelines, VPC peering with other AWS services).

Default unit on AWS:
- Container service: ECS Fargate (simpler than EKS for most teams).
- Static + CDN: S3 + CloudFront.
- Database: RDS (Postgres) or Aurora Serverless.
- Functions: Lambda.
- Networking: VPC with public + private subnets, NAT gateway only if private subnets need outbound.

Always pair AWS work with Infrastructure as Code (Terraform). The console is for inspection, not changes.

## Environment Management

Three environments per project, minimum. Each has its own database, secrets, and domain.

### Development

- Runs on the developer's laptop, usually via `docker compose up`.
- Uses local Postgres/Redis containers.
- Seeded with fake data.
- May freely break.

### Staging

- Deployed automatically from the `develop` branch.
- Backed by a real managed database (sized down).
- Mirrors production configuration. Different secrets, different domain (`staging.example.com`).
- Used for QA, integration testing, demos.
- Data is non-PII and may be reset.

### Production

- Deployed manually (with approval) from the `main` branch.
- Real users, real data.
- Smallest blast radius for changes — feature flags for risky launches.
- Backups, monitoring, alerting are mandatory.

### What Differs Between Them

| Concern | Dev | Staging | Production |
|---|---|---|---|
| Database | Local Docker | Managed, small instance | Managed, sized for load |
| Secrets | `.env` | GitHub Environment / platform secrets | Platform secrets, restricted access |
| Logging | Console | Aggregated, retained 7 days | Aggregated, retained 30+ days |
| Monitoring | None | Basic uptime | Full: uptime, errors, performance, alerts |
| Backups | None | Daily, throwaway | Hourly snapshot + daily off-region |
| Auth providers | Test apps | Test apps | Production apps |
| Email | Mailpit / dry-run | Sandbox / single domain | Real provider |
| Rate limits | Disabled | Production values | Production values |

Same code in all three. Differences come from config, never from `if (env.NODE_ENV === 'production')` branches in business logic.

## Domain and DNS

- Use a registrar that supports DNSSEC and 2FA. Cloudflare, Namecheap, Porkbun are sane choices.
- Hold the domain on an organization account, not a personal one. Personal accounts disappear when people leave.
- Set DNS records via the platform (Cloudflare DNS, Route 53). Keep registrar and DNS provider separate if you can — limits blast radius if one account is compromised.

### Records You'll Need

- `A` / `AAAA` — apex domain to IP, or `ALIAS`/`ANAME` to a platform hostname.
- `CNAME` — `www.example.com` → `example.com`, or subdomains to platform hosts.
- `MX` — mail. Set even if you don't send mail, to prevent spoofing.
- `TXT` — SPF, DKIM, DMARC for email. Verification records for platforms (Vercel, Google, etc).
- `CAA` — restricts which CAs can issue certs for your domain. Add Let's Encrypt or your provider.

### Subdomains

- `api.example.com` — backend.
- `app.example.com` — frontend (or apex with `www` redirect).
- `staging.example.com`, `api.staging.example.com` — staging.
- `status.example.com` — status page.

Cap subdomain depth at two levels. `dev.api.example.com` is fine; `dev.api.east.us.example.com` is too much.

## SSL / TLS

- **Always HTTPS.** Redirect HTTP to HTTPS at the edge.
- Use HSTS with a 1-year max-age once you're confident every subdomain is HTTPS.
- Certificates: platform-provided (Vercel, Netlify, Railway, Render, Cloudflare) or Let's Encrypt via `certbot`/`acme.sh`. Never pay for DV certificates — they're free.
- Auto-renew. Monitor expiry; an expired cert is downtime. Most platforms handle this; on raw VMs use cron + `certbot renew`.

### TLS Version

- TLS 1.2 minimum.
- TLS 1.3 preferred.
- Disable everything below 1.2 (SSLv3, TLS 1.0, TLS 1.1).

Run `https://www.ssllabs.com/ssltest/` against the domain at launch and quarterly. Target A or A+.

## CDN

Anything static — JS bundles, CSS, images, fonts — goes through a CDN.

- Vercel/Netlify include this automatically.
- For custom setups, CloudFront, Cloudflare, or Bunny CDN.

### Cache Headers

- **Immutable assets** (hashed filenames like `app.a1b2c3.js`): `Cache-Control: public, max-age=31536000, immutable`. One year, never revalidate.
- **HTML**: `Cache-Control: no-cache` or short max-age with `must-revalidate`. HTML references the hashed assets, so it must always be fresh.
- **API responses**: usually `Cache-Control: no-store` for authenticated endpoints. Public read endpoints can use short caching (`max-age=60`) with care.

### Invalidation

For platform CDNs, deploys invalidate automatically. For CloudFront and similar, issue an invalidation as a post-deploy step. Don't rely on TTL expiry to ship a hotfix.

## Monitoring and Alerting

Three layers, all required for production.

### Uptime Monitoring

- External HTTP checks against `/health` from multiple regions.
- 1-minute frequency for production.
- Alert on 2 consecutive failures.
- Free options: Better Stack (formerly Better Uptime), UptimeRobot, Hetrix.

### Error Tracking

- **Sentry** (or equivalent: Rollbar, Bugsnag). Both frontend and backend.
- Capture unhandled exceptions, unhandled promise rejections, and user-facing errors.
- Tag events with environment, release SHA, user ID (anonymized).
- Configure source maps so stack traces show real code, not minified.

```ts
import * as Sentry from '@sentry/node'

Sentry.init({
  dsn: env.SENTRY_DSN,
  environment: env.NODE_ENV,
  release: env.GIT_SHA,
  tracesSampleRate: 0.1,    // 10% of transactions
})
```

Set up alerts: new error type, error rate spike, regression of resolved error.

### Performance

- **Web Vitals** for the frontend: LCP, INP, CLS. Use `web-vitals` library, send to analytics (Vercel Analytics, Plausible, or custom).
- **Server traces** for APIs: p50/p95/p99 latency per endpoint. Sentry, OpenTelemetry, or platform-native (Datadog, New Relic).
- Set SLO targets and alert on burn rate (e.g., 99% of requests under 500ms).

### What to Alert On

- Production outage (uptime check fails).
- Error rate above baseline by 3× for 5+ minutes.
- New high-severity Sentry issue (first occurrence of a previously unseen error).
- Database CPU > 80% sustained 10 minutes.
- Disk > 80% on any production volume.
- Failed deploy.
- Certificate expiry within 14 days.

**Don't** alert on every individual error or every spike — alert fatigue kills response quality. Tune until alerts are rare and meaningful.

## Cost Management

Cloud bills surprise you the first time. They shouldn't surprise you the second time.

### Billing Alerts

- Set a monthly budget alert at 50%, 80%, 100%, 120% of expected spend.
- Route alerts to a channel a human reads.
- Tag every resource with `project` and `environment`. Cost reports group by tag.

### Monthly Review

- Pull the previous month's bill. Identify the top 5 line items.
- For each, ask: is this expected? Is it growing? Can it be smaller?
- Common surprises: NAT gateway egress, S3 PUT requests, Lambda log retention, idle RDS instances, abandoned snapshots.

### Right-Sizing

- Start small. Scale up when load demands it, not preemptively.
- For databases, monitor CPU, IOPS, connections. Scale up before you hit 70% sustained.
- For compute, autoscale on CPU or request rate. Don't over-provision baseline.
- Reserved instances / savings plans for steady production workloads (1-year commit usually 30–50% cheaper).

### Switch Off What You're Not Using

- Spin down staging overnight if no one's testing — Railway, Render, and EC2 instances all support scheduling.
- Delete old snapshots, unused load balancers, abandoned S3 buckets. Each costs a small amount, but the small amounts add up.

## Backup Strategy

If you've never restored a backup, you don't have backups.

### Database Backups

- **Automated snapshots** at minimum daily for production. Hourly for high-write systems.
- **Point-in-time recovery (PITR)** enabled — RDS, Aurora, Cloud SQL, Supabase all support this. Recovery to any second in the retention window.
- **Off-region copy** of weekly snapshots — protects against regional failure.
- Retention: 30 days minimum, longer if compliance demands.

### Backup Testing

Schedule a quarterly restore drill:

1. Spin up a fresh instance from yesterday's snapshot.
2. Verify a sample of records.
3. Document time-to-restore.
4. Tear down.

If you've never done this, do it before the end of the next sprint.

### What to Back Up Besides the Database

- User-uploaded files (S3 with versioning + cross-region replication).
- Configuration in external systems (Auth0 tenant export, Stripe products).
- Secrets (in a separate, audited backup vault — not on the same provider as the primary).

### Restore Procedure

Document in the repo's `RUNBOOK.md`:

```markdown
## Restore database from backup

1. Identify the snapshot ID in the AWS console (Snapshots tab on the RDS instance).
2. Create a new instance from the snapshot.
3. Update DATABASE_URL secret in production environment.
4. Restart the app.
5. Verify with `curl https://api.example.com/health` and a manual spot check.
6. Decommission the old instance after 24 hours of stable operation.
```

When the page fires at 3 a.m., this is the only thing the on-call person reads.

## Infrastructure as Code

Anything beyond a single platform's UI clicks should be in code.

### When You Need It

- More than one environment with non-trivial infra.
- More than one engineer touching infrastructure.
- Compliance or audit requirements ("show me how this was provisioned").
- Anything you couldn't recreate from memory in an outage.

### Tooling

- **Terraform** — default. Vast provider ecosystem (AWS, GCP, Cloudflare, GitHub, Vercel).
- **Pulumi** — same idea, code in TypeScript/Go/Python instead of HCL. Good if the team prefers a real programming language.
- **CloudFormation / AWS CDK** — AWS-only. CDK is reasonable if you're committed to AWS.

### Layout

```
infra/
├── modules/              # reusable modules
│   ├── postgres/
│   └── ecs-service/
├── environments/
│   ├── staging/
│   │   ├── main.tf
│   │   └── terraform.tfvars
│   └── production/
│       ├── main.tf
│       └── terraform.tfvars
└── README.md
```

### State

- Store Terraform state in a remote backend (S3 + DynamoDB lock, or Terraform Cloud).
- Never commit `terraform.tfstate` to git — it contains secrets.
- One state file per environment. Don't mix staging and production state.

### Apply Through CI

`terraform apply` runs from CI, not from a laptop:

```yaml
- run: terraform init
- run: terraform plan -out=tfplan
- name: Approval
  uses: trstringer/manual-approval@v1
- run: terraform apply tfplan
```

Manual approvals on production changes. Plans are reviewed in PRs.

## Common Mistakes

- **Picking AWS for a 3-person project.** Vercel + Supabase ships in a day; AWS takes a week. Use AWS when its specifics matter, not by default.
- **Same database across environments.** Staging tests against production data → eventual disaster. Separate everything.
- **No HTTPS redirect.** "We'll add it later" → search engines indexing the HTTP version → traffic loss.
- **No backups, or backups that have never been restored.** A backup you can't restore from is decoration. Test quarterly.
- **No billing alerts.** $5,000 surprise bill from a runaway log group or open S3 bucket egress.
- **Manual changes in the cloud console.** Drift from IaC. Either codify the change or revert it.
- **Production secrets in a teammate's personal account.** Use organization-level vaults with audit logs.
- **Monitoring everything, alerting on everything.** Alert fatigue → ignored real alerts. Alert only on what requires human action now.
- **Free-tier instance for production database.** Auto-pauses, throttles, and corrupts on cold restarts. Pay for production.
- **No disaster recovery plan.** Region goes down, panic ensues, mistakes follow. Document the steps before you need them.
- **One environment.** "We deploy straight to prod." Stops working past one developer. Spin up staging immediately.
- **Wildcard SSL certs everywhere.** A leak compromises every subdomain. Use specific certs unless the platform issues wildcards by default.
- **Public S3 buckets.** Default-deny, then grant access explicitly. Many leaks start with `--acl public-read` that wasn't supposed to stay.
