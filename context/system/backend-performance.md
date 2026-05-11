# Backend Performance

Server-side performance standards. Read before adding a query, an endpoint, or anything that runs in a hot path.

## Database Query Optimization

The database is the most common bottleneck. Treat every query as a budget item.

### N+1 Prevention

The classic killer: one query loads N parent rows, then N more queries load their children.

```ts
// Bad — N+1
const machines = await prisma.machine.findMany()
for (const m of machines) {
  m.operator = await prisma.operator.findUnique({ where: { id: m.operatorId } })
}

// Good — single query with join
const machines = await prisma.machine.findMany({
  include: { operator: true },
})
```

Detect N+1 in development with Prisma's query logging or a tool like `prisma-query-inspector`. In production, slow-query logs + APM traces reveal them. Any endpoint executing > 10 queries to render is suspect.

### Explain Plans

For slow queries, run `EXPLAIN ANALYZE`:

```sql
EXPLAIN ANALYZE
SELECT * FROM orders WHERE machine_id = $1 AND status = 'completed'
ORDER BY created_at DESC LIMIT 50;
```

Look for:
- **Seq Scan** on a large table without a WHERE filter that uses an index — usually means you need an index.
- **Sort** in memory on large rowsets — add a covering index or reduce the rowset.
- Wildly inaccurate row estimates — statistics are stale; `ANALYZE` the table.

Run explain plans before adding indexes — confirm the index would actually be used.

### Index What You Query

- Every foreign key needs an index (Prisma does not auto-create them in all cases).
- Compose indexes match query patterns: `(status, created_at)` serves `WHERE status = ? ORDER BY created_at`.
- Partial indexes for filtered queries: `WHERE deleted_at IS NULL` should hit a partial unique index, not scan + filter.

Don't over-index. Each index slows writes and consumes disk. Drop unused indexes (`pg_stat_user_indexes`).

### Select Only What You Need

```ts
// Bad — pulls every column including a large `payload` JSON
const orders = await prisma.order.findMany()

// Good — only what the response needs
const orders = await prisma.order.findMany({
  select: { id: true, total: true, status: true, createdAt: true },
})
```

Especially important for tables with large columns (TEXT blobs, JSONB payloads, BYTEA).

### Connection Pooling

- Use a connection pool. Direct connection per request crushes the database under load.
- Prisma's default pool size is 10 — tune based on database capacity.
- For serverless (Lambda, Vercel functions), use a pooler (`pgbouncer`, Prisma Accelerate, Supabase Pooler) — function instances can outnumber DB connections fast.

```
DATABASE_URL=postgresql://user:pass@host:6432/db?connection_limit=10&pool_timeout=20
```

- Pool timeout shorter than request timeout: requests waiting for a free connection should fail fast and shed load, not pile up.
- Monitor pool saturation. Sustained queue means the pool is too small or queries are too slow.

### Pagination

Cursor-based, not offset-based, for any table beyond ~10k rows.

```ts
const orders = await prisma.order.findMany({
  where: { createdAt: { lt: cursorDate } },
  orderBy: { createdAt: 'desc' },
  take: 51,
})
const hasMore = orders.length > 50
const nextCursor = hasMore ? orders[49].createdAt.toISOString() : null
return { data: orders.slice(0, 50), nextCursor, hasMore }
```

Offset pagination at page 1000 reads page 999 worth of rows first. Cursor pagination is constant-time.

## Caching Layers

### In-Memory (Per-Process)

For data that's hot, small, and tolerable as slightly stale within one process:

```ts
import { LRUCache } from 'lru-cache'

const featureFlags = new LRUCache<string, FlagSet>({
  max: 1000,
  ttl: 60_000,   // 1 minute
})
```

Caveat: multi-process apps have N caches, all slightly inconsistent. Acceptable for low-stakes data, not for anything that must be synchronized.

### Redis (Shared)

For cache shared across processes/instances:

- Session storage.
- Hot read data (top products, leaderboards).
- Rate-limit counters.
- Memoized computations from expensive jobs.

