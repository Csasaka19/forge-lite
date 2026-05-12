# Rate Limiting & Throttling

How to protect an API from abuse, accidental floods, and runaway clients. Read before exposing any public endpoint.

## Decision Tree

| Need | Pick |
|---|---|
| Global per-IP cap on a small app | **`express-rate-limit`** in memory |
| Multi-instance, must hold across replicas | **`express-rate-limit` + Redis store** |
| Token-bucket with burst tolerance | **`rate-limiter-flexible`** (Redis backed) |
| Auth endpoints, sensitive routes | **Per-account limits** with progressive lockout |
| DDoS protection at edge | **Cloudflare, AWS Shield, Vercel Firewall** — not your app |
| Per-tenant SaaS quotas | **Custom counter in Redis** scoped by tenant |

In-app limiting is the second line. The edge (CDN/WAF) is the first.

## Algorithm Selection

### Fixed Window

Count requests in 1-minute buckets. Reset every minute. Simple; spiky at bucket edges (allows 2× near the boundary).

### Sliding Window

Tracks the last N seconds continuously. Smoother, slightly more expensive.

### Token Bucket

A bucket holds N tokens; each request consumes one; tokens refill at a steady rate. Allows bursts up to N, sustained rate equal to refill. The standard for APIs because it tolerates legitimate bursts.

### Leaky Bucket

Like token bucket inverted: requests queue, leak out at a fixed rate. Smooths traffic to a steady stream. Used at L7 proxies (Nginx); less common in app code.

Default choice: **token bucket** (`rate-limiter-flexible`). Falls back to fixed window for the simplest cases.

## express-rate-limit (Quick Start)

```bash
npm install express-rate-limit rate-limit-redis ioredis
```

```ts
import rateLimit from 'express-rate-limit'
import RedisStore from 'rate-limit-redis'
import { Redis } from 'ioredis'

const redis = new Redis(env.REDIS_URL)

export const apiLimiter = rateLimit({
  store: new RedisStore({ sendCommand: (...args) => redis.call(...args) as Promise<any> }),
  windowMs: 60 * 1000,
  max: 100,
  standardHeaders: 'draft-7',     // RateLimit-* headers
  legacyHeaders: false,
  keyGenerator: (req) => req.user?.id ?? req.ip ?? 'anon',
  handler: (_req, res) => res.status(429).json({
    error: { code: 'RATE_LIMIT', message: 'Too many requests' },
  }),
})

app.use(apiLimiter)
```

In-memory storage works only for single-instance apps. Use Redis-backed storage for anything else — limits hold across replicas.

## Tighter Limits on Sensitive Endpoints

```ts
export const loginLimiter = rateLimit({
  store: new RedisStore({ sendCommand: (...a) => redis.call(...a) as any }),
  windowMs: 60 * 1000,
  max: 5,
  keyGenerator: (req) => `login:${req.ip}:${req.body?.email ?? ''}`,
  skipSuccessfulRequests: true,    // only count failures
})

app.post('/auth/login', loginLimiter, login)
```

### Per-Endpoint Suggestions

