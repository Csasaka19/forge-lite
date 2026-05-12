# Image & Media Processing

How to resize, optimize, and serve images. Read before adding any image-heavy feature.

## Decision Tree

| Need | Pick |
|---|---|
| Server-side resize / convert / optimize | **Sharp** |
| URL-based on-demand transformation | **Cloudinary**, **ImageKit**, **Cloudflare Images**, **imgix** |
| Responsive images, modern formats | `<img srcset>` + Sharp pipeline or hosted service |
| Blur placeholder while loading | **BlurHash** or LQIP (low-quality image placeholder) |
| Lazy-load below the fold | `loading="lazy"` + Intersection Observer |
| Video | Don't self-host. Use **Mux**, **Cloudflare Stream**, **Vimeo**. |

Never serve user-uploaded originals. Always transform.

## Sharp: The Workhorse

```bash
npm install sharp
```

Sharp uses libvips — fast, low memory, parallel.

### Resize and Convert

```ts
import sharp from 'sharp'

await sharp(input)
  .rotate()                                    // honor EXIF
  .resize({ width: 1600, height: 1600, fit: 'inside', withoutEnlargement: true })
  .toFormat('webp', { quality: 80 })
  .toFile(output)
```

### Fit Modes

- **`cover`** — fill the box, crop overflow. Default for thumbnails.
- **`contain`** — fit inside the box, letterbox if needed.
- **`inside`** — shrink to fit, don't enlarge.
- **`outside`** — fill the box, may overflow.
- **`fill`** — stretch to fit. Never use for photos.

### Crop with Smart Focus

```ts
await sharp(input)
  .resize({
    width: 800,
    height: 400,
    fit: 'cover',
    position: sharp.strategy.attention,    // crop toward salient region
  })
  .toFile(output)
```

`sharp.strategy.attention` keeps faces and detail in frame. `sharp.strategy.entropy` keeps detail without face bias.

### Format Selection

| Format | Use |
|---|---|
| **AVIF** | Best compression, modern browsers |
| **WebP** | Wide support, smaller than JPEG |
| **JPEG** | Photos for ancient browsers |
| **PNG** | Logos, screenshots, anything with transparency that AVIF/WebP can't handle |
| **SVG** | Vector — icons, logos. Don't rasterize SVG sources. |

Default pipeline: **AVIF + WebP + JPEG fallback** via `<picture>`.

### Strip Metadata

EXIF can include GPS coordinates of where a photo was taken. Always strip on user uploads:

```ts
await sharp(input)
  .rotate()                  // rotate first (uses EXIF), then strip
  .withMetadata({ exif: {} })   // or omit entirely with .toBuffer() (default strips)
  .toFile(output)
```

## Thumbnail Pipeline

Generate multiple sizes on upload, all stored:

```ts
const sizes = [
  { suffix: 'sm', width: 320 },
  { suffix: 'md', width: 800 },
  { suffix: 'lg', width: 1600 },
]

async function buildVariants(input: Buffer, baseKey: string) {
  const pipeline = sharp(input).rotate()
  const meta = await pipeline.metadata()

  await Promise.all(
    sizes.map(async ({ suffix, width }) => {
      if (meta.width && width > meta.width) return
      const buffer = await pipeline
        .clone()
        .resize({ width, withoutEnlargement: true })
        .toFormat('webp', { quality: 80 })
        .toBuffer()
      await uploadToStorage(`${baseKey}-${suffix}.webp`, buffer)
    }),
  )
}
```

### Rules

- **Run in a background job** — not in the upload endpoint.
- **Clone the pipeline** before branching (`pipeline.clone()`) — Sharp pipelines are single-use.
- **Don't enlarge** — `withoutEnlargement: true`. Enlarging tiny images produces blurry results.
- **Set quality per format** — WebP 80, AVIF 60–70, JPEG 75–85 are good defaults.

## On-Demand vs Pre-Generated

- **Pre-generate** at upload time — cheaper at read, more storage. Best for known sizes.
- **On-demand** via a URL service — flexible (any size on the fly), pay per transform.

Hybrid: pre-generate the 3–5 sizes you use 95% of the time; let a service handle the long tail.

## Responsive Images (`srcset`)

Serve the right resolution for the device:

```html
<img
  src="hero-800.webp"
  srcset="hero-400.webp 400w, hero-800.webp 800w, hero-1600.webp 1600w"
  sizes="(max-width: 600px) 100vw, 800px"
  width="800"
  height="600"
  alt="Hero"
/>
```

- **Always set `width` and `height`** — prevents CLS.
- **Use `<picture>` with format fallback**:

```html
<picture>
  <source srcset="hero.avif" type="image/avif" />
  <source srcset="hero.webp" type="image/webp" />
  <img src="hero.jpg" alt="..." width="800" height="600" />
</picture>
```