```ts
import { Redis } from 'ioredis'

const redis = new Redis(env.REDIS_URL)

export async function getCachedMachine(id: string): Promise<Machine | null> {
  const cached = await redis.get(`machine:${id}`)
  if (cached) return JSON.parse(cached)

  const fresh = await prisma.machine.findUnique({ where: { id } })
  if (fresh) await redis.set(`machine:${id}`, JSON.stringify(fresh), 'EX', 300)
  return fresh
}
```

Invalidate on write:

```ts
await prisma.machine.update({ where: { id }, data })
await redis.del(`machine:${id}`)
```

### Cache Stampede

When a hot cache key expires, many requests hit the DB simultaneously. Solutions:

- **Stale-while-revalidate** — serve stale, refresh in background.
- **Lock the refresh** — first request to miss refreshes; others wait briefly.
- **Probabilistic refresh** — refresh probability rises as the TTL approaches expiry.

Don't ignore stampedes — they crash databases at the worst time.

### HTTP Cache Headers

Set on responses, even when there's no CDN — browsers and proxies honor them.

- **Private, authenticated**: `Cache-Control: private, no-store`.
- **Public read endpoint**, low churn: `Cache-Control: public, max-age=60, stale-while-revalidate=300`.
- Use `ETag` for conditional GETs. Server returns 304 on match.

```ts
res.set('Cache-Control', 'public, max-age=60, stale-while-revalidate=300')
res.set('ETag', `"${hash(body)}"`)
```

## Response Compression

Always compress text responses. Saves 70–90% on JSON.

```ts
import compression from 'compression'
app.use(compression())
```

Modern stack: terminate compression at the edge (CDN, load balancer) — they're better at it and offload work from the app. Most platforms (Vercel, Cloudflare, AWS ALB) compress automatically.

- Prefer **brotli** over gzip when both client and server support it. ~20% better ratio.
- Don't compress already-compressed payloads (images, videos, gzipped responses). Wastes CPU.
- Don't compress tiny responses (< 1 KB). Overhead > savings.

## Connection Management

### Database

Covered above — pool, don't open per-request.

### Outbound HTTP

Reuse connections. Node's `http`/`https` agent has keep-alive **disabled by default** in older versions — verify and enable:

```ts
import { Agent } from 'undici'

const agent = new Agent({
  keepAliveTimeout: 60_000,
  keepAliveMaxTimeout: 600_000,
  connections: 50,
})

// Pass to fetch via dispatcher
const res = await fetch(url, { dispatcher: agent })
```

For libraries like `axios`, configure the `httpAgent`/`httpsAgent` explicitly with `keepAlive: true`.

### Server-Side Keep-Alive

HTTP keep-alive is on by default in Node. Don't disable. Tune:

- `server.keepAliveTimeout` — how long an idle connection stays open. Default 5s; usually 60s is better behind a load balancer.
- Set higher than the upstream load balancer's idle timeout to avoid the balancer closing first.

## Rate Limiting and Throttling

Two concerns, related but distinct.

- **Rate limiting** — protect against abuse. Hard limit; reject over.
- **Throttling** — protect against overload. Queue or shed work when the system is under stress.

### Per-IP / Per-User Limits

Standard middleware:

```ts
import rateLimit from 'express-rate-limit'
import RedisStore from 'rate-limit-redis'

export const apiLimiter = rateLimit({
  store: new RedisStore({ sendCommand: (...args) => redis.call(...args) }),
  windowMs: 60_000,
  max: 100,            // 100 req/min
  standardHeaders: true,
  keyGenerator: (req) => req.user?.id ?? req.ip,
})
```

- Tighter limits on sensitive endpoints: login 5/min, password reset 3/hour, expensive search 20/min.
- Use Redis-backed storage so limits hold across instances.
- Return `429 Too Many Requests` with a `Retry-After` header.

### Adaptive Throttling

For overload protection, use circuit breakers and queue depth checks. If the database is at 90% CPU, start shedding non-critical traffic — better to refuse 10% than crash for everyone.

## Background Jobs

Anything that takes more than a few hundred milliseconds doesn't belong in a request handler.

### Use a Queue

- **BullMQ** — Redis-backed. Battle-tested. Default for Node.
- **pg-boss** — Postgres-backed. Fewer moving parts if you already have Postgres.
- **Cloud-native** — SQS, GCP Tasks, Cloud Run Jobs. Good when you're committed to a cloud.

