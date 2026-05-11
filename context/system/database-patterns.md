# Database Patterns

Standards for schema design, queries, and migrations. Applies to PostgreSQL (default) with Prisma as the ORM unless otherwise specified.

## Schema Design Principles

### Normalization vs Denormalization

Default to 3NF (third normal form). Denormalize only when you have measured a real read-performance problem and other options (indexes, caching, materialized views) are insufficient.

Normalize when:
- Data has clear entity boundaries with distinct lifecycles.
- The same fact would otherwise be stored in multiple places (update anomalies).
- Writes outnumber reads or are correctness-critical.

Denormalize when:
- A read path is hot and joins are the bottleneck.
- A computed value is expensive and acceptably stale (store with `computed_at` timestamp).
- A historical snapshot is needed (line items copy product name and price at order time, not by FK alone).

Order line items should always copy `unit_price` and `product_name` at purchase time — never join back to `products` to compute an old order's total. Product names and prices change.

## Naming Conventions

- Tables: plural, `snake_case`. `users`, `order_items`, `audit_logs`.
- Columns: `snake_case`. `created_at`, `email_verified_at`.
- Primary keys: `id`. Use UUID v7 (time-ordered) or BIGSERIAL. Avoid v4 UUIDs as primary keys — they kill index locality.
- Foreign keys: `<singular_table>_id`. `user_id`, `order_id`.
- Booleans: prefix with `is_`, `has_`, or end with `_at` for nullable timestamp flags (`deleted_at` is preferable to `is_deleted`).
- Junction tables: alphabetical concatenation. `roles_users`, `products_tags`.
- Indexes: `idx_<table>_<columns>`. Unique: `uniq_<table>_<columns>`.
- Prisma models: `PascalCase` singular. Map to snake_case via `@@map("users")`.

```prisma
model User {
  id        String   @id @default(uuid()) @db.Uuid
  email     String   @unique
  createdAt DateTime @default(now()) @map("created_at")
  updatedAt DateTime @updatedAt @map("updated_at")

  @@map("users")
}
```

## Migration Practices

- Always use migrations. Never modify production schema with ad-hoc SQL.
- One migration per logical change. Don't bundle unrelated schema changes.
- Migrations must be reversible in development. Prisma generates up-only by default; write a manual `down` SQL alongside for destructive changes.
- Never edit a migration after it has been applied to a shared environment (staging, prod). Write a new migration to correct it.
- Backfills go in their own migration, separate from schema changes. For large tables, write a script that runs in batches outside the migration system.
- Adding a NOT NULL column to a non-empty table requires three steps: add as nullable → backfill → set NOT NULL. Each in its own migration.
- Dropping a column is a two-deploy operation: deploy code that no longer reads/writes it → then drop in a later migration.

### Seed Data

Keep dev seeds in `prisma/seed.ts`. Seeds should be idempotent — running twice should produce the same result. Use `upsert`, not `create`.

```ts
await prisma.user.upsert({
  where: { email: 'admin@example.com' },
  update: {},
  create: { email: 'admin@example.com', name: 'Admin', role: 'ADMIN' },
})
```

Never run seeds against production. Gate with `if (env.NODE_ENV !== 'production') throw ...`.

## ORM vs Raw SQL

Prefer Prisma for:
- Standard CRUD and filtering.
- Anything touching auth, billing, or audited data — type safety prevents column-name typos.
- Transactions across multiple tables (`prisma.$transaction`).

Drop to raw SQL (`prisma.$queryRaw`) for:
- Window functions, recursive CTEs, complex aggregations.
- Full-text search using `tsvector`/`to_tsquery`.
- Bulk operations where the ORM generates inefficient SQL (e.g., 1000-row inserts — use `createMany` first, raw COPY only if necessary).
- Queries that need database-specific features (PostgreSQL `JSONB` operators, partial indexes).

When using `$queryRaw`, always use the tagged template form to parameterize:

```ts
const users = await prisma.$queryRaw<User[]>`
  SELECT * FROM users WHERE email = ${email}
`
```

Never interpolate user input into a raw query string — that's SQL injection.

## Indexing Strategy

- Every foreign key needs an index. Prisma does not create these automatically except when the FK is also unique.
- Index columns you filter or sort by, not columns you only select.
- Composite indexes are ordered: `(status, created_at)` serves `WHERE status = ?` and `WHERE status = ? ORDER BY created_at`, but not `WHERE created_at > ?` alone.
- For `WHERE deleted_at IS NULL` (soft delete), use a partial index: `CREATE INDEX ... WHERE deleted_at IS NULL`.
- Run `EXPLAIN ANALYZE` on any slow query before adding an index. Confirm the index is used and the plan improves.
- Don't over-index. Every index slows writes and consumes disk. Drop indexes you don't use (`pg_stat_user_indexes`).

