# Logging & Observability

How to know what's happening in production. Read before adding `console.log`, before launching anything publicly, before going on-call.

## Decision Tree: What to Reach For

| Question | Tool |
|---|---|
| What happened in this request? | **Structured logs** (Pino) keyed by correlation ID |
| Why did this throw in prod? | **Sentry** (or Rollbar/Bugsnag) |
| How fast is this endpoint? | **APM traces** (Sentry, Datadog, OpenTelemetry → backend) |
| Is the system up? | **Uptime monitor** (external pings) |
| Are users having a bad time? | **Web Vitals + RUM** (real-user monitoring) |
| Should I get paged? | **Alerts on SLO burn**, not on raw events |

You need all of these in production. They're not interchangeable.

## Structured Logging

Logs are read by machines first, humans second. **Always JSON** in production. Never `console.log` in server code.

### Pino

```ts
// src/lib/logger.ts
import pino from 'pino'

export const logger = pino({
  level: env.LOG_LEVEL ?? 'info',
  formatters: {
    level: (label) => ({ level: label }),
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  redact: {
    paths: [
      'password', '*.password',
      'token', '*.token',
      'authorization', 'req.headers.authorization',
      'cookie', 'req.headers.cookie',
      '*.email',                  // adjust per privacy policy
    ],
    censor: '[REDACTED]',
  },
})
```

### Pretty Output in Dev

```json
"scripts": {
  "dev": "node --enable-source-maps dist/server.js | pino-pretty"
}
```

Pretty in dev, raw JSON in production. Logs in prod go to stdout and the platform ships them somewhere (Loki, Datadog, CloudWatch, Logflare).

## Log Levels

Use them consistently. The level determines who gets paged and what gets shipped.

| Level | Use for | Audience |
|---|---|---|
| `debug` | Verbose dev info: payloads, internal state | Dev only — disabled in prod |
| `info` | Significant events: server start, user signed up, order created | Operators reviewing flow |
| `warn` | Recoverable issues: retry succeeded, deprecated endpoint hit, fallback fired | Operators noticing patterns |
| `error` | Failures needing attention: unhandled exception, external service down | Whoever's on-call |
| `fatal` | Process about to die | On-call, then post-mortem |

### Rules

- **Never log at `error` for an expected outcome.** Validation failures from user input are `info` or `warn`, not `error`. Otherwise alerts drown.
- **One log line per significant event**, not five for the same thing.
- **Structured fields, not interpolated strings.** `logger.info({ userId, orderId }, 'Order created')`, not `logger.info('Order ' + orderId + ' created for ' + userId)`.
- **Don't `console.log` to "see what's happening."** Use `logger.debug` so it can be turned off in prod.

## Correlation IDs

Every request gets an ID. Every log emitted while handling that request includes it. When a user reports a bug, the support team gives you the ID, and you find every related log in seconds.

### Middleware

```ts
import { randomUUID } from 'node:crypto'

declare global {
  namespace Express {
    interface Request {
      id: string
      logger: typeof logger
    }
  }
}

export const requestId: RequestHandler = (req, res, next) => {
  const incoming = req.headers['x-request-id']
  req.id = typeof incoming === 'string' ? incoming : randomUUID()
  res.set('X-Request-Id', req.id)
  req.logger = logger.child({ requestId: req.id })
  next()
}
```

Use `req.logger` everywhere — it carries the ID automatically.

```ts
req.logger.info({ orderId }, 'Order created')
```

### Propagate Downstream

When calling another service, forward the ID:

```ts
fetch(url, { headers: { 'X-Request-Id': req.id } })
```

The downstream service uses the same ID, so a single ID traces the whole request fan-out.

### In Async Work

When the request enqueues a background job, pass the ID through:

```ts
await jobQueue.add('send-email', { userId, requestId: req.id })
```

The worker uses it as its log context — same ID, complete trace from request to side effect.

## Frontend Errors: Sentry

```bash
npm install @sentry/react
```

```ts
// src/main.tsx
import * as Sentry from '@sentry/react'

Sentry.init({
  dsn: import.meta.env.VITE_SENTRY_DSN,
  environment: import.meta.env.MODE,
  release: import.meta.env.VITE_GIT_SHA,
  integrations: [
    Sentry.browserTracingIntegration(),
    Sentry.replayIntegration({ maskAllText: true, blockAllMedia: true }),
  ],
  tracesSampleRate: 0.1,           // 10% of transactions
  replaysSessionSampleRate: 0.0,
  replaysOnErrorSampleRate: 1.0,   // 100% on errors
})
```

### User Context

After login, attach the user. Never log emails or PII in plain — use anonymized IDs.

