# Progressive Web Apps & Offline

How to build installable, offline-capable web apps. Read before adding a service worker, manifest, or offline behavior.

## Decision Tree: PWA vs Alternatives

| You need | Pick |
|---|---|
| Installable, works offline, no app stores | **PWA** |
| iOS App Store / Google Play presence | **React Native** (see `mobile-react-native.md`) |
| Just a fast website, occasional offline tolerance | **Service worker for caching only**, skip the install prompt |
| Heavy offline data (megabytes), complex sync | **PWA with IndexedDB + background sync** |
| Push notifications on iOS | PWA works since iOS 16.4 **only when installed to home screen** |

PWAs shine for:
- Internal tools, dashboards, field-worker apps.
- Markets where app store presence is optional.
- Cross-platform with one codebase and no review queues.
- Apps where update speed matters (PWAs update on next visit).

PWAs are limited:
- Background tasks beyond Background Sync / Periodic Sync are constrained.
- iOS web push only when installed to home screen.
- No access to many native APIs (Bluetooth on iOS, NFC reading, deep system integration).

## PWA Requirements

A PWA needs three things:

1. **HTTPS** — service workers don't register on HTTP (except localhost).
2. **Web App Manifest** at a discoverable URL.
3. **Service Worker** registered and intercepting fetches.

Beyond that, browsers show the install prompt when the app meets engagement and quality heuristics (varies by browser).

## Web App Manifest

`public/manifest.webmanifest`:

```json
{
  "name": "Water Vending",
  "short_name": "WaterVending",
  "description": "Find water vending machines near you.",
  "start_url": "/?source=pwa",
  "scope": "/",
  "display": "standalone",
  "orientation": "portrait",
  "background_color": "#ffffff",
  "theme_color": "#1A73E8",
  "icons": [
    { "src": "/icons/192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icons/512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "/icons/maskable.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ],
  "screenshots": [
    { "src": "/screens/home.png", "sizes": "1080x1920", "type": "image/png", "form_factor": "narrow" }
  ]
}
```

Link in `index.html`:

```html
<link rel="manifest" href="/manifest.webmanifest" />
<meta name="theme-color" content="#1A73E8" />
<link rel="apple-touch-icon" href="/icons/apple-touch.png" />
```

### Rules

- **Provide both 192×192 and 512×512 PNG icons.** Both are required for install on most platforms.
- **Maskable icon** (`purpose: "maskable"`) — full-bleed PNG with safe zone. Android adapts it to the platform's icon shape.
- **`display: "standalone"`** is the typical choice — looks like a native app. `"minimal-ui"` keeps a thin URL bar.
- **`start_url`** can include a tracking param to distinguish PWA launches from browser visits.
- **`scope`** — restrict which URLs the PWA controls. Usually `/`.

## Service Worker Strategies (Workbox)

Workbox provides battle-tested caching strategies. Don't write a service worker by hand — get them wrong once and your users are stuck on a broken cache forever.

```bash
npm install -D vite-plugin-pwa workbox-window
```

### Strategy Selection

| Resource | Strategy |
|---|---|
| App shell (HTML, JS, CSS) | **Stale-While-Revalidate** or **Network-First** |
| Static assets with content hash | **Cache-First** (immutable) |
| API GET responses | **Stale-While-Revalidate** or **Network-First** with cache fallback |
| Images, fonts | **Cache-First** with expiration |
| Mutations (POST/PUT/DELETE) | **Network-Only** with Background Sync queue |

### Pattern Definitions

- **Cache-First** — serve from cache; fall back to network if missing. For immutable, hashed assets.
- **Network-First** — try network; fall back to cache on failure. For data that should be fresh but tolerable when offline.
- **Stale-While-Revalidate** — serve cache instantly, refresh in background. Best UX for "good enough fresh."
- **Network-Only** — always network. For non-cacheable requests.
- **Cache-Only** — never network. For pre-cached assets you know are there.

## vite-plugin-pwa

```ts
// vite.config.ts
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.ico', 'apple-touch.png'],
      manifest: { /* ...same as above... */ },
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,png,woff2}'],
        runtimeCaching: [
          {
            urlPattern: /^https:\/\/api\.example\.com\/.*$/,
            handler: 'StaleWhileRevalidate',
            options: {
              cacheName: 'api-cache',
              expiration: { maxEntries: 100, maxAgeSeconds: 5 * 60 },
              cacheableResponse: { statuses: [0, 200] },
            },
          },
          {
            urlPattern: /\.(?:png|jpg|jpeg|svg|webp|avif)$/,
            handler: 'CacheFirst',
            options: {
              cacheName: 'image-cache',
              expiration: { maxEntries: 200, maxAgeSeconds: 30 * 24 * 60 * 60 },
            },
          },
        ],
      },
      devOptions: { enabled: false },     // don't run SW in dev — caches break HMR
    }),
  ],
})
```

