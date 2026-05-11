# Backend Architecture

Server-side architecture standards for Node.js/TypeScript backends (Express or Hono). Read this before writing any server code.

## API Design Principles

### REST Conventions

- Resources are nouns, not verbs. `/users`, not `/getUsers`.
- Use plural nouns for collections: `/orders`, `/products`.
- Nest resources only one level deep: `/users/:id/orders` is fine; `/users/:id/orders/:id/items` is not — flatten to `/orders/:id/items`.
- Actions that don't map cleanly to CRUD use POST on a sub-path: `POST /orders/:id/cancel`, not `POST /cancelOrder`.

### HTTP Methods

- `GET` — read, never mutates state. Safe and idempotent.
- `POST` — create a new resource, or trigger a non-idempotent action.
- `PUT` — replace a resource entirely. Idempotent.
- `PATCH` — partial update. Send only the fields that change.
- `DELETE` — remove a resource. Idempotent.

### Status Codes

Always return the most specific code that applies.

- `200 OK` — successful GET, PATCH, PUT.
- `201 Created` — successful POST that created a resource. Return the created object in the body, and include `Location` header pointing to the new resource.
- `204 No Content` — successful DELETE or update that returns nothing.
- `400 Bad Request` — malformed request, validation failure.
- `401 Unauthorized` — missing or invalid auth credentials.
- `403 Forbidden` — authenticated but not allowed.
- `404 Not Found` — resource does not exist.
- `409 Conflict` — duplicate resource, version conflict.
- `422 Unprocessable Entity` — well-formed but semantically invalid.
- `429 Too Many Requests` — rate limit exceeded.
- `500 Internal Server Error` — unhandled exception. Should be rare.
- `503 Service Unavailable` — dependency down, maintenance.

Never return `200` with `{ error: "..." }` in the body. Use the right status code.

### Pagination

Use cursor-based pagination for any endpoint that may return more than ~100 items. Offset pagination is acceptable for small admin tables but breaks under concurrent inserts.

```ts
// Response shape
{
  data: T[],
  nextCursor: string | null,  // opaque, base64-encoded
  hasMore: boolean
}
```

Query params: `?cursor=<opaque>&limit=20`. Cap `limit` at 100.

### Filtering and Sorting

- Filtering: `?status=active&category=electronics`. Combine with AND semantics.
- Sorting: `?sort=createdAt:desc,name:asc`. Whitelist sortable fields server-side.
- Search: `?q=<term>`. Distinct from filtering — full-text or partial match.

## Project Structure

Organize by feature, not by layer. A feature folder owns its routes, handlers, validation, and tests.

```
src/
├── server.ts                 # entry point, app composition
├── config/
│   ├── env.ts                # validated env variables
│   └── logger.ts             # logger instance
├── middleware/
│   ├── auth.ts
│   ├── errorHandler.ts
│   ├── rateLimit.ts
│   └── requestId.ts
├── features/
│   ├── users/
│   │   ├── users.routes.ts
│   │   ├── users.service.ts
│   │   ├── users.schema.ts   # Zod schemas
│   │   └── users.test.ts
│   └── orders/
│       └── ...
├── lib/
│   ├── errors.ts             # custom error classes
│   └── db.ts                 # Prisma client
└── types/
    └── express.d.ts          # request augmentation
```

Never put business logic in route handlers. Routes parse input, call services, return responses. Services contain the logic.

## Request Validation

Always validate at the boundary. Use Zod for runtime validation; derive TypeScript types from schemas with `z.infer`.

```ts
import { z } from 'zod'

export const createUserSchema = z.object({
  body: z.object({
    email: z.string().email(),
    name: z.string().min(1).max(100),
    age: z.number().int().min(13).max(120).optional(),
  }),
})

export type CreateUserInput = z.infer<typeof createUserSchema>['body']
```

Wire validation as middleware so handlers receive parsed, typed data:

```ts
export const validate = (schema: z.ZodSchema) =>
  (req: Request, res: Response, next: NextFunction) => {
    const result = schema.safeParse({ body: req.body, query: req.query, params: req.params })
    if (!result.success) {
      return next(new ValidationError(result.error.flatten()))
    }
    req.body = result.data.body
    req.query = result.data.query
    req.params = result.data.params
    next()
  }
```

## Error Handling

### Custom Error Classes

Define a base error class and extend it for each error type. Never throw plain `Error` from business logic.