```ts
Sentry.setUser({ id: user.id })
// On logout
Sentry.setUser(null)
```

### Source Maps

Upload source maps at build time so stack traces resolve to real code:

```bash
sentry-cli sourcemaps upload --release="$GIT_SHA" dist/
```

Most build tools (Vite, Next, Webpack) have a Sentry plugin that handles this automatically.

### Breadcrumbs

Sentry auto-captures clicks, navigation, fetch calls. Add custom ones for domain events:

```ts
Sentry.addBreadcrumb({
  category: 'order',
  message: 'User initiated checkout',
  level: 'info',
  data: { machineId },
})
```

When an error fires, the breadcrumb trail shows what led up to it.

### Filtering Noise

Drop expected errors before they leave the client:

```ts
beforeSend(event, hint) {
  const err = hint.originalException
  if (err instanceof ApiError && err.status === 401) return null   // expected auth failure
  return event
}
```

## Backend Request Logging

Log every request once, on completion. Not separate "request received" + "response sent" lines — one structured line with everything.

```ts
export const accessLog: RequestHandler = (req, res, next) => {
  const start = process.hrtime.bigint()

  res.on('finish', () => {
    const durMs = Number(process.hrtime.bigint() - start) / 1e6
    req.logger.info({
      method: req.method,
      path: req.route?.path ?? req.path,
      status: res.statusCode,
      durationMs: Math.round(durMs),
      userId: req.user?.id,
      ip: req.ip,
      userAgent: req.headers['user-agent'],
    }, 'request')
  })

  next()
}
```

### Rules

- **Log the route pattern, not the raw path.** `/users/:id` aggregates better than `/users/42`.
- **Never log request or response bodies in production.** PII + secrets leak this way. If you must for one endpoint, redact rigorously and rate-limit.
- **`finish` event captures the response.** Don't log inside the handler before it returns — you miss thrown errors and timing.

## Sensitive Field Redaction

Redact at the **logger level**, not at the call site. Call-site redaction is forgotten exactly once and that one leak is enough.

Pino's `redact` config (above) walks the object. For nested data, use paths or wildcards. Test redaction in a unit test — log a known-sensitive object, assert the output is scrubbed.

What to redact, always:

- Passwords, password hashes.
- Tokens, refresh tokens, session IDs.
- Authorization and Cookie headers.
- Full credit card numbers, CVV.
- API keys.

What to redact unless explicitly needed:

- Email addresses (use a hash or user ID instead).
- Phone numbers.
- IP addresses (in some jurisdictions, IPs are PII).

## Health Checks

Two endpoints, with distinct semantics. Don't conflate them.

### `/health` — Liveness

"Is the process responsive?" If not, the orchestrator restarts the container.

```ts
app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok' })
})
```

**No external dependencies.** A flaky database shouldn't cause restart loops. Liveness asks one question: is the event loop responding?

### `/ready` — Readiness

"Should this instance receive traffic?" If not, the load balancer takes it out of rotation until it recovers.

```ts
app.get('/ready', async (_req, res) => {
  try {
    await Promise.all([
      prisma.$queryRaw`SELECT 1`,
      redis.ping(),
    ])
    res.status(200).json({ status: 'ready' })
  } catch (err) {
    req.logger.warn({ err }, 'Readiness check failed')
    res.status(503).json({ status: 'not-ready' })
  }
})
```

Readiness **does** check dependencies. A backend without a database can't serve real traffic.

## Uptime Monitoring

External pings from outside your infrastructure. If your monitoring runs inside the same datacenter as your app, an outage takes both down and you learn from Twitter.

### Tools

- **Better Stack** (formerly Better Uptime), **UptimeRobot**, **Hetrix** — entry-level, generous free tiers.
- **Pingdom**, **StatusCake** — established options.
- **Datadog Synthetics**, **Checkly** — integrated with broader observability.

### Configuration

- **1-minute checks** for production.
- **Multiple regions** — a single point of monitoring lies during regional issues.
- **Alert on 2 consecutive failures**, not 1. Avoids paging on a single flake.
- **Hit `/health`**, not the homepage. Homepage may degrade for unrelated reasons.

### Status Page

Public status page is part of trust. Statuspage, Instatus, BetterStack all work.

- Show component status (API, dashboard, mobile).
- Tie to incidents — when an alert fires, an incident is auto-created or surfaced to subscribers.
- Subscribe button for users.

## Performance Monitoring

### Frontend: Core Web Vitals

```ts
import { onCLS, onINP, onLCP } from 'web-vitals'

function report(metric: { name: string; value: number; id: string }) {
  navigator.sendBeacon('/api/vitals', JSON.stringify(metric))
}

onCLS(report)
onINP(report)
onLCP(report)
```