## Soft Delete vs Hard Delete

Default to **hard delete** unless one of these applies:

- Legal/compliance requires retention.
- Users can undo a delete from the UI.
- The row is referenced from immutable records (orders, invoices) and FK constraints would break.

When soft deleting, use a nullable `deleted_at TIMESTAMPTZ`. Add a partial index `WHERE deleted_at IS NULL`. Filter every query — Prisma does not do this automatically. Consider a middleware or a `BaseService` that applies the filter.

Soft delete leaks. Unique constraints (like `email`) need to either include `deleted_at` or be enforced via partial unique index:

```sql
CREATE UNIQUE INDEX uniq_users_email_active ON users (email) WHERE deleted_at IS NULL;
```

## Timestamp Conventions

Every table has:

- `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- `updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` — Prisma updates this via `@updatedAt`.

Always store in UTC (`TIMESTAMPTZ`, not `TIMESTAMP`). Convert to user timezone in the application layer.

For business events with their own time (`shipped_at`, `cancelled_at`, `email_verified_at`), use nullable `TIMESTAMPTZ` and set when the event happens. Don't use a separate boolean — the timestamp encodes both the state and when it transitioned.

## Common Patterns

### Audit Logs

For tables that need change history:

```prisma
model AuditLog {
  id         String   @id @default(uuid()) @db.Uuid
  entityType String   @map("entity_type")
  entityId   String   @map("entity_id")
  action     String   // 'create' | 'update' | 'delete'
  actorId    String?  @map("actor_id")
  before     Json?
  after      Json?
  createdAt  DateTime @default(now()) @map("created_at")

  @@index([entityType, entityId])
  @@index([actorId])
  @@map("audit_logs")
}
```

Write to it inside the same transaction as the change. Never log "after the fact" — you'll miss failed/rolled-back changes.

### Many-to-Many with Join Tables

Always use an explicit join table when the relationship has attributes (when it was added, who added it, role within the relationship). Use Prisma's implicit M:N only for pure tagging.

```prisma
model UserRole {
  userId    String   @map("user_id") @db.Uuid
  roleId    String   @map("role_id") @db.Uuid
  grantedAt DateTime @default(now()) @map("granted_at")
  grantedBy String?  @map("granted_by") @db.Uuid

  user User @relation(fields: [userId], references: [id])
  role Role @relation(fields: [roleId], references: [id])

  @@id([userId, roleId])
  @@map("user_roles")
}
```

### Polymorphic Associations

Avoid them. They break foreign key integrity. If you must have one entity that points to "any of these other entities," prefer:

1. A single column per related table, with a CHECK constraint that exactly one is non-null.
2. Separate join tables per related type (more tables, but FK integrity preserved).

Use polymorphic only for low-stakes data (comments, reactions) and accept that the database cannot enforce referential integrity.

### Money

Never store money as a float. Use `DECIMAL(12, 2)` for currency amounts, or store the smallest unit (cents) as `INTEGER`. Pick one convention per project and document it.

```prisma
priceCents Int @map("price_cents")
```

## Common Mistakes

- **No index on foreign keys.** Joins crawl. Add the index even if Prisma didn't.
- **Float for money.** `0.1 + 0.2 !== 0.3`. Use decimal or integer cents.
- **Boolean flags instead of timestamps.** `is_deleted = true` tells you nothing about when. Use `deleted_at`.
- **Editing applied migrations.** Breaks any environment where the old migration ran. Always write a new one.
- **Missing `created_at`/`updated_at`.** You will always wish you had them.
- **Storing local times.** Always UTC. Convert at the edge.
- **Wide tables (40+ columns).** Usually a sign two entities have been collapsed. Split them.
- **No backups before destructive migrations.** Take a snapshot before dropping anything in prod.
- **`SELECT *` in production code.** Returns extra data, breaks when columns are added, ruins covering-index optimizations. Be explicit.
- **Implicit cascades.** `ON DELETE CASCADE` is fine for owned children (order items belong to an order), dangerous everywhere else. Spell out the intent.
- **Using `OFFSET` for deep pagination.** Page 1000 of 50/page scans 50,000 rows. Use cursor pagination.
