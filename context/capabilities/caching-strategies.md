# Caching Strategies

Where to cache, how long, and how to invalidate. Read before optimizing read paths or "just adding Redis."

## Decision Tree: Where to Cache

| Data | Cache layer |
|---|---|
| Hashed static asset (JS/CSS bundle, image with content hash) | **Browser + CDN, 1 year, `immutable`** |
| HTML shell | **Browser short-cache or no-cache, CDN with revalidation** |
| Authenticated API response | **No public cache, possibly in-memory per request** |
| Public read endpoint (low churn) | **CDN + Redis + HTTP cache headers** |
| Hot DB query result | **Redis (shared) or in-memory (single instance)** |
| Computed value in one render | **`useMemo`** |
| Server-side computed value across requests | **Redis or LRU** |

Caching is the second-best fix. The best fix is to not need the work. Profile first.

## Browser Cache (HTTP)

Set via `Cache-Control`. Browsers honor it; CDNs honor it.

### Hashed Assets

```
Cache-Control: public, max-age=31536000, immutable
```

- **`max-age=31536000`** — 1 year.
- **`immutable`** — never revalidate, even on hard reload (Chrome respects this).
- Vite/Next/Webpack content-hash filenames automatically; the hash changes whenever content does.

### HTML

```
Cache-Control: public, max-age=0, must-revalidate
```

Or `no-cache` (which means "check before using," not "don't cache").

### API Responses

- **Authenticated**: `Cache-Control: private, no-store`. Don't cache anywhere.
- **Public read, low churn**: `Cache-Control: public, max-age=60, stale-while-revalidate=300`. Cache 60s; serve stale up to 5 more minutes while refreshing.

### ETag

For conditional GETs:

```ts
const body = JSON.stringify(data)
const tag = `"${crypto.createHash('sha1').update(body).digest('base64')}"`
res.set('ETag', tag)
if (req.headers['if-none-match'] === tag) return res.status(304).end()
res.send(body)
```

304 responses save bandwidth without losing freshness.

## CDN Cache

Sits between the browser and your origin. Configure via headers (or platform UI for cache rules).

### Patterns

- **Vercel / Netlify**: respects `Cache-Control` from your responses by default.
- **Cloudflare**: separate "Edge Cache TTL" rules; can override headers.
- **CloudFront**: cache policies, distinct from your headers.

Key rules:

- **Vary on what changes the response.** `Vary: Accept-Encoding` for compression; `Vary: Accept` for content negotiation.
- **Never cache cookies-bound responses publicly.** A response set for user A served to user B = breach.
- **Cache by URL.** Query params count. `?utm_source=` should be stripped or ignored.

### Invalidation

Best invalidation = URL change. Hash the content, change the URL, problem gone.

When invalidating is unavoidable:

- **Vercel / Netlify**: redeploy invalidates the build.
- **Cloudflare**: `Cache.purge` API.
- **CloudFront**: create an invalidation (slow, partly billed).

Plan for cache invalidation latency — never assume "purged" means "instantly gone" across all edges.

## App Cache: Redis

For data shared across instances: session state, hot read data, rate-limit counters, locks.

```ts
import { Redis } from 'ioredis'
export const redis = new Redis(env.REDIS_URL)
```

### Cache-Aside Pattern

```ts
async function getMachine(id: string): Promise<Machine> {
  const cached = await redis.get(`machine:${id}`)
  if (cached) return JSON.parse(cached)

  const fresh = await prisma.machine.findUnique({ where: { id } })
  if (!fresh) throw new NotFoundError('Machine')
  await redis.set(`machine:${id}`, JSON.stringify(fresh), 'EX', 300)
  return fresh
}
```

### Invalidation on Write

```ts
async function updateMachine(id: string, data: Partial<Machine>) {
  const updated = await prisma.machine.update({ where: { id }, data })
  await redis.del(`machine:${id}`)
  return updated
}
```

### Key Conventions

- **Namespace by concern**: `machine:${id}`, `user:${id}:orders`.
- **Include tenant** in multi-tenant apps: `tenant:${tenantId}:machine:${id}`.
- **TTL on everything.** Even "permanent" data — protects against bugs.
- **Cap value size.** Redis values past ~1 MB slow the server. Don't cache giant blobs.

## Stale-While-Revalidate (Cache Stampede)

When a hot key expires, many requests miss simultaneously and hammer the DB.

```ts
async function getWithSWR<T>(
  key: string,
  freshFn: () => Promise<T>,
  ttlSec = 300,
  graceSec = 600,
): Promise<T> {
  const raw = await redis.get(key)
  if (raw) {
    const { value, expiresAt } = JSON.parse(raw)
    if (expiresAt > Date.now()) return value
    // Stale — refresh in background, return stale now
    refreshInBackground(key, freshFn, ttlSec).catch(() => {})
    return value
  }
  const fresh = await freshFn()
  await redis.set(key, JSON.stringify({ value: fresh, expiresAt: Date.now() + ttlSec * 1000 }), 'EX', ttlSec + graceSec)
  return fresh
}
```

Alternative: **lock the refresh** so only one request hits the DB; others wait briefly.