Targets at p75:

- **LCP < 2.5s**
- **INP < 200ms**
- **CLS < 0.1**

Send to your analytics backend, Vercel Analytics, or a dedicated RUM provider.

### Backend: Latency Percentiles

Mean latency lies. Track p50, p95, p99 per endpoint. The mean might be 100ms while p99 is 8 seconds — a tail that's eating users.

OpenTelemetry exports to most APMs:

```ts
import { NodeSDK } from '@opentelemetry/sdk-node'
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node'
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http'

new NodeSDK({
  traceExporter: new OTLPTraceExporter(),
  instrumentations: [getNodeAutoInstrumentations()],
}).start()
```

Auto-instrumentations cover HTTP, Express, Prisma, Redis — no manual span code needed for common paths.

### Database

`pg_stat_statements` for the top-N slowest queries. Cloud-managed Postgres exposes this via Performance Insights or similar. Review weekly.

## Alerting

Alerts that don't require action don't belong in the alert channel. Tune until every page is real.

### What to Alert On

- **Error rate above baseline by 3×** for 5+ minutes.
- **p95 latency over SLO** for 10+ minutes.
- **Uptime check failing** from 2 regions.
- **Database CPU > 80%** sustained 10 minutes.
- **Disk > 80%** on production volumes.
- **Failed deploy.**
- **Certificate expiry within 14 days.**
- **Dead-letter queue depth growing.**
- **New high-severity Sentry issue** (first occurrence of a previously unseen error class).

### What NOT to Alert On

- **Individual errors.** Use Sentry's daily digest.
- **Latency spikes < 1 minute.** Noise.
- **CPU > 50% for 30 seconds.** Garbage collection cycle, not an incident.
- **Anything you'd silence after the first page.** Either fix the alert or the underlying issue.

### Burn-Rate Alerts

For SLOs ("99% of requests under 500ms over 28 days"), alert on **error-budget burn rate** instead of every breach. A 1-hour spike that consumes 0.5% of the monthly budget is acceptable; a sustained drip that consumes 50% in a day is not.

### Routing

- **Page-worthy alerts** → on-call rotation (PagerDuty, Opsgenie, Better Stack).
- **Awareness alerts** → team chat channel (Slack).
- **FYI metrics** → dashboard. No notifications.

## Production Debugging with Correlation IDs

When a user reports a bug:

1. **Get the request ID.** It's in the response headers (`X-Request-Id`) and in error toasts. Surface it in user-facing error messages: "Something went wrong. Reference: a1b2c3...".
2. **Search logs for that ID.** One query in Loki/Datadog/CloudWatch returns every line emitted for that request — across services, across queue workers, across retries.
3. **Pull the Sentry event.** Sentry tags include the request ID; you find the full stack with breadcrumbs.
4. **Correlate with APM trace.** Same ID in the trace; you see DB queries, downstream calls, where time was spent.
5. **Reproduce** with the captured input. Fix. Add a test.

This workflow only works if **every log line carries the ID**. Without correlation IDs, debugging in production is guesswork.

## Common Mistakes

- **`console.log` in production code.** Unstructured, unsearchable, unfilterable. Use a logger.
- **Logging at `error` for expected user input failures.** Pages the on-call for a typo. Use `info` or `warn`.
- **Logging request bodies.** PII and secrets leak. Log identifiers and outcomes.
- **No correlation IDs.** Debugging requires guessing. Add them on day one.
- **Same `/health` as `/ready`.** Liveness should be cheap and dependency-free; readiness should be honest.
- **Liveness check that queries the database.** Database hiccup → restart loop → cascading failure.
- **No source maps in production.** Sentry stack traces show minified gibberish.
- **`Sentry.setUser({ email })`.** Leaks PII into the error tracker. Use IDs.
- **Mean latency as the metric.** Hides tail issues. Use percentiles.
- **Alert on every individual error.** Alert fatigue → real alerts ignored.
- **No status page.** Users find out from Twitter.
- **Uptime monitoring from the same datacenter.** Outage takes both down. Use an external service.
- **Pretty-printed JSON logs in production.** Costs CPU; aggregators want compact JSON.
- **Logger not redacting at the call site.** One forgotten `password` field leaks. Configure redaction in the logger.
- **No retention policy on logs.** Logs grow forever, costs balloon. 30 days for app logs, longer for audit.
- **Alert thresholds set once, never reviewed.** Traffic grows, thresholds become wrong. Review quarterly.
- **Manual investigation as the only debug tool.** When the ID lookup is broken, every incident takes hours. Test the workflow.
