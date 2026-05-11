# Docker Containerization

Container standards for Node.js services and supporting infrastructure. Read before adding a Dockerfile or `docker-compose.yml`.

## Dockerfile Best Practices

### Multi-Stage Builds

Always use multi-stage builds for compiled or bundled code. Build stage has dev dependencies and toolchain; runtime stage has only what runs.

```dockerfile
# syntax=docker/dockerfile:1.7
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY package.json ./

RUN addgroup -S app && adduser -S app -G app
USER app

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "dist/server.js"]
```

The final image contains compiled output and production deps only — no source, no build tools, no dev deps.

### Minimize Layers

Combine related `RUN` commands when they share a logical step. Don't chain unrelated commands just to save a layer — readability wins past the cache boundary.

```dockerfile
# Good — single apt step
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Bad — three layers, leaves apt lists in image
RUN apt-get update
RUN apt-get install -y curl ca-certificates
```

### Layer Order: Copy Manifests Before Source

`package.json` and `package-lock.json` change less often than source. Copy them first so `npm ci` is cached across source changes.

```dockerfile
COPY package.json package-lock.json ./
RUN npm ci
COPY . .            # source comes last
```

### Non-Root User

Always run as a non-root user in the runtime stage. Containers running as root that get compromised get the whole host.

```dockerfile
RUN addgroup -S app && adduser -S app -G app
USER app
```

The `node` official image already includes a `node` user — use it if you're using that image directly:

```dockerfile
USER node
```

### Don't Run init/Systemd

Containers run one process. If you genuinely need PID 1 to reap zombies (rare, for long-running parent-of-many-children processes), use `tini`:

```dockerfile
RUN apk add --no-cache tini
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "dist/server.js"]
```

## Base Image Selection

Pin to a specific version. Never use `latest` — silent breakage when the tag moves.

```dockerfile
FROM node:20.11.1-alpine3.19    # exact version
```

### When to Use Which

- **alpine** (`node:20-alpine`) — smallest image (~50 MB compressed). Good default. Uses musl libc — most npm packages with native modules work; some don't.
- **slim** (`node:20-slim`) — Debian-based, ~150 MB. Better compatibility with native modules (`bcrypt`, `sharp`, `canvas`, anything pulling glibc).
- **distroless** (`gcr.io/distroless/nodejs20`) — no shell, no package manager, smallest attack surface. Use for production runtime stage after building elsewhere. Hard to debug — keep the build stage on alpine/slim.
- **bookworm/bullseye** (full Debian) — only when you need a specific apt package not in slim. Heavier; usually unnecessary.

Start with alpine. Switch to slim only if a native module fails to install.

### Version Pinning

- Pin major and minor: `node:20.11-alpine` is the floor.
- Pin to exact patch for production: `node:20.11.1-alpine3.19`. Renovate updates this.
- Never `node:latest`, `node:20`, or `node:alpine` for production — they move under you.

## docker-compose for Local Development

`docker-compose.yml` orchestrates services for local dev: the app, its database, Redis, anything else it needs. Production runs on different infrastructure — compose is a dev tool.

```yaml
services:
  app:
    build:
      context: .
      target: build    # use the build stage for hot reload
    command: npm run dev
    ports:
      - '3000:3000'
    volumes:
      - .:/app
      - /app/node_modules    # don't mount over installed deps
    environment:
      DATABASE_URL: postgres://app:app@db:5432/app
      NODE_ENV: development
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started

  db:
    image: postgres:16.2-alpine
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: app
      POSTGRES_DB: app
    volumes:
      - db-data:/var/lib/postgresql/data
    ports:
      - '5432:5432'
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U app']
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7.2-alpine
    ports:
      - '6379:6379'
    volumes:
      - redis-data:/data

volumes:
  db-data:
  redis-data:
```

### Volumes

- **Named volumes** (`db-data:`) for database state — persists across `docker compose down`.
- **Bind mounts** (`.:/app`) for source — live reload.
- **Anonymous volumes for `node_modules`** to keep the in-container install from being shadowed by the host mount.

### `.env` Files

Compose reads `.env` automatically. Use it for local-only values. Don't commit; commit `.env.example` instead.

```yaml
environment:
  DATABASE_URL: ${DATABASE_URL}
  JWT_SECRET: ${JWT_SECRET}
```

### Profiles

Use profiles for optional services (monitoring, mailpit, MinIO) so `docker compose up` stays fast.

```yaml
services:
  mailpit:
    image: axllent/mailpit
    profiles: [mail]
```

Start with `docker compose --profile mail up`.

## Container Security

### Scan Images

Run vulnerability scans in CI:

```yaml
- uses: aquasecurity/trivy-action@master
  with:
    image-ref: myapp:${{ github.sha }}
    severity: HIGH,CRITICAL
    exit-code: 1
```

Fail the build on high/critical CVEs. Use a base-image update or alternate base if the CVE is in a system package.

### Don't Run as Root

Already covered above — `USER` directive in the runtime stage. CI should reject Dockerfiles missing it.

### Read-Only Filesystem

