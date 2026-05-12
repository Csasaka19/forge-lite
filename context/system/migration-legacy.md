# Migrations & Legacy Systems

How to replace, evolve, or extract systems without breaking what's running. Read before any rewrite, framework swap, or database migration.

## Decision Tree: How to Migrate

| Situation | Approach |
|---|---|
| Rewriting an entire service | **Strangler fig** — incremental replacement behind a router |
| Changing API shape | **Versioning** — run v1 and v2 in parallel with deprecation timeline |
| Schema change with type/semantic shift | **Dual-write** — write to both, read from new when ready |
| Replacing a database engine | **CDC** (change data capture) → replay → cutover |
| Frontend framework swap | **Micro-frontends** or **page-by-page** behind a reverse proxy |
| Bulk data shape change | **ETL** with dry runs, validation, and rollback |

**Never big-bang.** Any migration that fails on cutover day with no rollback path is a future incident.

## Strangler Fig Pattern

Coined by Martin Fowler. Build the replacement around the legacy system; route traffic incrementally; the legacy "dies" by attrition.

### Pattern

1. **Place a router in front** of the legacy system (reverse proxy, API gateway, or thin app layer).
2. **Build the new system in parallel.** Same external contract, different implementation.
3. **Route one endpoint or one feature at a time** to the new system.
4. **Validate** — same inputs produce equivalent outputs (or intentionally-different-better outputs).
5. **Repeat** until the legacy system has no traffic.
6. **Decommission** the legacy.

### Example: Replacing a Monolith

```
Before:
client → monolith

Phase 1 — proxy in front:
client → proxy → monolith

Phase 2 — new service for one feature:
client → proxy → orders-service (new)   for /orders/*
              → monolith                for everything else

Phase 3 — more features migrated:
client → proxy → orders-service
              → users-service
              → monolith                for the shrinking remainder

Phase n — monolith retired
```

### Rules

- **The proxy is a real component**, not a temporary hack. Treat it as production infrastructure with monitoring and tests.
- **Route at the lowest sensible granularity.** Per-endpoint is the safest; per-customer is finer; per-request randomization is highest-risk.
- **Keep contracts stable.** The new system implements the same external interface unless you're explicitly evolving it.
- **Plan for parallel running** — both systems may need shared state (database, cache, queue). Decide how before splitting.

### When Strangler Doesn't Work

- The legacy system can't be put behind a proxy (deeply embedded UI, hardware).
- Contracts are too coupled to extract a single feature cleanly.
- No team capacity to maintain both systems during the transition.

In those cases, the answer is sometimes "don't migrate; build green-field with no legacy reuse." That has its own risks but is honest about the choice.

## API Versioning During Migration

When changing API shape, run **both versions** in parallel until clients move.

### Versioning Strategy

- **URL path versioning**: `/v1/orders`, `/v2/orders`. Simplest. Cache-friendly.
- Add `v2` when v1 has been frozen — bug fixes only on v1.
- Never delete v1 silently. Set a sunset date in headers + docs.

```
Deprecation: true
Sunset: Wed, 31 Dec 2026 23:59:59 GMT
Link: <https://api.example.com/v2/orders>; rel="successor-version"
```

### Deprecation Timeline

```
T-0       v2 released; v1 still default.
T+3 mo    v1 marked deprecated. Sunset announced.
T+9 mo    v1 starts returning warnings in response headers.
T+12 mo   v1 returns 410 Gone after the sunset date.
```

Adjust by audience. Internal APIs can deprecate faster; public APIs need months or years.

### Behind the Scenes

The two versions can share the same handler with a thin adapter:

```ts
function v1OrderShape(order: Order): V1Order {
  return { id: order.id, total: order.priceCents / 100, /* v1 fields */ }
}

app.get('/v1/orders/:id', async (req, res) => {
  const order = await orders.findById(req.params.id)
  res.json(v1OrderShape(order))
})

app.get('/v2/orders/:id', async (req, res) => {
  const order = await orders.findById(req.params.id)
  res.json(order)                             // canonical v2 shape
})
```

Two thin endpoints, one core implementation. Easier to maintain than two parallel codebases.

## Database Migration

The hardest kind. Data has gravity; downtime is expensive; rollback after corruption is sometimes impossible.

