# Multi-Tenancy

How to serve multiple customers from one codebase without leaking data between them. Read before designing any B2B SaaS, marketplace, or workspace feature.

## Decision Tree: Isolation Level

| Need | Model |
|---|---|
| Many small tenants, fast onboarding, cost-sensitive | **Shared DB, `tenant_id` column** |
| Mid-size tenants, regulatory pressure for separation | **Schema per tenant** (Postgres schemas) |
| Large tenants, custom contracts, strict isolation | **Database per tenant** |
| Enterprise with on-prem requirement | **Stack per tenant** (separate deploy) |

Start with shared DB + `tenant_id`. Migrate to schema-per-tenant or DB-per-tenant only when measured pain (noisy neighbor, compliance, scale) justifies the operational cost.

## Shared DB with `tenant_id`

Every row carries the tenant it belongs to.

```prisma
model Order {
  id        String   @id @default(uuid())
  tenantId  String   @map("tenant_id")
  // ...
  tenant    Tenant   @relation(fields: [tenantId], references: [id])

  @@index([tenantId])
  @@index([tenantId, createdAt])    // tenant-scoped queries hit the index
}
```

### Resolve Tenant on Every Request

```ts
import { AsyncLocalStorage } from 'node:async_hooks'

export const tenantContext = new AsyncLocalStorage<{ tenantId: string }>()

export const resolveTenant: RequestHandler = async (req, _res, next) => {
  const tenantId = req.user?.tenantId
    ?? req.headers['x-tenant-id']
    ?? subdomainToTenant(req.hostname)
  if (!tenantId) throw new UnauthorizedError('Tenant required')
  tenantContext.run({ tenantId }, () => next())
}
```

Resolve from one of:

- **Authenticated user's tenant** — most common.
- **Subdomain** — `acme.example.com` → `acme`. Best UX.
- **Header** — `X-Tenant-Id`. For admin tooling.

### Enforce in the Query Layer

Manual `WHERE tenant_id = ?` everywhere is the bug magnet. Centralize.

```ts
// Wrap Prisma so every query is scoped automatically.
export function tenantScoped() {
  const { tenantId } = tenantContext.getStore() ?? {}
  if (!tenantId) throw new Error('No tenant in context')
  return prisma.$extends({
    query: {
      $allModels: {
        async $allOperations({ args, query, model }) {
          if (TENANT_SCOPED_MODELS.has(model)) {
            args.where = { ...args.where, tenantId }
            if (args.data && !('tenantId' in args.data)) args.data.tenantId = tenantId
          }
          return query(args)
        },
      },
    },
  })
}
```

Now every read filters by tenant; every write stamps the tenant. Bugs become impossible at the wrong layer.

### Postgres Row-Level Security (RLS)

Belt-and-braces: tell the database itself to enforce the rule.

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON orders
  FOR ALL
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
```

Set the session variable per request:

```ts
await prisma.$executeRaw`SET LOCAL app.tenant_id = ${tenantId}::text`
```

If application code forgets the `WHERE`, the DB still refuses. Critical defense for shared-DB models.

## Schema Per Tenant

Each tenant gets a Postgres schema (`tenant_acme`, `tenant_globex`); tables exist within. One DB connection, many schemas.

### Migrate

```ts
await prisma.$executeRawUnsafe(`CREATE SCHEMA "tenant_${slug}"`)
// Run migrations against the new schema
```

Application sets `search_path` per request:

```ts
await prisma.$executeRaw`SET LOCAL search_path TO ${`tenant_${slug}`}, public`
```

### Trade-offs

- **Pros**: clean isolation; backup/restore per tenant; easier compliance.
- **Cons**: migrations run N times (one per tenant); schema drift between tenants if a migration fails on one; harder cross-tenant analytics.

Cap practical tenant count around 500–1000. Past that, migration time and connection limits dominate.

## Database Per Tenant

Each tenant has its own database (or its own RDS instance).

### When to Use

- Regulated industries with explicit "no shared storage" rules.
- Tenants paying enough to justify the cost.
- Large per-tenant data volumes.

### Architecture

A **tenant directory** (small global DB) maps tenant ID → connection string. Application pulls the right connection per request.

```ts
const tenantPools = new Map<string, PrismaClient>()