### Register and Handle Updates

```ts
import { registerSW } from 'virtual:pwa-register'

const updateSW = registerSW({
  onNeedRefresh() {
    if (confirm('New version available. Reload?')) updateSW(true)
  },
  onOfflineReady() {
    toast('App ready for offline use.')
  },
})
```

### Skip Waiting Carefully

`registerType: 'autoUpdate'` skips the waiting phase automatically — the new SW activates as soon as it installs. That's convenient but can break clients mid-session if assets change.

For critical apps, use `'prompt'` and let the user choose when to reload.

## Offline Data with IndexedDB

For anything beyond a few KB of key-value, use IndexedDB.

### Choose a Library

- **`idb`** (Jake Archibald) — thin promise wrapper around raw IndexedDB. Minimal.
- **Dexie** — fluent API, indexes, queries, migrations. Recommended for non-trivial offline data.

```ts
import Dexie, { type Table } from 'dexie'

export interface CachedMachine {
  id: string
  name: string
  lat: number
  lng: number
  status: string
  updatedAt: number
}

class AppDB extends Dexie {
  machines!: Table<CachedMachine, string>

  constructor() {
    super('app')
    this.version(1).stores({
      machines: 'id, status, updatedAt',
    })
  }
}

export const db = new AppDB()
```

### Versioning

Every schema change is a new `version(n).stores(...)`. Never edit a past version. Migrations:

```ts
this.version(2).stores({
  machines: 'id, status, updatedAt, operatorId',
}).upgrade((tx) =>
  tx.table('machines').toCollection().modify((m) => {
    m.operatorId = m.operatorId ?? null
  }),
)
```

### Read/Write

```ts
await db.machines.bulkPut(machines)
const recent = await db.machines.where('updatedAt').above(cutoff).toArray()
```

Wrap in try/catch — quota errors and "user cleared site data" both surface here.

## Install Prompt

Browsers show a default install banner when heuristics fire. You can also trigger it on demand.

### Capture the Event

```ts
let deferred: BeforeInstallPromptEvent | null = null

window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault()
  deferred = e as BeforeInstallPromptEvent
  setInstallable(true)
})
```

### Custom Install Button

```tsx
function InstallButton() {
  const [show, setShow] = useState(false)
  const deferredRef = useRef<BeforeInstallPromptEvent | null>(null)

  useEffect(() => {
    const handler = (e: Event) => {
      e.preventDefault()
      deferredRef.current = e as BeforeInstallPromptEvent
      setShow(true)
    }
    window.addEventListener('beforeinstallprompt', handler)
    return () => window.removeEventListener('beforeinstallprompt', handler)
  }, [])

  if (!show) return null
  return (
    <button onClick={async () => {
      const ev = deferredRef.current
      if (!ev) return
      await ev.prompt()
      const { outcome } = await ev.userChoice
      if (outcome === 'accepted') setShow(false)
    }}>
      Install app
    </button>
  )
}
```

### Rules

- **Don't prompt on first visit.** Wait for engagement signals — second visit, completing a key action.
- **Respect dismissal.** Store "user said no" in localStorage and don't re-prompt for weeks.
- **Detect already-installed state**:

```ts
window.matchMedia('(display-mode: standalone)').matches
// or navigator.standalone on iOS
```

### iOS Caveats

iOS Safari does **not** support `beforeinstallprompt`. Show manual instructions:

> Tap **Share**, then **Add to Home Screen**.

Detect iOS Safari and conditionally show the instructions.

## Web Push Notifications

Web push works on Chrome, Firefox, Edge, and (since iOS 16.4) on Safari **when the PWA is installed to home screen**.

### VAPID Keys

Generate a VAPID keypair once (server-side):

```bash
npx web-push generate-vapid-keys
```

Store the public key in the client, the private key on the server.

### Subscribe

```ts
async function subscribePush(publicVapidKey: string) {
  const reg = await navigator.serviceWorker.ready
  const sub = await reg.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(publicVapidKey),
  })
  await fetch('/api/push/subscribe', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(sub),
  })
}
```