| Endpoint | Limit |
|---|---|
| Login | 5 / minute per IP+email |
| Password reset | 3 / hour per email |
| Signup | 5 / hour per IP |
| Password change | 5 / hour per user |
| OTP send (SMS/email) | 3 / 5 min per phone/email |
| Search | 30 / minute per user |
| Generic read | 100 / minute per user |
| Generic write | 30 / minute per user |
| Webhook receive | 1000 / minute per source IP (don't throttle providers too tight) |

Tune by traffic patterns. Set baseline, watch real values, adjust.

## Token Bucket with rate-limiter-flexible

```bash
npm install rate-limiter-flexible
```

```ts
import { RateLimiterRedis } from 'rate-limiter-flexible'

const limiter = new RateLimiterRedis({
  storeClient: redis,
  keyPrefix: 'api',
  points: 100,             // bucket size (burst)
  duration: 60,            // ... refilling over 60s
  blockDuration: 60,       // block for 60s after exhaustion
})

export const limit: RequestHandler = async (req, res, next) => {
  try {
    const key = req.user?.id ?? req.ip ?? 'anon'
    await limiter.consume(key, 1)
    next()
  } catch (rej) {
    const ms = (rej as any).msBeforeNext ?? 1000
    res.set('Retry-After', String(Math.ceil(ms / 1000)))
    res.status(429).json({ error: { code: 'RATE_LIMIT' } })
  }
}
```

### Multi-Tier Rate Limiting

Combine limits per tier — global, per-IP, per-user, per-endpoint:

```ts
async function check(req: Request) {
  const userId = req.user?.id ?? req.ip
  await Promise.all([
    globalLimiter.consume('global'),
    ipLimiter.consume(req.ip),
    userLimiter.consume(userId),
    endpointLimiter.consume(`${userId}:${req.route?.path}`),
  ])
}
```

Most-restrictive wins. Reject early — don't waste DB queries on a request that's about to be 429'd.

## Login Attempt Limiting

Beyond rate limits: **lock the account** after repeated failures.

```ts
async function recordLoginFailure(email: string) {
  const key = `login-failures:${email}`
  const count = await redis.incr(key)
  if (count === 1) await redis.expire(key, 15 * 60)    // 15-min window

  if (count >= 5) {
    await prisma.user.update({
      where: { email },
      data: { lockedUntil: new Date(Date.now() + 15 * 60_000) },
    })
    await sendAccountLockedEmail(email)
  }
}
```

### Rules

- **Notify the user.** Lockout email gives them a heads-up something's happening on their account.
- **Constant-time response** for "user not found" vs "wrong password" — same status, same shape, same timing. Don't leak which emails exist.
- **Reset on successful login.** Clear the failure counter.
- **Don't lock forever.** Permanent locks are abused as DoS. Time-bounded with self-service unlock.

## Rate-Limit Response Headers

Tell clients what's happening. Don't make them guess.

```
RateLimit-Limit: 100
RateLimit-Remaining: 64
RateLimit-Reset: 30           # seconds until window resets
Retry-After: 30               # only on 429
```

`express-rate-limit` adds them with `standardHeaders: 'draft-7'`. Always include `Retry-After` on 429.

## Per-Tenant SaaS Quotas

For B2B with plan-based quotas:

```ts
async function checkTenantQuota(tenantId: string, endpoint: string) {
  const plan = await getTenantPlan(tenantId)
  const limit = QUOTAS[plan][endpoint]
  const key = `quota:${tenantId}:${endpoint}:${todayKey()}`

  const count = await redis.incr(key)
  if (count === 1) await redis.expireat(key, endOfDayUnix())

  if (count > limit) throw new ApiError(429, 'PLAN_QUOTA_EXCEEDED', { plan, limit })
}
```

Quotas tend to be **per-day or per-month**, not per-minute — they protect revenue terms, not server load. Combine both: per-minute for safety, per-month for billing.

## DDoS Basics

App-level rate limiting won't stop a real DDoS. The volume overwhelms your network before your code runs.

### Real DDoS Protection

- **Cloudflare** (or Cloudflare-class) in front of your origin. Free tier handles a lot.
- **AWS Shield Standard** is on by default for AWS-hosted resources. Shield Advanced for stronger SLA.
- **Vercel Firewall**, **Fastly**, others — equivalent options.

What the edge does that your app can't:

- Absorbs the volume before it hits you.
- Fingerprints botnets, blocks at IP/ASN level.
- Filters malformed traffic.
- Geofencing.

### Hide the Origin

If you have a CDN, lock your origin to only accept traffic from the CDN's IP ranges. Attackers can't bypass to hit your servers directly.

```
# Nginx allowlist (Cloudflare ranges)
allow 173.245.48.0/20;
# ... (full list rotates; use a script to refresh)
deny all;
```

### Application-Layer Mitigations

When edge filtering isn't enough:

- **Aggressive 429 on suspect patterns** (high request rate from one IP).
- **Tar-pit / slow response** on repeated failure — adds latency to attacker's path without blocking legitimate retries.
- **Cookie/JS challenges** for routes that don't need to serve bots.
- **CAPTCHA** on login, signup, password reset. **hCaptcha** or **Turnstile** are privacy-friendly defaults.

## Cost-Conscious Endpoints

For endpoints that cost real money (sending SMS, calling expensive APIs, generating PDFs):

- **Per-user lifetime caps** ("you can request 100 SMS this month").
- **Sliding-window per-hour limits** to smooth bursts.
- **Cost-based limiting**: each request consumes N "tokens" based on the cost; user has a budget.

```ts
async function chargeCost(userId: string, costPoints: number) {
  await costLimiter.consume(userId, costPoints)
}

await chargeCost(user.id, smsSegments * 10)
await sendSms(...)
```

## Bypass and Whitelist

Some clients should bypass — internal services, monitoring, premium customers.

```ts
const limit: RequestHandler = async (req, res, next) => {
  if (isInternalRequest(req)) return next()
  if (req.user?.plan === 'enterprise') return next()
  // ... regular check
}
```

Log bypasses so you can audit. Don't let bypass become the path of least resistance for "just one more service."

## Common Mistakes

- **In-memory rate limit on a multi-instance app.** Each instance counts separately; limit is N × instances. Use Redis-backed storage.
- **No `Retry-After` on 429.** Clients retry immediately, get 429 again, herd.
- **Same limit on login and on generic reads.** Either too tight for normal users or too loose for credential stuffing. Tier per endpoint.
- **`keyGenerator` based on a header attackers control.** `X-Forwarded-For` from arbitrary requests is spoofable; trust only at the edge.
- **No per-account lockout.** Distributed credential stuffing rotates IPs; per-IP limits don't catch it.
- **Permanent account lockout.** Becomes a DoS vector — attacker locks every email they know.
- **Different responses for "user not found" vs "wrong password."** Account enumeration. Same status, same timing.
- **Rate-limiting only at the application layer with no edge protection.** Real DDoS still gets through.
- **Origin server reachable directly (bypassing CDN).** Attacker hits it and bypasses every CDN protection. Lock the origin to CDN IPs.
- **No alerting on rate-limit-hit volume.** A spike of 429s might be normal noise or a real attack. Distinguish with alerts.
- **CAPTCHAs on every login.** Hostile UX. Use them only after suspicious signals.
- **Logging full request bodies on 429.** Adds load during an attack. Log only what's needed.
- **Counting successful logins toward the failure limit.** `skipSuccessfulRequests: true` for login limiters.
- **Webhook receivers rate-limited tightly.** Stripe retries get blocked, your data goes stale. Whitelist or set per-source limits.
- **No quota observability for tenants.** They hit the limit and don't know why. Surface usage in their dashboard.
