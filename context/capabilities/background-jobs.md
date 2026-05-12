# Background Jobs

How to run work outside the request path. Read before adding a slow operation to an endpoint or scheduling anything recurring.

## Decision Tree

| Situation | Pick |
|---|---|
| Self-hosted Node, Redis already in stack | **BullMQ** |
| Postgres available, no Redis | **pg-boss** or **graphile-worker** |
| Vercel / serverless deploy | **Inngest** or **Trigger.dev** |
| AWS-resident, simple queue | **SQS + Lambda** |
| Cron-only (no queue) | **EAS Scheduled Jobs**, **Vercel Cron**, **systemd timers**, **GitHub Actions cron** |

Don't run jobs inside the same process as the web server in production. Workers are separate processes.

## BullMQ

```bash
npm install bullmq ioredis
```

### Queue and Worker

```ts
import { Queue, Worker } from 'bullmq'
import { Redis } from 'ioredis'

const connection = new Redis(env.REDIS_URL, { maxRetriesPerRequest: null })

export const emailQueue = new Queue('email', { connection })

new Worker(
  'email',
  async (job) => {
    if (job.name === 'order-confirmation') {
      await sendOrderConfirmation(job.data.orderId)
    }
  },
  {
    connection,
    concurrency: 10,
    removeOnComplete: { count: 1000, age: 24 * 3600 },
    removeOnFail: { count: 5000 },
  },
)
```

Workers run in a separate process. Spin them up via your process manager (PM2, systemd, Docker, Kubernetes).

### Enqueue

```ts
await emailQueue.add('order-confirmation', { orderId }, {
  attempts: 3,
  backoff: { type: 'exponential', delay: 1000 },
  jobId: `order-confirmation:${orderId}`,    // idempotency
})
```

### Idempotency

Set a deterministic `jobId`. BullMQ rejects duplicates with the same ID until the job ages out. Without it, retries and accidental double-enqueues run twice.

For mutations the worker performs, also make the work itself idempotent — check current state, advance only if needed.

## Retry Strategy

```ts
await queue.add('process', data, {
  attempts: 5,
  backoff: { type: 'exponential', delay: 2000 },   // 2s, 4s, 8s, 16s
  removeOnFail: false,                              // keep failed jobs for inspection
})
```

### Rules

- **3–5 attempts** with exponential backoff for most jobs.
- **Don't retry validation failures.** If `data.userId` doesn't exist, no number of retries will fix it. Throw a non-retryable error, dead-letter immediately.
- **Retry only transient failures**: network timeouts, 5xx from third parties, lock conflicts.
- **Cap the backoff.** 16s, 32s — don't let one stuck job hold a worker for hours.

### Distinguish Errors

```ts
class NonRetryableError extends Error {}

new Worker('email', async (job) => {
  try {
    await doWork(job.data)
  } catch (err) {
    if (err instanceof NonRetryableError) {
      job.discard()    // skip remaining attempts
      throw err
    }
    throw err
  }
})
```

## Dead-Letter Queue

Jobs that exhaust attempts go to a DLQ for human review. BullMQ keeps failed jobs by default; query them:

```ts
const failed = await emailQueue.getFailed(0, 50)
for (const job of failed) {
  console.log(job.id, job.failedReason, job.data)
}
```

**Alert on DLQ depth growing.** Failures that pile up unobserved become silent data loss.

For an explicit DLQ pattern:

```ts
new Worker('email', handler, {
  connection,
  ...,
}).on('failed', async (job, err) => {
  if (job && job.attemptsMade >= (job.opts.attempts ?? 1)) {
    await deadLetterQueue.add('email-dead', { originalJob: job.data, error: err.message })
  }
})
```

## Cron / Scheduled Jobs

### BullMQ Repeating Jobs

```ts
await queue.add(
  'daily-report',
  {},
  { repeat: { pattern: '0 9 * * *', tz: 'Africa/Nairobi' } },
)
```

`pattern` is standard cron syntax. Always set `tz` — server timezone bites.

### Vercel Cron / Cloudflare Cron Triggers

For serverless deploys, use the platform's cron. Each scheduled time hits an HTTP endpoint:

```json
// vercel.json
{
  "crons": [
    { "path": "/api/cron/daily-report", "schedule": "0 9 * * *" }
  ]
}
```

The endpoint must complete within the platform's timeout (10–60s depending on plan). For longer work, enqueue from the cron handler.

### Rules

- **Idempotent cron handlers.** If the platform retries (Vercel and similar do), the second run must not double-process.
- **Lock by date.** "Daily report for 2026-05-12" runs once total — use a unique key in DB before processing.
- **Set a sensible timezone.** Don't bury this in code; make it an env var.

