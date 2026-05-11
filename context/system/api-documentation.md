# API Documentation

How to document HTTP APIs so that clients can integrate without asking. Documentation is part of the API — ship it together.

## OpenAPI / Swagger Specification

Write the OpenAPI spec **first**, before writing handler code. The spec is the contract. Generate docs, types, and mock servers from it.

- Use OpenAPI 3.1 (latest stable). 3.0 is acceptable for tooling that hasn't caught up.
- Store the spec at `docs/openapi.yaml` (or `.json`). Version it in git.
- Generate TypeScript types from the spec with `openapi-typescript`. The same types serve client and server.
- Generate human-readable docs with Redoc, Swagger UI, or Stoplight Elements. Host at `/docs`.

### Spec Structure

```yaml
openapi: 3.1.0
info:
  title: Water Vending API
  version: 1.0.0
  description: |
    Manages water vending machines, orders, and operator dashboards.
  contact:
    name: API team
    email: api@example.com
servers:
  - url: https://api.example.com/v1
    description: Production
  - url: https://staging-api.example.com/v1
    description: Staging
paths:
  /machines:
    get:
      summary: List machines
      ...
components:
  schemas:
    Machine:
      type: object
      ...
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
```

### Schema Reuse

Define every entity once under `components/schemas` and `$ref` it everywhere. Define standard error responses once under `components/responses`.

```yaml
components:
  schemas:
    Error:
      type: object
      required: [code, message]
      properties:
        code: { type: string, example: VALIDATION_ERROR }
        message: { type: string }
        details: { type: object, nullable: true }
        requestId: { type: string }
  responses:
    NotFound:
      description: Resource not found
      content:
        application/json:
          schema:
            type: object
            properties:
              error: { $ref: '#/components/schemas/Error' }
```

## Endpoint Documentation Format

Every endpoint includes:

- **Method and path** — `POST /machines`
- **Summary** — one line, imperative voice. "Create a machine."
- **Description** — what it does, side effects, related endpoints.
- **Authentication** — which security scheme applies.
- **Authorization** — which roles or attributes are required.
- **Request body schema** — `$ref` to a component.
- **Response schemas** — one per status code.
- **Error codes** — every error code this endpoint can return, with cause.
- **Examples** — at least one success, one validation failure.

```yaml
/machines:
  post:
    summary: Create a machine
    description: |
      Registers a new water vending machine in the fleet. Only admins can create machines.
      The machine starts in `offline` status until its first heartbeat.
    operationId: createMachine
    tags: [Machines]
    security:
      - bearerAuth: []
    requestBody:
      required: true
      content:
        application/json:
          schema: { $ref: '#/components/schemas/CreateMachineInput' }
          examples:
            kilimani:
              summary: Kilimani machine
              value:
                name: Kilimani Mall
                location: { lat: -1.2921, lng: 36.7869, address: "Kilimani Rd, Nairobi" }
                pricePerLiter: 25
    responses:
      '201':
        description: Machine created
        headers:
          Location:
            schema: { type: string, format: uri }
            description: URL of the new machine
        content:
          application/json:
            schema: { $ref: '#/components/schemas/Machine' }
      '400':
        $ref: '#/components/responses/ValidationError'
      '401':
        $ref: '#/components/responses/Unauthorized'
      '403':
        $ref: '#/components/responses/Forbidden'
```

## Examples for Every Endpoint

A spec without examples is a spec nobody reads. Include:

- At least one happy-path example.
- One example per distinct error case (validation, not found, conflict).
- For list endpoints, show pagination response with `nextCursor`.

OpenAPI supports `examples` (plural) on request bodies, parameters, and responses. Use named examples — they render as a dropdown in Swagger UI.

```yaml
responses:
  '200':
    description: List of machines
    content:
      application/json:
        examples:
          full:
            summary: Two machines returned
            value:
              data:
                - id: m_01...
                  name: Kilimani Mall
                  status: online
              nextCursor: null
              hasMore: false
          empty:
            summary: No machines in this radius
            value:
              data: []
              nextCursor: null
              hasMore: false
```

## Authentication Documentation

In `info.description` or a dedicated `/docs/authentication` page, explain:

- **How to obtain a token.** Endpoint, request shape, response shape.
- **Where to put the token.** `Authorization: Bearer <token>` header.
- **Token lifetime.** Access token expiry, refresh token expiry, when to refresh.
- **How to refresh.** Endpoint, request shape, behavior on rotation.
- **Revocation.** How a user can sign out everywhere, what happens to in-flight requests.