### Pattern

```ts
// In the request handler — fast
await emailQueue.add('send-welcome', { userId: user.id })
res.status(202).json({ status: 'queued' })

// In a separate worker process
new Worker('email', async (job) => {
  await sendWelcomeEmail(job.data.userId)
}, { connection: redis })
```

The request returns immediately. The worker does the slow work. The user gets a response in 20ms instead of 2s.

### What Goes in a Job

- Email delivery.
- PDF/report generation.
- Image processing.
- Third-party API calls that may be slow or rate-limited.
- Bulk database operations.
- Anything with retries.

### Job Discipline

- **Idempotent.** A retry must not double-charge or double-send. Use a unique key or check-and-set pattern.
- **Visibility timeout > expected runtime.** Otherwise the queue thinks the job died and runs it again.
- **Bounded retries.** Default 3–5, exponential backoff, then dead-letter queue for inspection.
- **Observable.** Log job start, success, failure. Alert on dead-letter buildup.

## Monitoring

If you can't measure it, you can't tune it.

### What to Measure

- **Latency percentiles** — p50, p95, p99 per endpoint. Mean hides outliers.
- **Throughput** — requests per second.
- **Error rate** — percentage of non-2xx responses, broken out by endpoint.
- **Saturation** — CPU, memory, DB connections in use, queue depth.
- **Dependencies** — latency and error rate for each external service.

### Tools

- **OpenTelemetry** for traces and metrics. Vendor-neutral; ships to most APMs.
- **APMs** — Datadog, New Relic, Sentry Performance, Honeycomb. Pick one.
- **Logs** — structured JSON (Pino) shipped to a central store (Loki, Datadog, CloudWatch).
- **Database-side metrics** — `pg_stat_statements` for top queries, RDS Performance Insights, slow-query log.

### Alerting

Page on:

- Error rate > 1% for 5 minutes (tune per endpoint).
- p95 latency over SLO for 10 minutes.
- DB connection pool > 90% sustained.
- Queue depth growing without bound.
- Dead-letter job rate above baseline.

Don't page on transient blips. Use multi-window or burn-rate alerts to catch real problems.

### SLOs

Set service-level objectives per endpoint or per user journey:

- "99% of `/api/orders` responses under 500ms over 28 days."
- "99.9% of login attempts succeed (excluding bad-credentials) over 28 days."

Alert on **error budget burn rate**, not on every breach. A two-minute spike is acceptable; a sustained burn is not.

## Common Mistakes

- **N+1 queries.** The classic. Use `include`/`select` to load relations in one query.
- **No connection pooling, or pool too small.** Crashes under modest load.
- **Offset pagination on a million-row table.** Page 1000 reads 50,000 rows. Use cursors.
- **`SELECT *` in hot paths.** Pulls columns you don't need, breaks covering-index optimizations.
- **In-memory cache as the only cache in a multi-instance app.** Each instance has its own. Use Redis for anything that needs consistency.
- **No invalidation on cache writes.** Stale data forever. Pair every write with an invalidation.
- **Cache stampede.** Hot key expires, traffic dogpiles the DB. Use stale-while-revalidate or locking.
- **Compressing in app code when the edge already compresses.** Wasted CPU.
- **Synchronous email/PDF/heavy work in the request path.** User waits 5 seconds for "OK." Use a queue.
- **Jobs without idempotency.** Retries cause double-sends, double-charges, duplicate writes.
- **No slow-query log.** You can't fix what you can't see. Enable it.
- **Mean latency as the only metric.** A p99 of 8 seconds is hiding behind a 200ms mean. Track percentiles.
- **No alerting on dead-letter queues.** Failed jobs pile up silently for weeks until someone notices.
- **Disabling keep-alive on outbound HTTP.** Every request pays the TCP+TLS handshake cost. Reuse connections.
- **Premature optimization.** Profile first, optimize what's actually slow. Don't add Redis because "it'll be faster."
- **No load test before launch.** You discover the bottleneck in production. Spend an afternoon with `k6` or `artillery` first.
