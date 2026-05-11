# Authentication

How to build auth flows. Read before adding login, signup, or any protected route.

## Choose One Strategy

Don't mix strategies. Pick one per client surface.

- **Session cookies** — server-rendered apps, SPAs on the same domain as the API. Simplest.
- **JWT in httpOnly cookies** — same as sessions but stateless. Easier horizontal scaling.
- **JWT in Authorization header** — mobile, third-party API clients, cross-domain SPAs. Risk: XSS-stealable if stored in `localStorage`.
- **OAuth2 / OIDC** — delegating identity to a provider (Google, GitHub, Auth0, Clerk).

For most B2C web apps: **JWT in httpOnly cookies** is the sweet spot.

## JWT Flow

### Sign In

```ts
// POST /auth/login
const { email, password } = req.body
const user = await prisma.user.findUnique({ where: { email } })
if (!user || !(await argon2.verify(user.passwordHash, password))) {
  throw new UnauthorizedError('Invalid credentials')
}

const accessToken = sign({ sub: user.id, role: user.role }, env.JWT_SECRET, {
  expiresIn: '15m',
})
const refreshToken = await issueRefreshToken(user.id)

res.cookie('accessToken', accessToken, {
  httpOnly: true,
  secure: true,
  sameSite: 'strict',
  maxAge: 15 * 60 * 1000,
})
res.cookie('refreshToken', refreshToken, {
  httpOnly: true,
  secure: true,
  sameSite: 'strict',
  path: '/auth/refresh',
  maxAge: 7 * 24 * 60 * 60 * 1000,
})
res.json({ user: { id: user.id, email: user.email, role: user.role } })
```

### Verify on Every Request

```ts
export const requireAuth: RequestHandler = (req, _res, next) => {
  const token = req.cookies.accessToken
  if (!token) throw new UnauthorizedError()
  try {
    const payload = verify(token, env.JWT_SECRET) as JwtPayload
    req.user = { id: payload.sub!, role: payload.role }
    next()
  } catch {
    throw new UnauthorizedError('Invalid or expired token')
  }
}
```

### Sign Out

```ts
// POST /auth/logout
await revokeRefreshToken(req.cookies.refreshToken)
res.clearCookie('accessToken')
res.clearCookie('refreshToken', { path: '/auth/refresh' })
res.status(204).end()
```

## Refresh Tokens

Short-lived access tokens are useless without a refresh mechanism. Build it correctly or skip JWTs entirely.

### Storage

Store refresh tokens **in the database**, not as standalone JWTs. They're revocable; access tokens aren't.

```prisma
model RefreshToken {
  id        String   @id @default(uuid()) @db.Uuid
  userId    String   @map("user_id") @db.Uuid
  tokenHash String   @map("token_hash")
  expiresAt DateTime @map("expires_at")
  revokedAt DateTime? @map("revoked_at")
  createdAt DateTime @default(now()) @map("created_at")
  @@map("refresh_tokens")
}
```

Store **a hash** of the token, not the token itself. Compromise of the DB doesn't leak active sessions.

### Rotation

Every refresh issues a new refresh token and revokes the old. This way, a stolen refresh token has a one-use window.

```ts
async function refresh(oldToken: string) {
  const hash = sha256(oldToken)
  const record = await prisma.refreshToken.findFirst({
    where: { tokenHash: hash, revokedAt: null, expiresAt: { gt: new Date() } },
  })
  if (!record) {
    // Token reuse — possible theft. Revoke the entire family.
    await prisma.refreshToken.updateMany({
      where: { userId: record?.userId },
      data: { revokedAt: new Date() },
    })
    throw new UnauthorizedError('Session compromised')
  }

  await prisma.refreshToken.update({
    where: { id: record.id },
    data: { revokedAt: new Date() },
  })

  return issueTokens(record.userId)
}
```

### Lifetimes

- Access token: **15 minutes**.
- Refresh token: **7 days** for ordinary apps, **30 days** for low-risk consumer apps.
- Absolute session limit: **90 days**. Force re-login.

## Session Management

If using server sessions (cookie holds an opaque ID, server holds the data):

- **Store in Redis** for shared state across instances.
- **Regenerate the session ID** on login and on privilege change (password change, role change) to prevent fixation.
- **Idle timeout**: 2 hours of inactivity → expire.
- **Absolute timeout**: 30 days max → expire regardless.
- **Sign out everywhere** = delete all session records for the user.

```ts
// On login
req.session.regenerate(() => {
  req.session.userId = user.id
  req.session.save(() => res.json({ ok: true }))
})
```

## OAuth2 / OIDC

Use a library — never hand-roll OAuth. `passport.js` is the classic; `auth.js` (NextAuth) handles framework integration.

### Authorization Code Flow with PKCE

The only flow you should use for public clients (SPAs, mobile):

1. Client generates a `code_verifier` (random string) and `code_challenge` (SHA-256 of the verifier).
2. Redirect user to provider's `/authorize` with `response_type=code&code_challenge=...&code_challenge_method=S256`.
3. Provider sends user back to your redirect URI with `?code=...`.
4. Server exchanges the code for tokens, sending the `code_verifier` to prove it's the same client.
5. Provider returns ID token, access token, optionally refresh token.

