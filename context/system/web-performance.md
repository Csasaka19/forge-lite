# Web Performance

Frontend performance standards. Read before adding a heavy dependency, a hero image, or anything that touches the critical render path.

## Core Web Vitals Targets

These are the numbers Google uses for ranking and what users actually feel. Hit them on production hardware, not on your laptop.

- **LCP (Largest Contentful Paint)** — under **2.5s** at p75 on mobile 4G.
- **INP (Interaction to Next Paint)** — under **200ms** at p75. (INP replaced FID in 2024.)
- **CLS (Cumulative Layout Shift)** — under **0.1** at p75.

Measure on real devices, not just on Chrome DevTools. Use `web-vitals` library to report from real users:

```ts
import { onCLS, onINP, onLCP } from 'web-vitals'

onLCP((m) => sendToAnalytics('LCP', m.value))
onINP((m) => sendToAnalytics('INP', m.value))
onCLS((m) => sendToAnalytics('CLS', m.value))
```

Treat the targets as a floor, not a ceiling. If the budget is being hit but the page _feels_ slow, the numbers aren't telling the whole story — go investigate.

## Bundle Size Budget

- **Initial JS:** under **200 KB gzipped** for most apps. Marketing pages aim for under **100 KB**. Dashboards can stretch to **300 KB** if measurably needed.
- **Initial CSS:** under **50 KB gzipped**.
- **Per-route chunk:** under **100 KB gzipped**.
- **Total transferred on first load:** under **500 KB gzipped** including images and fonts.

Measure on every PR. Enforce in CI:

```yaml
- run: npm run build
- run: npx bundlesize     # fails the build if budget exceeded
```

Inspect what's in the bundle:

```bash
npx vite-bundle-visualizer
```

Look for: duplicate copies of libraries, moment.js where Date would do, full lodash where one function would do, polyfills you don't need.

### Watch For

- A single dependency adding 50+ KB. Replace with a lighter alternative or import only what you use (`lodash/debounce`, not `lodash`).
- Moment.js → use `date-fns` or `dayjs` or native `Intl`.
- Full icon sets → import individual icons. `lucide-react`'s tree-shaking is good; verify in the visualizer.
- Polyfills loaded for browsers you don't support. Check `browserslist` config.

## Code Splitting

Default: route-based lazy loading. Don't ship the dashboard's code to a user on the landing page.

```tsx
import { lazy, Suspense } from 'react'

const Dashboard = lazy(() => import('./pages/Dashboard'))

<Route
  path="/dashboard"
  element={
    <Suspense fallback={<PageSkeleton />}>
      <Dashboard />
    </Suspense>
  }
/>
```

### Component-Level Splitting

Lazy-load heavy components that aren't visible on first paint:

- Modals and dialogs.
- Charts (Recharts, Chart.js can be 100+ KB).
- Rich text editors (TipTap, Lexical, Slate are large).
- Map components (Leaflet, Mapbox).
- Code editors (Monaco, CodeMirror).

```tsx
const Chart = lazy(() => import('./Chart'))

{showChart && (
  <Suspense fallback={<ChartSkeleton />}>
    <Chart data={data} />
  </Suspense>
)}
```

### Preload on Intent

When you know the user is about to navigate, preload the chunk:

```tsx
<Link
  to="/dashboard"
  onMouseEnter={() => import('./pages/Dashboard')}
>
  Dashboard
</Link>
```

React Router v7 and Next.js do this automatically with `<Link>` prefetching. Confirm it's enabled.

## Image Optimization

Images are usually the heaviest asset on a page. Treat every one as a budget line.

### Format

- **AVIF** first, **WebP** fallback, **JPEG/PNG** as last resort. Modern browsers all support WebP; AVIF saves another 20–30%.
- Serve via `<picture>` with multiple `<source>` elements, or use a CDN that negotiates by `Accept` header (Cloudinary, ImageKit, Vercel Image Optimization).

```html
<picture>
  <source srcset="hero.avif" type="image/avif" />
  <source srcset="hero.webp" type="image/webp" />
  <img src="hero.jpg" alt="..." width="1200" height="600" />
</picture>
```