### Dual-Write Pattern

For schema changes that can't be done in place.

1. **Write to both old and new** schemas in application code.
2. **Backfill** old data into the new schema (background job, batch).
3. **Validate** that old and new agree on every row.
4. **Switch reads to new** while still dual-writing.
5. **Stop writing to old.**
6. **Drop old.**

Each phase is its own deploy with its own rollback. Skipping is how data gets lost.

```ts
async function createOrder(input: OrderInput) {
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.create({ data: input })

    if (env.DUAL_WRITE_NEW_SCHEMA) {
      await tx.orderV2.create({ data: toV2Shape(order) })
    }
    return order
  })
}
```

Behind a feature flag so you can switch off if it starts failing.

### Change Data Capture (CDC)

For database engine swaps (Postgres → another Postgres, MySQL → Postgres, on-prem → managed):

1. **Snapshot** the source database at a point in time.
2. **Restore** to the target.
3. **Replay changes** from the source's write-ahead log into the target, continuously.
4. When target is caught up and validated, **cut over** application writes to the target.
5. **Rollback path**: if target diverges, the source is still authoritative until you formally cut over.

Tools: **Debezium**, **pgstream**, **AWS DMS**, **Bucardo**. Pick one with explicit consistency semantics and good failure modes.

### Event Sourcing for Migrations

If the legacy system records events (orders, transactions, log-style), replay them through the new system. The new system processes the historical event stream and arrives at the current state — verifiable against the legacy.

This works well when the domain is naturally event-shaped (financial ledgers, audit logs). It's overkill when it isn't.

### Rules

- **Backup before every step.** Verify the backup restores before continuing.
- **Run on staging first.** With a production-shaped dataset.
- **Set a hard freeze window** for the cutover. Communicate it. Practice the procedure.
- **Have a written rollback plan.** "Restore from snapshot at T-1h and replay." Test it.

## Frontend Migration

### Micro-Frontends

Each route owned by a separate codebase, composed at the edge or in a shell app.

- **Module Federation** (Webpack 5+, Vite via plugin) — runtime composition.
- **Iframe** — old, ugly, but isolating. Works when stacks can't otherwise coexist.
- **Reverse proxy** — `/checkout` served by old app, `/orders` by new. No JS-level integration.

Pick the lowest-coupling option that works. Module Federation is powerful but introduces shared-version headaches; reverse-proxy splitting is simpler when feasible.

### Page-by-Page Migration

For SPAs, route a subset of pages to the new framework via a reverse proxy.

```
/                 → new app
/dashboard        → new app
/legacy-form      → old app
/legacy-settings  → old app
```

User signs in once (shared auth cookie scoped to the parent domain) and moves between apps seamlessly.

### Iframe Bridge

When old and new must share a screen:

- Embed the legacy as an iframe.
- Communicate via `postMessage` with a typed protocol on both sides.
- Authenticate the iframe's origin in the message handler — never accept messages from any origin.

```ts
window.addEventListener('message', (e) => {
  if (e.origin !== env.LEGACY_ORIGIN) return
  // safe to process
})
```

Iframe bridges are a transitional tool, not a permanent design. Set a sunset.

## Data Migration

For bulk transformations: schema changes, importing from another system, normalizing a denormalized model.

### ETL Discipline

1. **Extract** — read from source. Read-only; never write.
2. **Transform** — map old shape to new in code, not in a hand-written SQL statement.
3. **Load** — write to target, idempotent (`UPSERT` or `INSERT ... ON CONFLICT`).

```ts
async function migrateOrder(legacy: LegacyOrder) {
  const transformed = {
    id: legacy.order_id,
    machineId: legacy.machineId,
    totalCents: Math.round(legacy.total * 100),   // float → integer cents
    createdAt: new Date(legacy.created),
    status: mapStatus(legacy.state),
  }
  await prisma.order.upsert({
    where: { id: transformed.id },
    create: transformed,
    update: transformed,
  })
}
```

### Validation

Before cutting over, validate:

- **Row counts match** between source and target (allowing for filtered-out rows by design).
- **Spot-check** a random sample (50–100 rows) end-to-end.
- **Sum invariants** — total revenue, total active users, count by status — match within tolerance.
- **Foreign key integrity** — every reference resolves.

