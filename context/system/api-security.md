# API Security

Authentication, authorization, and defensive standards. Read before touching any endpoint that handles user data, credentials, or sensitive operations.

## Authentication Patterns

Pick exactly one auth method per API surface. Don't mix sessions and JWTs in the same client.

### JWT (Bearer Tokens)

Use for stateless APIs, mobile clients, and service-to-service auth.

- Sign with HS256 (symmetric, simple) or RS256 (asymmetric, for cross-service).
- Keep payloads small. Stuff identifiers and a role, not full user objects.
- Set short expiries: 15 minutes for access tokens. Refresh tokens last 7–30 days and rotate on use.
- Never store JWTs in `localStorage` for browser clients — XSS will steal them. Use httpOnly, Secure, SameSite=Strict cookies.

```ts
import { sign, verify } from 'jsonwebtoken'

export const issueAccessToken = (userId: string, role: string) =>
  sign({ sub: userId, role }, env.JWT_SECRET, { expiresIn: '15m' })
```

Always include `sub`, `iat`, `exp`. Verify all three on read. Reject tokens missing any of them.

### Session-Based

Use for traditional server-rendered apps and SPAs on the same domain.

- Store session ID in httpOnly, Secure, SameSite=Lax cookie.
- Server keeps session state in Redis or the database. Cookie holds only an opaque ID.
- Regenerate session ID on privilege change (login, role grant, password change) to prevent fixation.
- Set absolute and idle timeouts. Default: 30 days absolute, 2 hours idle.

### OAuth2 / OIDC

Use when delegating identity to a provider (Google, GitHub, Auth0, Cognito, Clerk) or building a public API others authorize against.

- Always use the Authorization Code flow with PKCE for public clients (SPAs, mobile).
- Never use the Implicit flow — deprecated.
- Validate `iss`, `aud`, `exp`, `nbf` on every ID token. Verify the signature against the provider's JWKS.
- Treat the ID token as proof of identity, not authorization. Look up the user in your own database and use your own roles.

## Authorization Patterns

Authentication answers "who are you." Authorization answers "what can you do." These are separate concerns and need separate middleware.

### RBAC (Role-Based Access Control)

Default choice for most apps. Each user has one or more roles; each route requires a role.

```ts
export const requireRole = (...allowed: Role[]): RequestHandler =>
  (req, res, next) => {
    if (!req.user) throw new UnauthorizedError()
    if (!allowed.includes(req.user.role)) throw new ForbiddenError()
    next()
  }

router.delete('/users/:id', requireAuth, requireRole('admin'), deleteUser)
```

### ABAC (Attribute-Based)

Use when permissions depend on data, not just role. "A user can edit their own posts but not others'."

```ts
export const requireOwnership = async (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction,
) => {
  const post = await prisma.post.findUnique({ where: { id: req.params.id } })
  if (!post) throw new NotFoundError('Post')
  if (post.authorId !== req.user.id && req.user.role !== 'admin') {
    throw new ForbiddenError()
  }
  req.resource = post
  next()
}
```

### Middleware Guards

Compose, don't repeat. A typical protected route:

```ts
router.patch(
  '/posts/:id',
  requireAuth,
  requireOwnership,
  validate(updatePostSchema),
  updatePost,
)
```

Never check authorization inside the handler. If a handler runs, the user is authorized to run it. This rule keeps audits tractable.

## Password Handling

