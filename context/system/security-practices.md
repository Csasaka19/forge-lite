# Security Practices

Application security baseline. Read before adding a dependency, accepting a file upload, or storing user data.

## Dependency Security

Most production breaches come from known vulnerabilities in third-party code, not from novel exploits in your own. Treat dependencies as your code — you ship them, you own them.

### Audit

Run `npm audit` (or `pnpm audit`) in CI. Fail the build on high/critical findings.

```yaml
- run: npm audit --audit-level=high --omit=dev
```

- `--omit=dev` filters out dev dependencies, which usually don't ship. But review them anyway — a compromised dev tool can inject malicious code at build time.
- "High" is the gate. Tune down to "moderate" for security-sensitive projects.
- Don't pile up unresolved findings. Either patch, replace, or document why the vuln doesn't apply (and re-review quarterly).

### Automated Updates

Use **Dependabot** or **Renovate** to open PRs for updates. Configure:

- Group minor and patch updates into a single weekly PR per ecosystem. Major updates get their own PR.
- Auto-merge patch updates after CI passes (lockfile-only, no breaking changes).
- Major updates always get human review.

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: npm
    directory: /
    schedule: { interval: weekly }
    groups:
      minor-and-patch:
        update-types: [minor, patch]
    open-pull-requests-limit: 10
```

Renovate is more flexible (better grouping, automerge rules). Pick one and let it run.

### Review Before Merging

Even with automation, don't blind-merge dependency PRs:

- Read the changelog/release notes. A "minor" version can ship behavior changes.
- Check the diff in `package-lock.json` for unexpected transitive dependencies — a small update can pull in dozens of new packages.
- Run the full test suite. Updates can break in ways the maintainer didn't anticipate.

For high-trust packages (your own forks, well-known libraries), patch-only auto-merge is fine. For long-tail packages, require review.

## Supply Chain Security

The packages you depend on depend on others. The attack surface is the whole tree.

### Lock Files

- **Always commit `package-lock.json`** (or `pnpm-lock.yaml`, `yarn.lock`). It pins the exact tree.
- CI installs with `npm ci`, not `npm install`. `npm ci` fails if the lock file and `package.json` disagree, and never modifies the lock.
- Never delete and regenerate the lock file casually. It's a security-relevant change — review the diff.

### Verify Package Integrity

Lock files include integrity hashes (`sha512-...`). `npm ci` verifies them. If a registry tampered with a package, the install fails.

For production deploys, consider:

- A private registry mirror (Verdaccio, Artifactory) that caches verified versions.
- Signed builds with provenance attestations (`npm publish --provenance` for libraries you author).

### Minimize Dependencies

Every dependency is:

- More code shipped (bundle size).
- More attack surface.
- More potential breaking changes.
- More transitive dependencies you didn't choose.

Before adding a dependency, ask:

- Is the function trivial enough to write inline? (`is-odd` is famously not a dependency.)
- Is the package maintained? Check last commit, open issues, weekly downloads.
- Is the maintainer trustworthy? Avoid single-maintainer packages for security-critical code.
- Does it pull in 50+ transitive deps for a 10-line function?

Prefer the standard library, the runtime's built-ins (`crypto`, `Intl`, `URL`), and small focused packages over kitchen-sink frameworks.

### Watch For

- **Typosquatting** — `lodahs`, `expres`, `chalkk`. Always copy-paste package names from the official source.
- **Dependency confusion** — internal package names accidentally pulled from the public registry. Use scoped names (`@yourorg/utils`) and registry config to scope private packages.
- **Postinstall scripts** — packages can run arbitrary code on install. Audit `postinstall` in suspicious packages, or disable globally with `npm config set ignore-scripts true` and re-enable per-package.

## Data Protection

### Encryption in Transit

- **HTTPS only.** Redirect HTTP. HSTS preload once you're confident.
- **TLS 1.2 minimum**, 1.3 preferred.
- **Database connections over TLS** — `?sslmode=require` (or stricter) on connection strings.
- **Internal service-to-service traffic** also TLS. Within a VPC is not "safe by default" — assume the network is hostile.

### Encryption at Rest

- **Database**: enable storage encryption. RDS, Aurora, Cloud SQL, Supabase do this by default. Verify it's on.
- **Object storage** (S3, GCS): default to bucket-level encryption (`SSE-S3` minimum, `SSE-KMS` for sensitive data).
- **Backups**: encrypted with the same standard as the primary.
- **Disk volumes** (EBS, persistent disks): encrypted at creation. Cheap and easy.

### Application-Level Encryption

For especially sensitive fields (SSNs, payment tokens, secrets stored in your DB), encrypt at the application level so the DB never sees plaintext:

```ts
import { createCipheriv, createDecipheriv, randomBytes } from 'crypto'