Automated validation script, run after every migration step.

### Dry Run

Always run the migration end-to-end against a staging copy of production. Time it; collect failures; adjust. Never run a migration script against production for the first time.

### Rollback Plan

Before running:

1. **Snapshot** the database immediately before.
2. **Test the restore** on a sandbox.
3. **Write down the exact rollback command.** Not "we'll figure it out" — the literal command.
4. **Decision rule**: if X% of rows fail validation, rollback. Define X up front.

Idempotent migration scripts are safer because re-running is harmless. Strive for that.

## Feature Flags for Migration

Migration is high-stakes; feature flags let you cut blast radius.

### Patterns

- **Per-user**: enable for specific accounts (your team, beta users).
- **Per-percentage**: 1% → 10% → 50% → 100%, with a soak period at each step.
- **Per-cohort**: by region, by plan tier, by signup date.
- **Kill switch**: a single boolean to revert everything to the old path instantly.

```ts
if (flags.useNewOrderService.isEnabled({ userId: req.user.id })) {
  return newOrderService.create(input)
}
return legacyOrderService.create(input)
```

### Rules

- **Default off** for any flag in production until validated.
- **Monitor both paths** — error rates and latency for old and new, side by side.
- **Time-box flags.** A migration flag that lives past cutover becomes permanent technical debt. Schedule its removal.
- **Test the kill switch.** Practice flipping it back before you need to.

Use a managed flag service (LaunchDarkly, GrowthBook, Statsig, Unleash) for anything serious. Hand-rolled flags drift and lack the targeting controls.

## Decision Log

Every architectural decision during the migration goes in a decision log — usually an ADR (`docs/adr/`).

```markdown
# ADR 0012: Migrate orders table to event-sourced model

- Status: Accepted
- Date: 2026-05-11
- Deciders: Clive, Marta, the platform team

## Context
Legacy orders table is a denormalized snapshot. Audit requirements
mandate per-field change history, which is impractical with row-level
updates.

## Decision
Adopt event sourcing for orders. Order state is the fold of an append-only
event stream. Read models are projections.

## Migration Path
1. Build new event store + projection alongside the existing table.
2. Dual-write: every API write produces an event and updates the table.
3. Backfill historical events from the existing table.
4. Switch read paths to projections (behind a feature flag).
5. Stop writing to the table; drop after 60 days.

## Rollback
If projection lag exceeds 30s sustained, flip the flag back to table reads.
Backfill any missed projection updates from the event log.

## Consequences
- Audit and history come for free.
- Read patterns require new projections, more code.
- Storage grows linearly with event count; partitioning planned.
```

Document **before and after** so future maintainers know what the migration changed and why.

## Common Mistakes

- **Big-bang cutover with no rollback.** The single most expensive pattern in software. Always have a way back.
- **No proxy in front of the legacy.** Strangler fig requires the routing layer; without it, you're rewriting in place.
- **Deleting the old code before traffic has moved.** Lost rollback option, immediate panic when issues surface.
- **Skipping the dual-write phase on schema migration.** Discover the bugs after data is already in the new shape and the old is gone.
- **Dropping the v1 API the day v2 ships.** Clients haven't moved; outage. Run in parallel.
- **No deprecation timeline on retired APIs.** Clients have no signal to upgrade; eventually they break unexpectedly.
- **No validation script post-migration.** "It worked" by feel. Add row-count and invariant checks.
- **Untested rollback.** First time you try the restore is during the incident. Test it before.
- **Feature flag left on forever.** Becomes invisible state. Time-box and remove.
- **Migration scripts that aren't idempotent.** A retry doubles or fails halfway. Always upsert.
- **Reading from old while writing to new.** Stale reads, then "we lost data!" panic. Decide explicitly which is the read source at each phase.
- **No decision log.** Two years later, nobody remembers why the migration was structured this way. Write it down.
- **Migrating without a freeze window.** Concurrent writes during cutover produce ghosts. Plan the freeze.
- **Trusting a single backup.** Verify the backup restores before relying on it. Test restores routinely.
- **Routing 100% of traffic at the first deploy.** Roll forward at 1% → 10% → 50% → 100%. Watch each step.