## Inngest (Serverless-Friendly)

```bash
npm install inngest
```

```ts
import { Inngest } from 'inngest'

export const inngest = new Inngest({ id: 'water-vending' })

export const orderConfirmation = inngest.createFunction(
  { id: 'send-order-confirmation', retries: 3 },
  { event: 'order/created' },
  async ({ event, step }) => {
    const order = await step.run('fetch-order', () =>
      prisma.order.findUnique({ where: { id: event.data.orderId } }),
    )
    await step.run('send-email', () => sendEmail(order))
  },
)

// Trigger
await inngest.send({ name: 'order/created', data: { orderId } })
```

`step.run` is automatic checkpointing — if the function fails mid-way, Inngest replays from the last completed step. Great for long flows on platforms with timeouts.

## Long-Running Processes

For work that genuinely takes minutes (PDF generation, video processing, ML inference):

- **Bound the per-job wall time** — kill at N minutes, mark failed, retry separately.
- **Send progress updates** to a Redis key the UI can poll, or to an SSE stream.
- **Heartbeat** — periodic "still alive" so monitoring distinguishes slow from stuck.
- **Cancellation token** — let the user abort.

```ts
new Worker('reports', async (job) => {
  for (let i = 0; i < totalRows; i++) {
    if (await isCancelled(job.id)) return
    await processRow(rows[i])
    if (i % 100 === 0) await job.updateProgress((i / totalRows) * 100)
  }
})
```

Client polls `job.getState()` and `job.progress` via your API.

## Job Monitoring

### BullMQ Dashboard

```bash
npm install bull-board
```

```ts
import { createBullBoard } from '@bull-board/api'
import { BullMQAdapter } from '@bull-board/api/bullMQAdapter'
import { ExpressAdapter } from '@bull-board/express'

const serverAdapter = new ExpressAdapter()
serverAdapter.setBasePath('/admin/queues')
createBullBoard({ queues: [new BullMQAdapter(emailQueue)], serverAdapter })

app.use('/admin/queues', requireAdmin, serverAdapter.getRouter())
```

UI shows waiting/active/completed/failed jobs, retry/delete, view payloads. Gate behind admin auth.

### Metrics to Watch

- **Queue depth (waiting count)** — spike = workers can't keep up.
- **Active count** — should stay below worker concurrency × instances.
- **Failed count growth** — should be near zero; non-zero = bug or transient issue.
- **Mean job duration** — regressions signal slowness in the work itself.

Alert on:

- Queue depth > N for 10 min.
- Failed/min above baseline.
- No completed jobs in 10 min when there should be (worker dead).

## Worker Deployment

- **Separate process from the web server.** Don't run workers inside the API container.
- **Horizontal scaling** — multiple worker instances pull from the same queue. BullMQ handles distribution.
- **Concurrency knob per worker** — start at 5–10 per instance, tune by observation.
- **Graceful shutdown** — on SIGTERM, finish active jobs, then exit. BullMQ's `worker.close()` waits.

```ts
process.on('SIGTERM', async () => {
  await worker.close()
  process.exit(0)
})
```

## Common Mistakes

- **Running workers in the web process.** Slow jobs starve request handling. Separate processes.
- **No retries.** First transient failure loses the job.
- **Infinite retries.** Stuck jobs hammer downstream forever. Cap attempts.
- **Retrying validation failures.** Won't change on retry. Throw non-retryable, dead-letter.
- **No `jobId` for dedupe.** Double-enqueue runs the work twice.
- **Non-idempotent worker logic.** Retries double-charge, duplicate-create.
- **No DLQ alerting.** Failures pile up silently.
- **Cron without idempotency.** Vercel/Cloudflare retry on failure → duplicate runs.
- **Server-local timezone.** Production runs in UTC; "9am" fires at 11pm local. Set `tz`.
- **Logging job payloads with secrets.** Tokens, PII. Redact at the logger.
- **No monitoring UI.** Production incident requires SSH-and-pray. Add Bull Board or equivalent.
- **No graceful shutdown.** Deploys kill in-flight jobs mid-write. Handle SIGTERM.
- **Massive payload in the job data.** Move big blobs to S3, pass the key.
- **No cancellation for long jobs.** User clicks cancel; job runs for 20 more minutes.
- **Single worker, single instance.** Outage kills throughput. Run 2+.
- **Worker fetches and modifies the same row without locking.** Two workers race on the same item. Use `SELECT ... FOR UPDATE SKIP LOCKED` or a unique-jobId lock.