For services that don't write to disk, run with a read-only root filesystem:

```yaml
# in production orchestrator config (Kubernetes, ECS)
readOnlyRootFilesystem: true
```

If the app needs scratch space, mount an `emptyDir` or tmpfs at the specific path it writes to.

### Drop Capabilities

In production, drop all Linux capabilities and add back only what's needed (usually nothing):

```yaml
capabilities:
  drop: [ALL]
```

### Don't Expose Docker Socket

Never mount `/var/run/docker.sock` into a container in production. It's full root on the host. If you need orchestration access, use the platform API.

### Secrets in Containers

- Never `COPY .env` into an image.
- Never `ENV SECRET=...` for real secrets — they're baked into image layers, visible to anyone with the image.
- Pass at runtime: `docker run -e SECRET=...`, Kubernetes secrets, ECS task definition env, etc.

## .dockerignore

Mirror `.gitignore` and add Docker-specific exclusions. Without this, build context balloons and slows every build.

```
.git
.github
node_modules
dist
build
coverage
.env
.env.*
!.env.example
*.log
.DS_Store
.vscode
.idea
Dockerfile*
docker-compose*.yml
README.md
```

Excluding `node_modules` is critical — including it pulls host-built native modules into a Linux container build, breaking things subtly.

## Health Checks

Define a `HEALTHCHECK` in the Dockerfile or in the orchestrator config. Orchestrators (Kubernetes, ECS, Docker Swarm) use it to decide if a container is ready and alive.

### Liveness vs Readiness

- **Liveness** — is the process responsive? If not, restart.
- **Readiness** — is the process ready to accept traffic? If not, don't route.

Two endpoints, often `/health` (liveness) and `/ready` (readiness):

```ts
app.get('/health', (_req, res) => res.status(200).json({ status: 'ok' }))

app.get('/ready', async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`
    res.status(200).json({ status: 'ready' })
  } catch {
    res.status(503).json({ status: 'not-ready' })
  }
})
```

Liveness should not depend on external services — if the database is down, the app is unhealthy in a different sense (degraded but alive). Otherwise a flaky downstream causes restart loops.

## Logging from Containers

- Log to **stdout and stderr only**. The container runtime captures these and ships to wherever logs go.
- Never log to a file inside the container — it fills the writable layer and disappears on restart.
- Use **structured JSON** logs (Pino). Aggregators parse JSON natively.
- One JSON object per line — no pretty-printing in production.

```ts
import pino from 'pino'

export const logger = pino({
  level: env.LOG_LEVEL,
  formatters: {
    level: (label) => ({ level: label }),
  },
  timestamp: pino.stdTimeFunctions.isoTime,
})
```

For dev, pipe through `pino-pretty`:

```json
"scripts": {
  "dev": "node dist/server.js | pino-pretty"
}
```

## Registry Management

### Tag Strategy

Every image gets multiple tags:

- **`<sha>`** — the commit SHA. Immutable, unambiguous. Use this for deploys.
- **`<semver>`** (release tags) — `1.4.0`. For release artifacts.
- **`<branch>`** — `develop`, `main`. Convenient for "latest from this branch."
- **`latest`** — for the most recent main-branch build only. Never use `latest` in production deploys.

```bash
docker build -t myapp:${SHA} -t myapp:main -t myapp:latest .
docker push myapp:${SHA}
docker push myapp:main
docker push myapp:latest
```

### Cleanup

Registries grow forever without retention policies:

- Keep all release-tagged images (`1.x.x`) indefinitely.
- Keep the last 30 days of `<sha>` and `<branch>` tags.
- Garbage collect monthly. Most registries support automated retention rules (ECR Lifecycle Policies, GitHub Container Registry retention).

## Common Mistakes

- **`FROM node:latest`.** Reproducibility goes out the window. Pin versions.
- **Building on host, copying `node_modules` into image.** Host node_modules have host-specific binaries. Always `npm ci` in the build stage.
- **Single-stage build with dev deps in the final image.** Tripled image size, larger attack surface.
- **Running as root.** Compromise the process, you compromise the host (with most runtimes). Always set `USER`.
- **Bundling secrets via `ENV` or `COPY .env`.** They're in the image forever. Pass at runtime.
- **No `.dockerignore`.** Slow builds, accidental `.git` history in image, accidental `.env` in image.
- **No health check.** Orchestrator can't tell a hung process from a healthy one.
- **Logging to a file.** Fills the container's writable layer. Use stdout.
- **`apt-get install` without `--no-install-recommends` and `rm -rf /var/lib/apt/lists/*`.** Bloats the image.
- **Two unrelated processes in one container.** One container, one concern. Use separate services in compose.
- **Mounting `node_modules` from host into container.** Host-built modules break in the container. Use anonymous volume to mask the host's.
- **`docker-compose.yml` for production.** Compose is a dev tool. Production needs an orchestrator (Kubernetes, ECS, Fly, Railway, Render).
- **Re-pulling base images on every CI build with no cache.** Use registry-backed layer cache (`type=registry,ref=...`) to keep builds under a minute.