```ts
const lockKey = `${key}:refresh-lock`
const got = await redis.set(lockKey, '1', 'NX', 'EX', 10)
if (got) {
  try { /* refresh */ } finally { await redis.del(lockKey) }
}
```

## In-Memory Cache (Per Process)

For super-hot data tolerable as slightly stale across instances:

```bash
npm install lru-cache
```

```ts
import { LRUCache } from 'lru-cache'

const flagsCache = new LRUCache<string, FlagSet>({
  max: 1000,
  ttl: 60_000,            // 1 minute
})

function getFlags(userId: string) {
  let v = flagsCache.get(userId)
  if (v) return v
  v = await loadFlags(userId)
  flagsCache.set(userId, v)
  return v
}
```

Notes:

- **Multi-instance drift**: each instance has its own cache. Acceptable for low-stakes data; not for anything that must agree.
- **Process restart wipes it.** Don't store anything you can't recompute.

## React Memoization

In the browser, three primitives:

- **`useMemo(fn, deps)`** — cache a computed value across renders.
- **`useCallback(fn, deps)`** — cache a function identity. Use when passing to memoized children.
- **`React.memo(Component)`** — skip re-render when props haven't changed.

```tsx
const sorted = useMemo(() => items.toSorted(sortFn), [items, sortFn])

const handleClick = useCallback((id: string) => removeItem(id), [removeItem])

const Row = React.memo(function Row({ item }: { item: Item }) {
  return <li>{item.name}</li>
})
```

### Rules

- **Don't memoize everything.** Each `useMemo` adds overhead and memory. Profile before optimizing.
- **Stable references for memo to help.** `useCallback`'d handlers; primitive props; memoized objects.
- **`React.memo` is shallow.** Pass primitives or memoized objects, not freshly-allocated `{...}` literals.
- **`useDeferredValue` / `useTransition`** for filtering/sorting large lists — cooperates with concurrent rendering better than manual memoization.

## TanStack Query as Server-State Cache

Already a cache. `staleTime` controls freshness; `gcTime` controls retention.

```ts
useQuery({
  queryKey: ['machines', { status }],
  queryFn: () => api(`/machines?status=${status}`),
  staleTime: 30_000,     // don't refetch within 30s
  gcTime: 5 * 60_000,    // keep in memory 5min after unmount
})
```

Don't reach for Redux + manual fetching when TanStack Query gives you caching, dedupe, retry, and refetch in one package.

## Invalidation Patterns

> "There are only two hard things in computer science: cache invalidation and naming things." — Phil Karlton

### TTL-Based

Easiest. Cache for N seconds; let it expire. Tolerates staleness up to N.

### Event-Based

On write, evict related keys:

```ts
async function updateMachine(id, data) {
  const m = await prisma.machine.update({ where: { id }, data })
  await Promise.all([
    redis.del(`machine:${id}`),
    redis.del(`machines:tenant:${m.tenantId}`),    // list cache
  ])
  return m
}
```

Track which keys to evict alongside the write — a separate list grows out of date.

### Tag-Based

Group keys by tag, evict all of one tag:

```ts
await redis.sadd(`tag:tenant:${tenantId}`, key)
// On invalidation:
const keys = await redis.smembers(`tag:tenant:${tenantId}`)
await redis.del(...keys, `tag:tenant:${tenantId}`)
```

Useful for "everything for tenant X."

### Version-Based

Bump a version counter for the entire bucket; old keys age out via TTL.

```ts
const version = await redis.get(`machines:version`) ?? '1'
const key = `machines:v${version}:${id}`
```

Invalidating means incrementing the version. Old cached entries become orphans, deleted by TTL.

## Common Mistakes

- **Caching authenticated responses publicly.** One user's data served to another. Use `Cache-Control: private` or `no-store`.
- **No cache invalidation strategy.** Stale data forever. Plan invalidation alongside the cache.
- **Caching the wrong thing.** Caching DB results when the bottleneck is the slow API call upstream.
- **In-memory cache in a multi-instance app for consistency-critical data.** Each instance sees different state.
- **Cache stampede on hot keys.** Coordinated misses crash the DB. Use SWR or locks.
- **`useMemo` everywhere.** Adds overhead, helps nothing if dependencies change every render.
- **No TTL on Redis keys.** Bugs leave stale data forever. Always set a TTL.
- **One giant value cached (10 MB JSON).** Slows Redis, network, deserialization. Cache per-entity.
- **Cache key includes the user's session token.** Cache fragments by session, hit rate ~0%.
- **CDN cache without `Vary: Accept-Encoding`.** Gzipped response served to clients that didn't ask for it.
- **Reading from cache without checking the source of truth on writes.** Updates lost.
- **Caching error responses.** "Service unavailable" cached for 5 minutes, prolonged outage. Don't cache non-2xx.
- **`max-age` without `must-revalidate` on HTML.** Browser serves the old shell for days.
- **Stale TanStack Query data after a mutation, no invalidation.** Add `invalidateQueries` to `onSuccess`.
- **Cache fronting a write endpoint.** Writes return cached results, never reaching the DB. Only cache reads.
- **No metric on cache hit rate.** Can't tell if it's helping. Track it.