const key = Buffer.from(env.FIELD_ENCRYPTION_KEY, 'base64')

export function encryptField(plaintext: string): string {
  const iv = randomBytes(12)
  const cipher = createCipheriv('aes-256-gcm', key, iv)
  const ct = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()])
  const tag = cipher.getAuthTag()
  return Buffer.concat([iv, tag, ct]).toString('base64')
}
```

Always use authenticated encryption (AES-GCM or ChaCha20-Poly1305). Never CBC without HMAC. Never ECB. Don't write your own crypto primitives.

### Minimize Data Collection

The data you don't collect can't leak.

- Default to collecting nothing beyond what the feature needs.
- For each field on a signup form, ask: what would we use this for? If there's no answer, drop it.
- For analytics, prefer aggregated/anonymized data over individual events.
- Set retention policies. Old data gets deleted on schedule, not "kept just in case."

## Privacy: GDPR / CCPA Basics

If you serve users in the EU, UK, California, or similar jurisdictions, these are not optional.

### Consent

- **Cookie consent** for non-essential cookies (analytics, marketing). Essential cookies (auth, CSRF) don't need consent but should be documented.
- **Opt-in** for marketing email at signup. Pre-checked boxes are not consent.
- **Granular consent** — separate toggles for analytics, marketing, profiling. Not one "agree to everything" button.
- Log what the user consented to and when. Withdrawal must be as easy as giving consent.

### Data Subject Rights

Build endpoints (admin or self-service) for:

- **Access** — export everything you have about a user as JSON.
- **Deletion** — delete or anonymize the user's data. Be honest about what survives (legal-retention records, anonymized analytics).
- **Portability** — machine-readable export. JSON is fine.
- **Correction** — let users edit their data.

Document the SLA for each — usually 30 days.

### Privacy by Design

- Pseudonymize where possible — use opaque user IDs in logs, not emails.
- Separate identifiable data from behavioral data. Joining requires explicit code path.
- Audit who accesses PII. Log access to sensitive tables.
- Data Processing Agreement (DPA) with every vendor that touches user data.

## Security Headers

Set on every response. Use Helmet for sane defaults, then tighten.

```ts
import helmet from 'helmet'

app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      imgSrc: ["'self'", 'data:', 'https:'],
      connectSrc: ["'self'", env.API_URL],
      frameAncestors: ["'none'"],
    },
  },
  hsts: { maxAge: 31536000, includeSubDomains: true, preload: true },
}))
```

### Required Headers

- **`Strict-Transport-Security`** — `max-age=31536000; includeSubDomains; preload`. Browsers will refuse HTTP entirely.
- **`Content-Security-Policy`** — restricts what the page can load. Start strict, loosen as needed. Use `report-only` mode in staging first.
- **`X-Frame-Options: DENY`** — prevents clickjacking via iframe embedding. (CSP `frame-ancestors` supersedes it on modern browsers but keep both for old ones.)
- **`X-Content-Type-Options: nosniff`** — prevents MIME-type confusion.
- **`Referrer-Policy: strict-origin-when-cross-origin`** — limits referer leakage.
- **`Permissions-Policy`** — explicitly disable APIs you don't use (geolocation, camera, mic).

### Verify

Test with `securityheaders.com` or `Mozilla Observatory`. Target A+ in production.

## File Upload Security

User uploads are a classic attack vector. Treat every file as malicious.

### Validate

- **MIME type by content sniffing**, not by `Content-Type` header (client-controlled) or extension (client-controlled). Use `file-type` library.
- **Extension allowlist** — only the formats your feature needs. Block executables, scripts, archives by default.
- **Magic-number check** matches MIME — JPG starts with `FF D8 FF`, PNG with `89 50 4E 47`. Reject mismatches.

```ts
import { fileTypeFromBuffer } from 'file-type'

