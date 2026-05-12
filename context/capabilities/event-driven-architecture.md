# Event-Driven Architecture

How to decouple services with events instead of synchronous calls. Read before splitting a monolith, integrating with a third party, or building anything claiming to be "real-time."

## Decision Tree

| Need | Pick |
|---|---|
| In-process pub/sub | **EventEmitter** (Node built-in) |
| Cross-process, single host | **Redis Pub/Sub** or **Redis Streams** |
| Distributed, durable, replay | **NATS JetStream**, **Kafka**, **AWS EventBridge** |
| Cloud-managed, simple fan-out | **AWS SNS + SQS**, **GCP Pub/Sub** |
| Outbound integrations | **Webhooks** (HTTP POST) |
| Time-travel state, audit trail | **Event sourcing** |
| Heavy read/write separation | **CQRS** (with or without event sourcing) |

Start with **Redis Streams** + a job queue (BullMQ). Reach for Kafka/NATS only when scale or durability genuinely require it.

## Events vs Commands

Distinguish the two — confusing them is a common cause of bad designs.

- **Command** — "do this." Imperative. One handler. Returns success/failure to the caller.
- **Event** — "this happened." Past tense. Zero-to-many handlers. Caller doesn't wait or care.

`CreateOrder` is a command. `OrderCreated` is an event emitted after the command succeeds.

Routes accept commands; the system emits events.

## In-Process Pub/Sub

Easiest. Useful for decoupling within one service.

```ts
import EventEmitter from 'node:events'

interface AppEvents {
  'order.created': (payload: { orderId: string; userId: string }) => void
  'order.cancelled': (payload: { orderId: string }) => void
}

export const bus = new EventEmitter() as EventEmitter & {
  on<K extends keyof AppEvents>(e: K, fn: AppEvents[K]): unknown
  emit<K extends keyof AppEvents>(e: K, ...args: Parameters<AppEvents[K]>): boolean
}

bus.on('order.created', (p) => sendConfirmationEmail(p.orderId))
bus.on('order.created', (p) => incrementAnalytics('orders', p))
```

Use only for things that can fail and be retried without leaving the system inconsistent. Handlers run synchronously; an exception in one doesn't stop the others (depending on emitter).

## Redis Pub/Sub vs Streams

**Pub/Sub** is fire-and-forget. If no subscriber is connected, the message is gone.

**Streams** are durable. Messages persist, support consumer groups (fan-out + load balancing), and survive subscriber restarts.

Default to **Streams**. Use Pub/Sub only for transient notifications (presence updates, cache invalidation pings).

```ts
import { Redis } from 'ioredis'

const redis = new Redis(env.REDIS_URL)

// Publish
await redis.xadd('orders', '*', 'event', 'order.created', 'data', JSON.stringify(payload))

// Consume (in a worker)
async function consume() {
  while (true) {
    const res = await redis.xreadgroup(
      'GROUP', 'order-emails', 'worker-1',
      'COUNT', 10, 'BLOCK', 5000,
      'STREAMS', 'orders', '>',
    )
    if (!res) continue
    for (const [, messages] of res) {
      for (const [id, fields] of messages) {
        try {
          await handle(fields)
          await redis.xack('orders', 'order-emails', id)
        } catch {
          // leave unacked; will be reclaimed
        }
      }
    }
  }
}
```

Consumer groups make this load-balance across workers and survive crashes.

## NATS JetStream

For multi-service architectures wanting durability without Kafka's operational weight:

- **Subjects** (topics) with hierarchical patterns.
- **Streams** persist messages; **consumers** read from streams.
- **At-least-once** delivery with ack/redelivery.
- Lightweight (single binary), good throughput, decent observability.

```ts
import { connect, StringCodec } from 'nats'

const nc = await connect({ servers: env.NATS_URL })
const js = nc.jetstream()
const codec = StringCodec()

await js.publish('orders.created', codec.encode(JSON.stringify(payload)))

const sub = await js.pullSubscribe('orders.created', { durable: 'order-emails' })
for await (const m of sub) {
  await handle(JSON.parse(codec.decode(m.data)))
  m.ack()
}
```

Pick NATS when Redis Streams isn't enough but Kafka is too much.

## Webhooks (External Integrations)

Outbound: notify another system when something happens.

```ts
async function fireWebhook(url: string, payload: unknown, secret: string) {
  const body = JSON.stringify(payload)
  const signature = crypto.createHmac('sha256', secret).update(body).digest('hex')

  await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Webhook-Signature': `sha256=${signature}`,
      'X-Webhook-Id': payload.eventId,
      'X-Webhook-Timestamp': new Date().toISOString(),
    },
    body,
  })
}
```

### Rules

- **Sign payloads.** HMAC with a per-subscriber secret. Receivers verify.
- **Include an `eventId`** for idempotency on the receiver's side.
- **Include a timestamp** to reject replays (receivers should refuse events older than 5 min).
- **Retry on 5xx and connection errors.** Exponential backoff. Cap attempts (Stripe goes 3 days; pick your tolerance).
- **Stop on 4xx.** The receiver said "this is wrong" — retrying won't fix it. Dead-letter and alert.
- **Document the schema.** Webhook payloads are an API contract.