### Responsive Sizes

Always set `width` and `height` attributes — prevents CLS. Use `srcset` to serve the right resolution.

```html
<img
  src="machine-800.webp"
  srcset="machine-400.webp 400w, machine-800.webp 800w, machine-1200.webp 1200w"
  sizes="(max-width: 600px) 100vw, 800px"
  width="800"
  height="600"
  alt="..."
/>
```

### Lazy Loading

Below-the-fold images use `loading="lazy"`. Above-the-fold (hero, LCP candidate) use `loading="eager"` and consider `fetchpriority="high"`.

```html
<img src="hero.webp" loading="eager" fetchpriority="high" ... />
<img src="thumb.webp" loading="lazy" ... />
```

Don't lazy-load images visible on initial paint — they become the LCP target and lazy loading defers them.

### Image CDN

For user-uploaded content, route through an image CDN. Cloudinary, Imgix, Cloudflare Images, or Vercel's built-in `<Image>` component. They handle format negotiation, resizing, and caching.

Never serve a 4 MB camera-original image to a 400×400 avatar slot.

## Font Loading

Fonts are the second-biggest CLS culprit after images.

### Rules

- `font-display: swap` in every `@font-face`. Shows fallback text immediately, swaps when font loads. Never `font-display: block` — invisible text is worse than fallback text.
- **Preload** critical fonts so they're available before CSS parses:

```html
<link rel="preload" href="/fonts/dm-sans-var.woff2" as="font" type="font/woff2" crossorigin />
```

- Only preload fonts used above the fold. Preloading everything destroys the benefit.
- Use **variable fonts** when available. One file covers all weights.
- Use `woff2` format. `woff` and `ttf` are larger and unnecessary on modern browsers.

### Self-Host vs Google Fonts

- Self-host. Better cache control, no third-party request, no privacy concerns. Use `@fontsource` packages or download from `google-webfonts-helper`.
- If using Google Fonts directly, add `&display=swap` and preconnect:

```html
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
```

### Subsetting

If the font supports characters you don't use (CJK on a Latin-only site, full extended Latin when you only need basic), subset it. Many `@fontsource` variants ship pre-subset.

## Caching Strategy

### Asset Caching

- Build output has content-hashed filenames (`app.a1b2c3.js`). Vite and Next.js do this by default.
- Serve hashed assets with `Cache-Control: public, max-age=31536000, immutable`. One year, never revalidate.
- The `immutable` directive tells browsers not to revalidate even on reload. Critical for performance.

### HTML Caching

- HTML references hashed assets, so it must always be fresh.
- `Cache-Control: no-cache` or short `max-age=60, must-revalidate`.
- Never `Cache-Control: public, max-age=31536000` on HTML — users will be stuck on old versions.

### API Caching

- Authenticated responses: `Cache-Control: private, no-store`.
- Public read endpoints: `Cache-Control: public, max-age=60, stale-while-revalidate=300` for low-churn data.
- Use `ETag` for conditional requests. Server returns 304 on match, saving bandwidth.

### Service Worker

Add a service worker when you need:

- Offline support for a real use case (PWA, field worker app).
- Custom caching beyond what HTTP can express.

Don't add one by default. Service workers are powerful and easy to mis-configure — stuck caches, broken updates, mysterious bugs.

If you do, use Workbox. Test the update flow ruthlessly.

## Rendering Performance

### Avoid Layout Thrashing

Layout thrashing happens when you read a layout property (`offsetHeight`, `scrollTop`, `getBoundingClientRect`) after writing one, forcing the browser to recalculate.

```ts
// Bad — read, write, read, write — thrash
for (const el of items) {
  const h = el.offsetHeight   // read
  el.style.height = h * 2 + 'px' // write
}

// Good — batch reads, then batch writes
const heights = items.map((el) => el.offsetHeight)
items.forEach((el, i) => { el.style.height = heights[i] * 2 + 'px' })
```

In React, this rarely comes up because state updates batch, but watch for direct DOM access in `useEffect`.