### Permission UX

```ts
async function requestPushPermission() {
  if (Notification.permission === 'granted') return true
  if (Notification.permission === 'denied') return false
  const result = await Notification.requestPermission()
  return result === 'granted'
}
```

Rules:

- **Ask in context.** Right after the user does something that justifies notifications, not on page load.
- **Pre-prompt screen.** Explain value before the browser prompt fires — once denied, browsers don't re-ask for weeks.
- **`userVisibleOnly: true`** is required by Chrome/Firefox. Silent push is not allowed.

### Server-Side Send

```ts
import webpush from 'web-push'

webpush.setVapidDetails('mailto:you@example.com', env.VAPID_PUBLIC, env.VAPID_PRIVATE)

await webpush.sendNotification(subscription, JSON.stringify({
  title: 'Order ready',
  body: 'Your water is ready for pickup at Kilimani.',
  url: '/orders/123',
}))
```

Handle `410 Gone` — subscription is dead, delete it.

## App Shell Architecture

The "app shell" is the minimal HTML, CSS, and JS that renders the chrome (header, nav, basic layout) before any data loads.

### Why

- First paint is instant after install — shell is cached.
- Subsequent navigations feel native — only data loads, not the full document.

### How

1. SSR or pre-render the shell HTML.
2. Hydrate client-side with React/Vue/whatever.
3. Service worker caches the shell aggressively (cache-first).
4. Data is fetched separately and cached with stale-while-revalidate.

With Vite + a SPA, the shell is essentially `index.html` + the main JS bundle. Pre-cache both. Routes load on demand.

## Testing Offline Mode

### Chrome DevTools

- **Network tab** → "Offline" throttling. Quick test.
- **Application tab** → Service Workers → "Offline" checkbox. More accurate.
- **Application tab** → Clear storage → "Clear site data" to start fresh.

### Lighthouse PWA Audit

```bash
npx lighthouse https://example.com --preset=desktop --view
```

Targets all the PWA criteria — manifest, service worker, installability.

### Manual Test Plan

1. Load app online. Browse main paths.
2. Switch to airplane mode.
3. Reload — app shell renders, cached data shows.
4. Navigate around — already-visited pages work.
5. Try a mutation — should queue or show "offline, will retry."
6. Go back online — queued mutations should sync.

Run this on every major release. Offline regressions are silent until users complain.

### Background Sync

For deferred mutations:

```ts
// In the SW
self.addEventListener('sync', (event) => {
  if (event.tag === 'sync-orders') {
    event.waitUntil(syncPendingOrders())
  }
})

// In the app
const reg = await navigator.serviceWorker.ready
await reg.sync.register('sync-orders')
```

Background Sync isn't supported everywhere (notably iOS). Fall back to retrying on next app open.

## Common Mistakes

- **Service worker registered in development.** Stale caches break HMR. Disable in dev (`devOptions.enabled: false`).
- **No update mechanism.** Users stuck on a six-month-old version forever. Use `autoUpdate` or `prompt`.
- **Caching HTML with `CacheFirst`.** Users never see updates. Use `NetworkFirst` or `StaleWhileRevalidate`.
- **Caching authenticated API responses publicly.** One user's data shows up for another. Scope cache by user or skip auth endpoints.
- **No `cacheableResponse: { statuses: [0, 200] }`.** Opaque responses (cross-origin) get cached as failures.
- **Manifest icons missing maskable variant.** Android renders a small icon on a colored background. Looks broken.
- **iOS expecting `beforeinstallprompt`.** It doesn't fire. Show manual instructions on iOS.
- **Push permission requested on page load.** Denial rate skyrockets. Ask after a value moment.
- **No handling of `410 Gone` push responses.** Dead subscriptions accumulate.
- **IndexedDB writes without try/catch.** Quota errors and private-mode restrictions crash the flow.
- **Schema changes without migrations.** New version errors out for existing users.
- **No "you're offline" UI.** Users see broken-looking app and assume it's down.
- **Background Sync as the only retry path.** iOS doesn't support it. Have a foreground retry too.
- **App shell that depends on uncached API calls.** Defeats the point. Shell should render without network.
- **`unregister()` on the SW from app code.** Cache survives but doesn't update — orphan caches forever.
- **Forgetting to test on real devices.** DevTools "Offline" doesn't catch everything; airplane-mode test on a phone does.