- Hash with **argon2id** (preferred) or **bcrypt** (cost factor ≥ 12). Never SHA-256, never MD5, never custom.
- Salts are per-password and stored with the hash. argon2 and bcrypt handle this for you.
- Never log passwords. Never email passwords. Never store passwords in plaintext, anywhere, for any reason.
- Verify with constant-time comparison (built into the hashing libraries — don't roll your own).

```ts
import argon2 from 'argon2'

export const hashPassword = (plaintext: string) =>
  argon2.hash(plaintext, { type: argon2.argon2id })

export const verifyPassword = (hash: string, plaintext: string) =>
  argon2.verify(hash, plaintext)
```

### Minimum Requirements

- Length: 12+ characters. Don't enforce composition rules (uppercase, symbols) — they make passwords weaker, not stronger.
- Check against a breach list (haveibeenpwned k-anonymity API) at signup and password change.
- Allow any character. Don't strip or restrict.

### Login Rate Limiting

Per-account and per-IP rate limits on login. Lock account after N failed attempts (default 5) for a short window (15 minutes). Notify the user by email when this happens.

## Input Validation and Sanitization

- Validate at the boundary using Zod. Reject malformed input with 400 before any handler logic runs.
- Sanitize at the output, not the input. Store data faithfully; escape when rendering.
- For HTML output, use a library (`DOMPurify`, `sanitize-html`). Never write your own escaper.
- For SQL, parameterize. Never concatenate user input into queries.
- For shell commands, don't. If you must, use `execFile` with an argument array — never `exec` with a constructed string.

## CORS Configuration

- Maintain an explicit allowlist of origins. Read from env.
- Never use `*` in production for endpoints that accept credentials.
- Set `Access-Control-Allow-Credentials: true` only when needed (cookie auth, custom auth headers).
- Limit allowed methods and headers to what the API actually uses.

```ts
import cors from 'cors'

const allowed = env.CORS_ORIGINS.split(',')

app.use(cors({
  origin: (origin, cb) => {
    if (!origin || allowed.includes(origin)) return cb(null, true)
    cb(new Error('Not allowed by CORS'))
  },
  credentials: true,
  methods: ['GET', 'POST', 'PATCH', 'DELETE'],
}))
```

## Rate Limiting

Layered: global → per-IP → per-user → per-endpoint.

- Global: protects the process from runaway traffic. 1000 req/min per IP is a sane default for a small API.
- Per-endpoint: tighter limits on expensive or sensitive routes. Login: 5/min. Password reset: 3/hour. Search: 20/min.
- Per-user: prevents one account from being abused. 100 req/min per user for general endpoints.

Use Redis-backed storage (`rate-limit-redis`) so limits hold across multiple processes. In-memory limits fail under horizontal scaling.

```ts
import rateLimit from 'express-rate-limit'

export const loginLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 5,
  message: { error: { code: 'RATE_LIMIT', message: 'Too many attempts' } },
  standardHeaders: true,
  legacyHeaders: false,
})
```

## Security Headers

Use Helmet with defaults, then tighten.

```ts
import helmet from 'helmet'

app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],  // tighten if possible
      imgSrc: ["'self'", 'data:', 'https:'],
      connectSrc: ["'self'", env.API_URL],
    },
  },
  hsts: { maxAge: 31536000, includeSubDomains: true, preload: true },
}))
```

- HSTS: 1 year, preload. Once set, you cannot easily roll back — test thoroughly.
- CSP: start strict, loosen as needed. Use `report-only` mode in staging first.
- `X-Frame-Options: DENY` unless you intentionally support embedding.
- `Referrer-Policy: strict-origin-when-cross-origin`.

## Secrets Management

- All secrets come from environment variables. Validated at boot.
- Never commit `.env`. `.env.example` with placeholder values is fine.
- Production secrets live in a secret manager (AWS Secrets Manager, GCP Secret Manager, Vault, Doppler). Not in `.env` files on a server.
- Rotate secrets quarterly, immediately after any suspected leak, and whenever a person with access leaves.
- JWT signing keys, database passwords, third-party API keys: all rotated independently.
- Audit logs should record which secret was used (by name, not value) and when.

## OWASP Top 10 Prevention

### A01 Broken Access Control

- Authorization at every protected endpoint, never trust client-supplied role/ID.
- Check resource ownership when the URL contains a resource ID.
- Test: log in as user A, copy a request, replay it with user B's session. Should fail.

### A02 Cryptographic Failures

- HTTPS only. Redirect HTTP. HSTS preload.
- TLS 1.2+ only.
- Strong password hashing (argon2id).
- Don't roll your own crypto. Use audited libraries.

### A03 Injection

- Parameterized queries (Prisma does this; raw SQL must use tagged templates).
- Validate every input with Zod.
- For shell, prefer `execFile` over `exec`.

### A04 Insecure Design

- Threat-model before building auth flows, password reset, payments.
- Add a security review step to PRs touching these areas.

### A05 Security Misconfiguration

- Disable directory listing.
- Don't ship `.env` or `.git` to production.
- Disable verbose error messages in prod (stack traces leak structure).
- Keep dependencies updated. Run `npm audit` in CI.

### A06 Vulnerable Components

- `npm audit` in CI, fail on `high` or `critical`.
- Renovate or Dependabot for updates.
- Pin versions in `package-lock.json`. Don't use `^` for security-critical deps if you can avoid it.

### A07 Authentication Failures

- Rate limit login.
- Lock accounts after repeated failures.
- Require re-auth for sensitive operations (password change, payment, delete account).
- Invalidate sessions on password change.

### A08 Data Integrity Failures

- Verify checksums on downloaded artifacts.
- Sign your release tags.
- CSP with hashes or nonces for inline scripts.

### A09 Logging Failures

- Log auth events: success, failure, lockout, password change.
- Don't log credentials.
- Centralize logs. Alert on suspicious patterns.

### A10 SSRF

- Validate and allowlist URLs the server fetches. Reject `127.0.0.1`, `169.254.169.254`, RFC1918 ranges, and `localhost`.
- Use a separate service account or network policy for outbound calls.

## CSRF

For cookie-authenticated APIs:

- `SameSite=Strict` (or `Lax` if you need top-level navigation logins). Modern browsers prevent most CSRF when this is set.
- Plus a synchronizer token (`csurf` middleware or equivalent) for state-changing endpoints.
- For Bearer-token APIs (Authorization header), CSRF is not applicable — but XSS is, and XSS to steal the token is worse. Use httpOnly cookies if possible.

## Common Mistakes

- **Storing JWTs in localStorage.** XSS-stealable. Use httpOnly cookies.
- **Long-lived access tokens.** 24-hour JWTs can't be revoked. Keep them short, use refresh tokens.
- **Hardcoded secrets in code or `.env` committed to git.** Rotate immediately if this happens.
- **Trusting `req.user.role` from the client.** Roles come from the database during auth, not the request body.
- **Returning stack traces in production.** Leaks file paths, framework versions, and code structure.
- **No rate limit on login.** Credential stuffing in minutes.
- **`Access-Control-Allow-Origin: *` with credentials.** Browsers reject this combo, but ad-hoc proxies don't — and it leaks data.
- **Logging passwords or tokens "just for debugging."** Make this impossible by structure (redact in the logger) so it can never happen accidentally.
- **Authorization checks inside the handler body.** Easy to forget. Use middleware so the check is part of the route definition.
- **Treating ID tokens as authorization.** They prove identity. Your database owns the permissions.
- **Disabled TLS verification on outbound requests.** `rejectUnauthorized: false` is never the answer in prod.