### Virtualize Long Lists

Render only what's visible. Beyond ~100 items, use a virtualizer:

- `@tanstack/react-virtual` — general-purpose.
- `react-window` / `react-virtuoso` — older but battle-tested.

```tsx
import { useVirtualizer } from '@tanstack/react-virtual'

const virtualizer = useVirtualizer({
  count: items.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 50,
})
```

### Debounce / Throttle

- **Debounce** — fire after the user stops doing the thing. Search input, resize handler, autosave.
- **Throttle** — fire at most every N ms. Scroll handler, mousemove.

```ts
import { debounce, throttle } from 'lodash-es'

const onSearch = debounce((q: string) => fetchResults(q), 250)
const onScroll = throttle(() => updateScrollIndicator(), 100)
```

For React, prefer `useDeferredValue` or `useTransition` over manual debouncing for state-driven work — they integrate with concurrent rendering.

### Memoization

`React.memo`, `useMemo`, `useCallback` are not free. Use them when:

- A component renders frequently with the same props (list rows, presentational wrappers).
- A computation is genuinely expensive.

Don't wrap everything. Profile first. Most components don't need memoization.

### Avoid Re-renders

- Move state down. State in the root re-renders the whole tree on every change.
- Split contexts. One big context with everything causes every consumer to re-render on any change.
- Use a state manager (Zustand, Jotai) for cross-cutting state. Subscribers re-render only when their slice changes.

## Lighthouse CI

Run Lighthouse on every PR. Fail the build if scores drop.

```yaml
- name: Lighthouse CI
  uses: treosh/lighthouse-ci-action@v11
  with:
    urls: |
      https://preview.example.com/
      https://preview.example.com/find
    uploadArtifacts: true
    temporaryPublicStorage: true
    configPath: ./.lighthouserc.json
```

`.lighthouserc.json`:

```json
{
  "ci": {
    "assert": {
      "assertions": {
        "categories:performance": ["error", { "minScore": 0.9 }],
        "categories:accessibility": ["error", { "minScore": 0.95 }],
        "largest-contentful-paint": ["error", { "maxNumericValue": 2500 }],
        "cumulative-layout-shift": ["error", { "maxNumericValue": 0.1 }]
      }
    }
  }
}
```

Tune thresholds to your app, but never lower them silently. Every regression is a conversation.

### Real-User Monitoring

Lighthouse measures synthetic conditions. Pair it with real-user monitoring (Vercel Analytics, Cloudflare Web Analytics, Datadog RUM). RUM catches what synthetic tests miss: real network conditions, real devices, real session patterns.

## Common Mistakes

- **Shipping all routes in the initial bundle.** Use lazy loading per route. First-paint should not include the admin dashboard.
- **No bundle budget in CI.** Bundle bloat is silent until shipping. Enforce on every PR.
- **Hero image at full camera resolution.** 4 MB JPEG where 80 KB WebP would do. Use an image CDN or pre-process at build.
- **Missing `width`/`height` on images.** CLS skyrockets. Always set intrinsic dimensions.
- **`font-display: block` (or default).** Invisible text for hundreds of milliseconds. Use `swap`.
- **Preloading every font.** Defeats the prioritization. Preload only fonts used above the fold.
- **Long lists rendered without virtualization.** 5,000 DOM nodes destroy scroll performance.
- **`useMemo` everywhere "just in case."** Adds overhead and memory; helps nothing.
- **One giant `Context` with the whole app state.** Every consumer re-renders on every change. Split or use a store.
- **Service worker added for "future PWA needs."** Now caching is wrong and updates ship broken. Add one only when you have a use case.
- **Caching HTML for a year.** Users stuck on old versions for months.
- **Measuring performance only on the developer's M-series laptop on home wifi.** Test on a throttled mid-tier Android and 4G. That's where users live.
- **Loading polyfills for IE11 in 2026.** Update `browserslist` to drop ancient targets. Ship modern code.
- **Big third-party scripts loaded synchronously in `<head>`.** Analytics, tag managers, chat widgets — defer or load on interaction.