### Inbound

When you receive webhooks, treat them like any other untrusted input:

- **Verify the signature.** Use raw body — JSON-parsing first breaks the hash.
- **Idempotency.** Dedupe by event ID.
- **Respond fast.** Ack in < 1 second; do real work in a job.

See `context/capabilities/payments.md` for full webhook patterns.

## Event Schema

Events are forever. Plan the shape.

```ts
type OrderCreated = {
  type: 'order.created'
  version: 1
  eventId: string
  occurredAt: string         // ISO 8601
  tenantId: string
  data: {
    orderId: string
    userId: string
    totalCents: number
    currency: string
  }
}
```

### Rules

- **Past tense.** `order.created`, not `create-order`.
- **Versioned.** Add fields freely; never remove or repurpose. For breaking shape changes, bump the version, emit both old and new during the transition.
- **Self-contained.** Include enough data that consumers don't have to call back for the basics.
- **No PII unless necessary.** Events are often replicated, archived, exported. Mask sensitive fields.

## Idempotent Handlers

Events are at-least-once. Same event arrives twice; both handlers must produce the same outcome.

```ts
async function handleOrderCreated(event: OrderCreated) {
  // Try to claim the event ID — fails if already processed
  const claimed = await prisma.processedEvent.create({
    data: { eventId: event.eventId, type: event.type },
  }).catch((e) => (e.code === 'P2002' ? null : Promise.reject(e)))

  if (!claimed) return     // duplicate, ignore

  await sendOrderConfirmation(event.data.orderId)
}
```

Or use natural keys — emails sent indexed by `eventId`, payments charged with `idempotencyKey: eventId`. The downstream's own dedupe carries the load.

## Event Sourcing (Brief Intro)

Instead of storing current state, store the **stream of events** that produced it. Current state is a fold over the stream.

```
Events: OrderCreated, OrderShipped, OrderDelivered
State:  status = 'delivered' (computed)
```

### When It Fits

- Audit trail is a hard requirement (financial systems, regulated industries).
- Complex domain with rich history queries.
- Time-travel debugging valuable.
- Multiple read models needed (CQRS).

### When It Doesn't

- Simple CRUD.
- Team unfamiliar with the pattern (learning cost is real).
- Small data, no audit need.

Event sourcing is powerful, not free. Migrations are harder; debugging is harder; eventual consistency is everywhere. Don't reach for it because it sounds cool.

## CQRS Basics

**Command Query Responsibility Segregation.** Reads and writes have different models.

- **Command side**: write model, normalized, optimized for consistency.
- **Query side**: read model(s), denormalized, optimized for the screens that read them.

Events bridge the two: writes emit events; projectors update the read models.

### When CQRS Fits

- Read and write loads differ wildly.
- Multiple read shapes (dashboard, search, mobile) from the same writes.
- Pairs naturally with event sourcing.

### When It Doesn't

Most apps. Premature CQRS is a frequent over-engineering trap.

## Outbox Pattern

When a transaction must both write to the DB and emit an event, "write then publish" can fail between the two. Use the outbox:

```sql
INSERT INTO orders (id, ...) VALUES (...);
INSERT INTO event_outbox (event_id, type, payload) VALUES (...);
-- both in the same transaction
```

A separate process polls `event_outbox`, publishes to the bus, marks rows sent.

This guarantees: if the order exists, the event will be published (eventually).

## Common Mistakes

- **Synchronous handler chain in the request path.** "Notify analytics, send email, charge card" — slow request, half-applied on failure. Emit events and let handlers run async.
- **Events with no version.** First schema change is painful.
- **Removing or repurposing event fields.** Breaks every downstream forever.
- **Non-idempotent handlers.** At-least-once delivery doubles your effects.
- **Trusting in-order delivery.** Most buses don't guarantee global ordering. Design handlers to tolerate any order.
- **No DLQ / unacked monitor.** Failed events pile up silently.
- **Pub/Sub when you need durability.** Subscribers offline → messages lost.
- **Publishing before persisting.** Crash between publish and DB write → ghost event with no underlying state. Use the outbox.
- **Verifying webhook signatures against parsed JSON.** The hash is over the raw body.
- **Replaying events without a snapshot.** Replaying years of history to compute current state takes forever. Take periodic snapshots.
- **One handler per consumer group at infinite concurrency.** Race conditions. Limit concurrency per stream key (per-aggregate).
- **Big payloads in events.** Storage and bandwidth balloon. Pass references (IDs); load details on the consumer side if needed.
- **Tight coupling via shared event types.** When every service imports the same `events.ts`, you've just moved the monolith to npm. Treat event schemas as a contract you publish, not a library you share by file path.
- **Sync code that should be a saga.** Long-running multi-service flows need explicit orchestration (Temporal, Inngest), not a chain of events.
- **No idempotency key on commands.** Command retry creates duplicates. Pass and check one.