```ts
export class AppError extends Error {
  constructor(
    public message: string,
    public statusCode: number,
    public code: string,
    public details?: unknown,
  ) {
    super(message)
    this.name = this.constructor.name
  }
}

export class NotFoundError extends AppError {
  constructor(resource: string) {
    super(`${resource} not found`, 404, 'NOT_FOUND')
  }
}

export class ValidationError extends AppError {
  constructor(details: unknown) {
    super('Validation failed', 400, 'VALIDATION_ERROR', details)
  }
}

export class UnauthorizedError extends AppError {
  constructor(message = 'Authentication required') {
    super(message, 401, 'UNAUTHORIZED')
  }
}
```

### Global Error Handler

Register last in the middleware chain. Catches everything, returns structured responses.

```ts
export const errorHandler = (
  err: Error,
  req: Request,
  res: Response,
  _next: NextFunction,
) => {
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      error: {
        code: err.code,
        message: err.message,
        details: err.details,
        requestId: req.id,
      },
    })
  }

  logger.error({ err, requestId: req.id }, 'Unhandled error')

  return res.status(500).json({
    error: {
      code: 'INTERNAL_ERROR',
      message: 'An unexpected error occurred',
      requestId: req.id,
    },
  })
}
```

### Async Handlers

Wrap async route handlers so rejections reach the error middleware:

```ts
export const asyncHandler = (fn: RequestHandler): RequestHandler =>
  (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next)
```

## Middleware Patterns

Order matters. Typical chain:

1. Request ID (correlation)
2. Request logger
3. CORS
4. Security headers (Helmet)
5. Body parser
6. Rate limiter
7. Authentication
8. Authorization (per-route)
9. Routes
10. 404 handler
11. Error handler

### Authentication Middleware

```ts
export const requireAuth: RequestHandler = (req, res, next) => {
  const token = req.headers.authorization?.replace('Bearer ', '')
  if (!token) throw new UnauthorizedError()
  try {
    const payload = verify(token, env.JWT_SECRET) as JwtPayload
    req.user = payload
    next()
  } catch {
    throw new UnauthorizedError('Invalid or expired token')
  }
}
```

### Rate Limiting

Use `express-rate-limit` or equivalent. Apply globally with sensible defaults, override per-route for sensitive endpoints (login, password reset).

## Environment Configuration

Never hardcode secrets. Never commit `.env`. Validate env at startup — fail fast if anything is missing.

```ts
import { z } from 'zod'
import 'dotenv/config'

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']),
  PORT: z.coerce.number().default(3000),
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
})

export const env = envSchema.parse(process.env)
```

Commit `.env.example` with placeholder values so teammates know what to set.

## Logging Standards

Use structured JSON logs (Pino is the default). Never use `console.log` in server code.

### Log Levels

- `debug` — verbose, dev-only. Request payloads, internal state.
- `info` — significant events. Server start, request completed, user signed up.
- `warn` — recoverable problems. Deprecated endpoint hit, retry succeeded after failure.
- `error` — failures that need attention. Unhandled exceptions, external API down.
- `fatal` — process is about to exit. Use sparingly.

### What to Log

Every log line includes:

- `requestId` for correlation
- `userId` if authenticated
- Timestamp (Pino adds this automatically)
- The event being logged, as a short message

```ts
logger.info({ requestId: req.id, userId: req.user?.id, orderId }, 'Order created')
```

Never log: passwords, tokens, full credit card numbers, PII unless required for audit (and even then, scope tightly).

## Common Mistakes

- **Business logic in route handlers.** Routes orchestrate; services execute. Keep them separate.
- **Trusting `req.body` without validation.** Always run through Zod first.
- **Returning `200` with an error in the body.** Use real status codes.
- **Catching errors and returning `null`.** Silent failure hides bugs. Let errors propagate to the global handler.
- **Using `console.log` instead of a structured logger.** Logs are searched by machines; give them structure.
- **Hardcoding URLs, secrets, or feature flags.** Use env vars. Validate them at boot.
- **Single huge `routes.ts` file.** Split by feature.
- **Forgetting to wrap async handlers.** Unhandled promise rejections crash the process or get swallowed.
- **Not setting `Location` header on 201.** Clients expect it for the canonical URL of the new resource.
- **Logging the entire request body.** PII and secrets leak this way. Log identifiers and outcomes, not payloads.