const detected = await fileTypeFromBuffer(buffer)
if (!detected || !['image/jpeg', 'image/png', 'image/webp'].includes(detected.mime)) {
  throw new ValidationError('Unsupported file type')
}
```

### Size Limits

Enforce at multiple layers:

- Reverse proxy / load balancer (Nginx `client_max_body_size`).
- Web framework (Express `express.json({ limit: '1mb' })`, multer `limits`).
- Per-endpoint (don't accept 10 MB on an avatar uploader).

Reject early — don't stream gigabytes into memory just to reject them.

### Scan for Malware

For user-shared files (attachments, public uploads), scan with ClamAV, VirusTotal, or a managed service. Quarantine on detection. Notify the uploader and never re-serve the file.

### Don't Serve from App Domain

Serve user uploads from a **separate origin** (`uploads.example.com` or an object storage URL). Reasons:

- **XSS isolation** — an HTML file uploaded as a profile picture can run scripts on the main domain if served from it.
- **Cookie isolation** — auth cookies don't leak to the upload domain.
- **CDN-friendly** — uploads cache independently.

Set `Content-Disposition: attachment` for downloads. Set `Content-Type` strictly. Disable inline rendering of unknown types.

### Image Re-encoding

For user-uploaded images, re-encode through `sharp` or similar. This strips embedded payloads and normalizes the file:

```ts
import sharp from 'sharp'

await sharp(input)
  .resize({ width: 2000, withoutEnlargement: true })
  .toFormat('webp', { quality: 80 })
  .toFile(outputPath)
```

Never serve raw user-uploaded bytes if you can avoid it.

## Environment Separation

Three environments. Different credentials for each. No exceptions.

- **Development** — local laptop. Fake data. No production access.
- **Staging** — production-shaped. Real services, separate accounts (separate Stripe test mode keys, separate auth tenant, separate database).
- **Production** — real users, real data. Highest access controls.

### Credentials

- One set of API keys per environment. Production keys never appear in staging or dev configs.
- Database is separate per environment. Never a single DB with `dev_`, `stg_`, `prd_` table prefixes.
- Object storage is separate per environment.
- Webhook endpoints register per environment.

### Access

- Production write access: smallest viable group. Use break-glass procedures, not standing access.
- Read-only access to production for debugging is fine for engineers, with audit logging.
- Rotate access when people change roles or leave.

### Drift

Production should be reachable only through deploy pipelines. Manual changes drift configuration and break IaC.

If you need to debug live, do it through observability, not by SSHing into the box. If you must SSH, log the session and write up what you did afterward.

## Common Mistakes

- **`npm install` in CI.** Mutates the lock file. Use `npm ci`.
- **Ignoring `npm audit` output.** Vulnerabilities accumulate; one day one matters. Triage every finding.
- **Auto-merging major version bumps.** Major versions have breaking changes by definition. Always review.
- **Single set of API keys reused across environments.** Staging tests trigger production charges or production emails.
- **HTTP allowed alongside HTTPS.** Redirect 100% of HTTP traffic. Then preload HSTS.
- **Trusting `Content-Type` on uploads.** Client-controlled. Sniff the bytes.
- **Serving user uploads from the main domain.** Stored XSS becomes account takeover.
- **No CSP, or CSP with `unsafe-inline` and `unsafe-eval` "for now."** Defeats the purpose. Use nonces or hashes.
- **PII in URLs.** Logged everywhere — proxies, browser history, referers. Use POST bodies or paths with opaque IDs.
- **Logging PII or secrets "for debugging."** Logs persist longer than you think. Redact at the logger level.
- **Manual production access without audit logs.** When something goes wrong, you can't tell who touched what.
- **Treating staging as a dumping ground.** Real users get used to seeing it; treat security and data hygiene as you would in prod.
- **No data retention policy.** Old data piles up; one breach exposes a decade of records. Delete on schedule.
- **DPAs and consent strings done after launch.** Build privacy in. Retrofits are expensive and incomplete.
- **Disabling certificate verification on outbound HTTP.** `rejectUnauthorized: false` is never the right answer in prod.