Example:

```markdown
## Authentication

1. POST `/auth/login` with `{ email, password }`.
2. Response: `{ accessToken, refreshToken, expiresIn }`.
3. Include `Authorization: Bearer <accessToken>` on every request.
4. Access tokens expire after 15 minutes. Refresh with POST `/auth/refresh`.
5. Refresh tokens last 7 days and rotate on each use — store the new one.
6. POST `/auth/logout` revokes the current refresh token.
```

## Versioning Strategy

Use **URL path versioning**: `/v1/users`, `/v2/users`. Simple, cache-friendly, explicit.

Avoid:

- **Header versioning** (`Accept: application/vnd.api+json;version=1`) — hard to test in a browser, easy to forget.
- **Query parameter versioning** (`?version=1`) — affects caching, easy to drop accidentally.

### When to Bump

- **Major version (`v1` → `v2`)** — breaking change to a response shape, removed endpoint, renamed field, changed semantics. Announce 6+ months ahead, run `v1` and `v2` in parallel during deprecation.
- **No bump needed** — adding a new endpoint, adding an optional request field, adding a new field to a response, fixing a bug, performance improvement.

Backwards-compatible changes never require a version bump. Clients should ignore unknown response fields.

### Deprecation Headers

Mark soon-to-be-removed endpoints:

```
Deprecation: true
Sunset: Wed, 31 Dec 2026 23:59:59 GMT
Link: <https://api.example.com/v2/users>; rel="successor-version"
```

Document the deprecation in the spec with `deprecated: true` and a description that points to the replacement.

## Changelog Format

Maintain `docs/api-changelog.md`. One entry per release. Newest first.

```markdown
# API Changelog

## 1.4.0 — 2026-04-15

### Added
- `GET /machines/:id/orders` — list a machine's recent orders. Operator role required.
- `nextCursor` field on all list endpoints.

### Changed
- `GET /machines` now returns `data` array instead of bare array. **Breaking-ish:** parse `body.data`, not `body`.
- Increased default page size from 20 to 50.

### Deprecated
- `POST /auth/token` — use `POST /auth/login`. Will be removed in 2.0.0.

### Fixed
- `PATCH /orders/:id` returned 200 with empty body on no-op updates; now returns the unchanged order.

### Security
- Tightened rate limit on `POST /auth/login` from 10/min to 5/min per IP.
```

Follow [Keep a Changelog](https://keepachangelog.com/) categories: Added, Changed, Deprecated, Removed, Fixed, Security.

## What Counts as a Breaking Change

Breaking (requires version bump):

- Removing or renaming an endpoint.
- Removing or renaming a response field.
- Changing the type of a request or response field.
- Making an optional request field required.
- Adding a new required request field.
- Changing the meaning of a status code.
- Tightening validation (rejecting input that was previously accepted).

Non-breaking (no bump needed):

- Adding a new endpoint.
- Adding an optional request field.
- Adding a new response field.
- Loosening validation.
- Bug fixes that align behavior with documented spec.
- Performance improvements.

When in doubt, treat it as breaking.

## Common Mistakes

- **Writing the docs after the code.** They drift the moment the code changes. Write the spec first, generate from it.
- **No examples.** A spec without examples is unreadable. Include at least one per endpoint.
- **One giant `openapi.yaml`.** Hard to review, hard to merge. Split with `$ref` to per-feature files, bundle for serving.
- **Different error shapes per endpoint.** Define `Error` once, return it everywhere.
- **Skipping error responses in the spec.** Clients need to handle 400, 401, 403, 404, 409, 429 — document every code each endpoint can return.
- **`200 OK` for all responses including errors.** Use real status codes; the spec should reflect them.
- **Hand-maintained markdown docs alongside the spec.** They will diverge. One source of truth — the OpenAPI spec — generate everything else.
- **No changelog.** Clients can't tell what changed. They guess, they break, they file bugs.
- **Header versioning because it's "RESTful."** Path versioning is fine, widely understood, and easy to test. Pick simplicity.
- **Documenting internal endpoints publicly.** Tag them `internal` and exclude from the public spec build, or maintain a separate spec.
- **`description` fields with one word.** "Updates a user." Add context: when to use it, side effects, idempotency, related endpoints.
- **No `operationId`.** Clients generated from the spec need stable method names; without `operationId`, they auto-generate ugly ones.
