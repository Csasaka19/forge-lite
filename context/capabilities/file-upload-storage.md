# File Upload & Storage

How to accept files from users and serve them back. Read before adding any file input.

## Storage Choice

- **AWS S3** — default for AWS-resident apps. Mature, cheap, well-tooled.
- **Cloudflare R2** — S3-compatible API, **no egress fees**. Best for public-facing media.
- **Supabase Storage** — bundled with Supabase, S3-compatible, easy auth integration.
- **UploadThing** — turnkey for React apps, opinionated.
- **Vercel Blob** — hosted on Vercel, simple, premium price.

Pick R2 first for new projects with public media. Pick S3 if already in AWS. Skip "store in the database" — files belong in object storage.

## Architecture: Presigned URLs

**Never proxy uploads through your app server.** Generate a presigned URL on the server, upload directly from the client to storage.

```ts
// server
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3'
import { getSignedUrl } from '@aws-sdk/s3-request-presigner'

const s3 = new S3Client({
  region: 'auto',
  endpoint: env.R2_ENDPOINT,   // for R2; omit for S3
  credentials: { accessKeyId: env.R2_KEY, secretAccessKey: env.R2_SECRET },
})

app.post('/uploads/presign', requireAuth, async (req, res) => {
  const { filename, contentType, size } = req.body
  validateUpload({ filename, contentType, size })

  const key = `users/${req.user.id}/${crypto.randomUUID()}-${sanitize(filename)}`
  const url = await getSignedUrl(
    s3,
    new PutObjectCommand({
      Bucket: env.BUCKET,
      Key: key,
      ContentType: contentType,
      ContentLength: size,
    }),
    { expiresIn: 300 },     // 5 min window
  )
  res.json({ url, key })
})
```

Client uploads via PUT:

```ts
const { url, key } = await api('/uploads/presign', {
  method: 'POST',
  body: JSON.stringify({ filename: file.name, contentType: file.type, size: file.size }),
})

await fetch(url, {
  method: 'PUT',
  headers: { 'Content-Type': file.type },
  body: file,
})

// Record the upload in your DB after success
await api(`/uploads/finalize`, { method: 'POST', body: JSON.stringify({ key }) })
```

### Rules

- **Always finalize.** The presign tells your DB nothing; the finalize call records the upload.
- **Validate everything on the server** before signing — size, type, the user's quota.
- **Short expiry on presigned URLs** — 5 minutes is plenty.
- **Scope keys by user** — `users/<id>/...` so one user can't accidentally read another's path.

## Client-Side Upload UI

### React Dropzone

```bash
npm install react-dropzone
```

```tsx
import { useDropzone } from 'react-dropzone'

function FileDrop({ onFiles }: { onFiles: (f: File[]) => void }) {
  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    accept: { 'image/*': ['.jpg', '.jpeg', '.png', '.webp'] },
    maxSize: 10 * 1024 * 1024,
    maxFiles: 5,
    onDrop: onFiles,
  })

  return (
    <div
      {...getRootProps()}
      className={`border-2 border-dashed rounded-lg p-8 text-center ${
        isDragActive ? 'border-primary bg-primary/5' : 'border-border'
      }`}
    >
      <input {...getInputProps()} />
      <p>{isDragActive ? 'Drop files here' : 'Drag files or click to select'}</p>
    </div>
  )
}
```

### Single vs Multi

- **Single**: profile avatar, document upload. `maxFiles: 1`.
- **Multi**: gallery, batch import. `maxFiles: 10`.
- Always show **per-file progress and remove buttons**.

## Progress Tracking

Fetch can't track upload progress. Use XHR for that one job:

```ts
export function uploadWithProgress(
  url: string,
  file: File,
  onProgress: (pct: number) => void,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest()
    xhr.upload.addEventListener('progress', (e) => {
      if (e.lengthComputable) onProgress((e.loaded / e.total) * 100)
    })
    xhr.addEventListener('load', () => {
      xhr.status >= 200 && xhr.status < 300 ? resolve() : reject(new Error('Upload failed'))
    })
    xhr.addEventListener('error', () => reject(new Error('Network error')))
    xhr.open('PUT', url)
    xhr.setRequestHeader('Content-Type', file.type)
    xhr.send(file)
  })
}
```

## File Type Validation

Client validation is a UX hint, **never** a security boundary. Validate on the server.

### Server-Side Magic Number Check

```ts
import { fileTypeFromBuffer } from 'file-type'

async function validateImage(buffer: Buffer) {
  const detected = await fileTypeFromBuffer(buffer)
  const allowed = ['image/jpeg', 'image/png', 'image/webp', 'image/avif']
  if (!detected || !allowed.includes(detected.mime)) {
    throw new ValidationError('Unsupported file type')
  }
}
```