### Treat ID Token as Identity, Not Authorization

The ID token proves who the user is. Don't trust it for role/permission claims. Look the user up in your DB by `sub` and use **your** roles:

```ts
async function handleOAuthCallback(idToken: string) {
  const payload = await verifyIdToken(idToken, providerJwks)
  const user = await prisma.user.upsert({
    where: { provider_sub: { provider: 'google', sub: payload.sub } },
    create: {
      email: payload.email,
      name: payload.name,
      provider: 'google',
      providerSub: payload.sub,
    },
    update: { lastLoginAt: new Date() },
  })
  return issueSession(user)
}
```

### Common Providers

- **Clerk** — turnkey, expensive at scale but ships in an afternoon.
- **Auth0 / Okta** — enterprise standard, expensive.
- **Supabase Auth** — bundled with Supabase, cheap.
- **NextAuth / Auth.js** — self-managed, free, well-supported.
- **Cognito** — AWS-native, painful to work with.

## Role-Based Access Control (RBAC)

Roles live in the database. Tokens carry the role for fast checks; database is authoritative.

```prisma
enum Role {
  CUSTOMER
  OPERATOR
  ADMIN
  SUPER_ADMIN
}

model User {
  id   String @id
  role Role   @default(CUSTOMER)
}
```

### Middleware Guards

```ts
export const requireRole = (...allowed: Role[]): RequestHandler =>
  (req, _res, next) => {
    if (!req.user) throw new UnauthorizedError()
    if (!allowed.includes(req.user.role)) throw new ForbiddenError()
    next()
  }

router.delete('/users/:id', requireAuth, requireRole('ADMIN'), deleteUser)
```

Compose with ownership checks for "edit your own posts but not others'":

```ts
export const requireOwnerOrAdmin = (table: string): RequestHandler =>
  async (req, _res, next) => {
    const row = await prisma[table].findUnique({ where: { id: req.params.id } })
    if (!row) throw new NotFoundError(table)
    if (row.ownerId !== req.user.id && req.user.role !== 'ADMIN') {
      throw new ForbiddenError()
    }
    next()
  }
```

Always authorize at the route level. Never inside the handler — it's easy to forget.

## Protected Routes in React

```tsx
function ProtectedRoute({ children, role }: { children: ReactNode; role?: Role[] }) {
  const { user, loading } = useAuth()
  if (loading) return <Spinner />
  if (!user) return <Navigate to="/login" replace />
  if (role && !role.includes(user.role)) return <Navigate to="/" replace />
  return <>{children}</>
}

<Route path="/admin" element={
  <ProtectedRoute role={['ADMIN', 'SUPER_ADMIN']}>
    <AdminLayout />
  </ProtectedRoute>
} />
```

### Auth Context

```tsx
const AuthContext = createContext<{ user: User | null; loading: boolean }>({ user: null, loading: true })

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    fetch('/api/auth/me', { credentials: 'include' })
      .then((r) => (r.ok ? r.json() : null))
      .then(setUser)
      .finally(() => setLoading(false))
  }, [])

  return <AuthContext.Provider value={{ user, loading }}>{children}</AuthContext.Provider>
}
```

Frontend role checks are UX, not security. The server enforces.

## Password Handling

- Hash with **argon2id** (preferred) or **bcrypt** (cost ≥ 12).
- Minimum length: 12 characters. No composition rules.
- Check against `haveibeenpwned` k-anonymity API at signup and password change.
- Rate-limit login: 5/min per IP, 5/min per email. Lockout 15 minutes after 5 failures.
- On password change, revoke all refresh tokens.

```ts
import argon2 from 'argon2'

const hash = await argon2.hash(password, { type: argon2.argon2id })
const valid = await argon2.verify(hash, password)
```

## Common Mistakes

- **JWTs in `localStorage`.** XSS-stealable. Use httpOnly cookies.
- **No refresh token rotation.** Stolen refresh token works forever.
- **Long-lived access tokens.** 24-hour JWT can't be revoked. Keep them at 15 minutes.
- **Trusting `req.user.role` from the client.** Roles come from the database during auth.
- **Authorization checks inside handlers.** Easy to miss. Use middleware.
- **Same JWT signed in dev and prod.** A dev token works against prod. Different secrets per environment.
- **Storing refresh tokens as raw JWTs.** Use opaque tokens + DB record. Revocable.
- **No CSRF protection on cookie-auth endpoints.** `SameSite=Strict` covers most; add a token for state-changing endpoints if you support older browsers.
- **OAuth Implicit flow.** Deprecated. Use Authorization Code + PKCE.
- **Treating OAuth ID token as authorization.** It proves identity. Your DB owns permissions.
- **No rate limit on login.** Credential stuffing in minutes.
- **Forgetting to revoke sessions on password change.** Old sessions still work after the password is rotated.
- **Logging passwords or tokens.** Make it structurally impossible — redact in the logger.
- **Front-end role checks treated as security.** Always re-check on the server.
- **Custom crypto for password hashing.** Use argon2id. Don't invent.