## Blur Placeholders (BlurHash / LQIP)

A 20–30 byte blur of the image, rendered instantly while the real image loads.

### BlurHash

```bash
npm install blurhash sharp
```

Generate on upload, store with the image record:

```ts
import { encode } from 'blurhash'

async function makeBlurHash(input: Buffer) {
  const { data, info } = await sharp(input)
    .raw()
    .ensureAlpha()
    .resize(32, 32, { fit: 'inside' })
    .toBuffer({ resolveWithObject: true })
  return encode(new Uint8ClampedArray(data), info.width, info.height, 4, 3)
}
```

Render client-side:

```tsx
import { Blurhash } from 'react-blurhash'

<div className="relative size-full">
  {!loaded && <Blurhash hash={image.blurHash} width="100%" height="100%" />}
  <img onLoad={() => setLoaded(true)} src={image.url} className={loaded ? '' : 'opacity-0'} />
</div>
```

### LQIP Alternative

A 20×20 base64-encoded blurred JPEG. Same effect, larger payload (~1 KB vs 20 bytes), no decode library needed.

Pick BlurHash for many images per page (lower payload); LQIP for hero-only.

## Lazy Loading

```html
<img src="thumb.webp" loading="lazy" alt="..." />
```

Native lazy-loading is enough for most cases. Above-the-fold images get `loading="eager"` (and possibly `fetchpriority="high"`).

For custom lazy loading (background images, fancier triggers), use Intersection Observer:

```tsx
function LazyImage({ src, ...rest }: ImgProps) {
  const [loaded, setLoaded] = useState(false)
  const ref = useRef<HTMLImageElement>(null)

  useEffect(() => {
    if (!ref.current) return
    const obs = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting) {
        ref.current!.src = src
        setLoaded(true)
        obs.disconnect()
      }
    }, { rootMargin: '200px' })
    obs.observe(ref.current)
    return () => obs.disconnect()
  }, [src])

  return <img ref={ref} {...rest} />
}
```

## CDN Serving

Always serve images through a CDN. Setting `Cache-Control: public, max-age=31536000, immutable` on uploaded variants gives infinite cacheability (the URL changes with new uploads — never reuse a key).

For hosted services (Cloudinary, ImageKit), the CDN is included.

## Hosted Image Services

For dynamic resize/crop without running Sharp:

- **Cloudinary** — generous free tier, strong DX, expensive at scale.
- **ImageKit** — cheaper than Cloudinary, similar features.
- **Cloudflare Images** — flat per-image pricing, integrates with R2.
- **imgix** — pioneer, premium.
- **Next.js `<Image>`** — bundled, uses the hosting platform's image service (Vercel-optimized).

URL-based transforms:

```
https://res.cloudinary.com/account/image/upload/w_400,h_400,c_fill,q_auto,f_auto/orders/abc.jpg
```

`q_auto,f_auto` is the killer combo — auto-quality based on content, auto-format negotiation per browser.

## Video

Don't try to self-host video. The pipeline (transcoding, adaptive bitrate, DRM, CDN) is enormous. Use:

- **Mux** — developer-focused, transcoding + streaming + analytics.
- **Cloudflare Stream** — cheap, decent features.
- **Vimeo OTT / Bunny Stream** — turnkey.

For audio: similar advice — **Cloudflare R2 + a streaming player** if you have simple needs, **Mux / SoundCloud** for richer features.

## Common Mistakes

- **Serving 4 MB camera originals as avatars.** Always transform.
- **No EXIF rotation.** Phone photos sideways. Always `.rotate()` first.
- **Forgetting to strip EXIF.** GPS coordinates leak on user uploads.
- **Same key for replacements.** CDN serves stale forever. Use a fresh key per upload.
- **`fit: 'fill'` on photos.** Stretches faces grotesquely. Use `cover` or `contain`.
- **Enlarging tiny images.** Blurry mush. `withoutEnlargement: true`.
- **No `width`/`height` on `<img>`.** CLS skyrockets. Always set.
- **Lazy-loading above-the-fold images.** Defers the LCP candidate. `loading="eager"` for hero.
- **One huge image for all screens.** Mobile pays the desktop price. Use `srcset`.
- **No blur placeholder for slow networks.** Blank rectangles look broken. BlurHash or LQIP.
- **Running Sharp in the request handler.** Slow uploads. Background job.
- **Sharp pipeline reused twice without `clone()`.** Second call errors.
- **PNG for photos.** 10× the size of JPEG/WebP at the same quality. Use it only for transparency or logos.
- **No CDN.** Object storage direct is slow globally and expensive in egress.
- **Self-hosting video.** Transcoding, DRM, adaptive bitrate — don't. Use a service.