The first bytes of every real image identify its format. Trust those, not the extension or the client-sent `Content-Type`.

### Direct-Upload Validation

When the client uploads straight to S3/R2, your server can't sniff bytes pre-write. Options:

- **Constrain via the presign**: `Conditions: [['content-length-range', 0, 10485760]]` enforces max size at the storage layer.
- **Validate post-upload**: in the `/finalize` endpoint, fetch the object's first KB, sniff, and either accept or delete.
- **Use S3 Object Lambda or R2's image API** to reject bad types at read time.

## Image Transformation

Don't serve user-uploaded originals. Resize, re-encode, strip metadata.

### Server-Side with Sharp

```bash
npm install sharp
```

```ts
import sharp from 'sharp'

async function processAvatar(input: Buffer): Promise<Buffer> {
  return sharp(input)
    .rotate()                                  // honor EXIF orientation
    .resize({ width: 512, height: 512, fit: 'cover' })
    .toFormat('webp', { quality: 85 })
    .toBuffer()
}
```

Run in a background job for large images so the upload endpoint stays fast.

### Cloudinary / Imgix / ImageKit

For dynamic transformations (resize/crop/watermark by URL), use a hosted service. URL becomes:

```
https://res.cloudinary.com/account/image/upload/w_400,h_400,c_fill,q_auto,f_auto/orders/abc.jpg
```

Generates the variant on demand, caches at the CDN. No server work after the initial upload.

### Cloudflare Images / R2 + Workers

Cloudflare's image service has a similar URL-based transformation API at lower cost. For R2 buckets, write a Worker that proxies, transforms, and caches.

## CDN Serving

Object storage alone is slow for global users. Front it with a CDN.

- **R2** — CDN built in via Cloudflare. URL is already cached.
- **S3** — front with CloudFront. Without it, S3 directly is expensive and slow cross-region.
- **Supabase Storage** — Supabase CDN included.

### Cache Headers

Set when uploading:

```ts
new PutObjectCommand({
  Bucket: env.BUCKET,
  Key: key,
  CacheControl: 'public, max-age=31536000, immutable',
  ContentType: contentType,
})
```

Object keys should include a content hash (or a unique ID) so new uploads have new URLs — never replace a file at the same key in production.

## Resumable / Large Uploads

For files > 100 MB or unreliable mobile networks:

- **S3 Multipart Upload** — split into chunks, presign each, finalize. AWS SDK supports it.
- **Tus protocol** — open standard, libraries for browser and Node. Works against any compatible server.
- **Uppy** + Companion — drop-in UI with Tus support.

```ts
import Uppy from '@uppy/core'
import AwsS3 from '@uppy/aws-s3'

const uppy = new Uppy()
  .use(AwsS3, { shouldUseMultipart: (file) => file.size > 100 * 1024 * 1024 })
```

## Deleting

When a record is deleted, delete the object too — orphans accumulate.

```ts
import { DeleteObjectCommand } from '@aws-sdk/client-s3'

await s3.send(new DeleteObjectCommand({ Bucket: env.BUCKET, Key: key }))
```

For soft deletes, mark the DB row deleted but defer object deletion to a nightly job — gives a recovery window.

## Common Mistakes

- **Proxying uploads through the app server.** Slow, expensive, doesn't scale. Use presigned URLs.
- **Trusting client-sent `Content-Type`.** Sniff magic bytes on the server.
- **Serving user uploads from the app's domain.** Stored XSS turns into account takeover. Use a separate origin.
- **No size limit at the storage layer.** Client lies and uploads 10 GB. Enforce via presign conditions.
- **Same key for replacements.** CDN serves stale forever. Use a fresh key per upload.
- **No `CacheControl` on upload.** Browser revalidates every time, undoing the CDN benefit.
- **Storing originals as the "primary."** Users uploaded 30 MB camera JPEG. Always transform.
- **Image re-encoding in the request handler.** Slow uploads. Move to a background job.
- **No EXIF rotation.** Phone photos render sideways. Always `sharp().rotate()`.
- **Forgetting to delete objects when DB rows are deleted.** Storage bill grows forever.
- **Public-write bucket "for convenience."** Don't. Keys are presigned per upload.
- **Long-lived presigned URLs.** Five-minute expiry; longer is needless risk.
- **Hand-rolling multipart upload.** Use the SDK or Uppy. Hand-rolled chunk math has bugs.
- **No virus scan on user-shared files.** Attachments shared with other users are a malware vector.