function getClient(tenantId: string) {
  if (!tenantPools.has(tenantId)) {
    const { databaseUrl } = await directory.findTenant(tenantId)
    tenantPools.set(tenantId, new PrismaClient({ datasourceUrl: databaseUrl }))
  }
  return tenantPools.get(tenantId)!
}
```

Cap the pool. Don't keep 10,000 Prisma clients alive — LRU-evict idle tenants.

## Preventing Data Leakage

The single biggest risk in any multi-tenant system. Defense in depth.

### Rules

- **Tenant scope at the data layer**, not in routes. Routes forget; centralized middleware doesn't.
- **RLS as a backstop** when on Postgres. Even if app code is wrong, DB refuses.
- **Code review checklist**: any new query touches `tenant_id`? New table needs a `tenant_id`?
- **Tests** that exercise cross-tenant boundaries — try to read tenant B's data while authenticated as tenant A. Assert 403.
- **Audit logs** record `tenantId` on every action.
- **Never include `tenantId` in URLs as the sole authorization**. URLs leak via referrers, logs, screenshots.

### Common Leak Surfaces

- **Background jobs** — the worker doesn't have a request context. Pass `tenantId` in job data; set it on the worker's tenant context.
- **Webhooks from third parties** — verify the webhook payload belongs to a tenant before processing.
- **Shared caches** — Redis keys must include tenant: `tenant:${id}:user:${userId}`.
- **Full-text search indexes** — Meilisearch/Typesense index per tenant, or filter at query time on a tenant field.
- **Logs and error tracking** — Sentry events tagged with `tenantId`. Don't put PII from one tenant into a global view another customer can access.

## Tenant Switching

For users belonging to multiple tenants (consultants, agencies, super-admins):

```ts
// User selects which tenant context they're acting in
app.post('/auth/switch-tenant', requireAuth, async (req, res) => {
  const { tenantId } = req.body
  const membership = await prisma.tenantMember.findFirst({
    where: { userId: req.user.id, tenantId },
  })
  if (!membership) throw new ForbiddenError()
  // Issue a new token/session that includes the active tenant
  const token = issueAccessToken({ userId: req.user.id, tenantId, role: membership.role })
  res.cookie('accessToken', token, COOKIE_OPTS)
  res.json({ tenantId })
})
```

UI exposes the switcher prominently — banner color or workspace name visible at all times so users know which tenant they're in.

## Billing Per Tenant

```prisma
model Tenant {
  id              String   @id @default(uuid())
  slug            String   @unique
  name            String
  plan            String   // 'free', 'pro', 'enterprise'
  stripeCustomerId String? @map("stripe_customer_id")
  trialEndsAt     DateTime? @map("trial_ends_at")
  cancelledAt     DateTime? @map("cancelled_at")
}
```

### Patterns

- **Per-seat**: count active members, sync to Stripe quantity.
- **Per-usage**: meter usage (API calls, storage, jobs), report to Stripe metered billing.
- **Tiered**: plan determines feature access via a feature-flags layer.

### Plan Enforcement

```ts
export const requirePlan = (...plans: Plan[]): RequestHandler => async (req, _res, next) => {
  const tenant = await getTenant(req.user.tenantId)
  if (!plans.includes(tenant.plan)) throw new ForbiddenError('Upgrade required')
  next()
}
```

Cache the tenant in Redis (60s TTL) to avoid hitting the DB on every request.

### Trials and Suspension

- **Trial expiry** — read-only mode until billing setup; don't delete data.
- **Failed payment** — grace period (Stripe Smart Retries), banner in UI, then read-only.
- **Cancellation** — keep data for 30+ days. Export tool for the customer.

## Cross-Tenant Operations

Admin tools, internal reporting, analytics — these need to read across tenants. Three patterns:

- **Privileged super-admin role** that bypasses tenant scope (logged, audited, MFA-required).
- **Aggregated analytics DB** with `tenant_id` columns, populated by ETL — doesn't bypass app rules.
- **Per-tenant data warehouse exports** — opt-in, customer-controlled.

Never embed cross-tenant queries in the main app paths.

## Common Mistakes

- **Manual `WHERE tenant_id = ?` in every query.** One missed query = data breach. Centralize.
- **No RLS as a backstop.** Application bug becomes a leak. Belt and braces.
- **Tenant ID in URL path with no auth check.** `/api/orders?tenantId=evil-corp` returns evil-corp's data.
- **Shared Redis keys.** `user:42` collides across tenants. Always namespace.
- **Cross-tenant FKs.** A "user" row can reference a tenant they shouldn't. Hard-code the scope per association.
- **No tenant context in background jobs.** Worker queries without scope, leaks.
- **Subdomain-based tenant resolution without CORS scoping.** `*.example.com` shared cookies cross tenants.
- **Hot tenants without isolation.** One big customer's load degrades all others. Detect, throttle or migrate to dedicated infra.
- **No tenant on logs/Sentry.** Debugging requires guessing which tenant the error belongs to.
- **Hard delete on tenant cancellation.** Customer asks for export a week later, gone. Soft-delete with retention period.
- **Allowing one tenant's webhook to mutate another's data.** Always check the payload's tenant matches the URL/auth.
- **No tenant in feature flag rollouts.** A flag enabled for "10% of users" splits per-tenant in unexpected ways. Roll by tenant first.
- **Schema-per-tenant chosen at scale without planning migrations.** Schema drift across 500 tenants is a nightmare.
- **DB-per-tenant pool exhaustion.** N tenants × M instances × connection limits → DB caps. Use a pooler.
