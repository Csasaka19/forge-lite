# Maps & Geolocation

How to build map features with Leaflet + React-Leaflet. Read before adding a map, a marker, or any location-aware feature.

## Stack Choice

- **Leaflet** + **react-leaflet** for most maps. Free, lightweight, no API key, works with OpenStreetMap tiles.
- **Mapbox GL** / **MapLibre GL** for vector tiles, 3D, advanced styling. Mapbox needs a token; MapLibre is the open fork.
- **Google Maps** only when the feature genuinely needs it (Places autocomplete, Street View). Bring the cost.

Default to Leaflet + OSM. Switch only with a real reason.

## Installation

```bash
npm install leaflet react-leaflet
npm install -D @types/leaflet
```

Import Leaflet CSS once at the app root — without it, tiles render at 0×0:

```ts
import 'leaflet/dist/leaflet.css'
```

## Basic Map

```tsx
import { MapContainer, TileLayer, Marker, Popup } from 'react-leaflet'

<MapContainer
  center={[-1.2921, 36.8219]}
  zoom={12}
  style={{ height: '500px', width: '100%' }}
  scrollWheelZoom={false}
>
  <TileLayer
    attribution='&copy; OpenStreetMap contributors'
    url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
  />
  <Marker position={[-1.2921, 36.8219]}>
    <Popup>A pretty Nairobi popup.</Popup>
  </Marker>
</MapContainer>
```

Always set an explicit `height` on the container or its parent. The map renders into a div with computed height; `0` means invisible map.

## Tile Providers

- **OpenStreetMap** — free, no key, attribution required. Reasonable for non-commercial; for production, use a paid mirror.
- **CartoDB (Positron, Dark Matter)** — clean basemaps, free for low usage. `https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png`.
- **Stadia Maps** — generous free tier, attribution required.
- **MapTiler** — vector + raster, free up to limits.
- **Mapbox** — premium, requires token.

For production at scale, never hammer the OSM tile server directly — read their tile usage policy. Mirror to your own CDN or use a paid provider.

## Custom Markers

Default Leaflet markers break with bundlers (the icon URLs resolve wrong). Two options:

### DivIcon (preferred for status pins)

```tsx
import L from 'leaflet'

const statusIcon = (color: string) =>
  L.divIcon({
    className: 'status-pin',
    html: `<div style="background:${color}" class="size-4 rounded-full ring-2 ring-white"></div>`,
    iconSize: [16, 16],
    iconAnchor: [8, 8],
  })

<Marker position={pos} icon={statusIcon('#16a34a')} />
```

DivIcons are HTML — style with Tailwind, animate with CSS, no image assets.

### Image Icon

```tsx
const customIcon = L.icon({
  iconUrl: '/marker.svg',
  iconSize: [32, 32],
  iconAnchor: [16, 32],
  popupAnchor: [0, -32],
})
```

`iconAnchor` is the pixel that sits on the coordinate. For a pin shape, that's the bottom-center.

## Marker Clustering

Beyond ~100 markers, individual markers slow the map down and clutter the UI. Cluster them.

```bash
npm install react-leaflet-cluster
```

```tsx
import MarkerClusterGroup from 'react-leaflet-cluster'

<MarkerClusterGroup chunkedLoading>
  {machines.map((m) => (
    <Marker key={m.id} position={[m.lat, m.lng]} />
  ))}
</MarkerClusterGroup>
```

- `chunkedLoading` adds markers in batches — keeps the UI responsive with 1000+ points.
- Customize cluster icons via `iconCreateFunction` for branded clusters.
- Set `disableClusteringAtZoom={16}` to show individuals at street level.

## Geolocation API

```ts
function useUserLocation() {
  const [coords, setCoords] = useState<LatLng | null>(null)
  const [error, setError] = useState<string | null>(null)

  const request = useCallback(() => {
    if (!navigator.geolocation) {
      setError('Geolocation not supported')
      return
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => setCoords({ lat: pos.coords.latitude, lng: pos.coords.longitude }),
      (err) => setError(err.message),
      { enableHighAccuracy: false, timeout: 5000, maximumAge: 60_000 },
    )
  }, [])

  return { coords, error, request }
}
```

### Rules

- **Always require a user gesture.** Don't auto-request on page load — browsers reject and users find it creepy.
- **Set a timeout.** Default `getCurrentPosition` can hang indefinitely on some browsers. 5s is plenty.
- **Provide a fallback.** If permission is denied or timeout fires, offer manual address entry.
- **`enableHighAccuracy: false`** for city-level features. High accuracy drains battery and isn't needed.
- **Cache with `maximumAge`** so repeat requests don't re-query GPS.

### Permission States

Check before requesting (saves a useless prompt):

```ts
const perm = await navigator.permissions.query({ name: 'geolocation' })
if (perm.state === 'denied') {
  // Show address-input fallback immediately
}
```

## Geocoding

Converting addresses to coordinates and back. Don't roll your own.

### Forward Geocoding (address → lat/lng)

**Nominatim (OpenStreetMap)** — free, no key, rate-limited (1 req/sec):

```ts
async function geocode(address: string): Promise<LatLng | null> {
  const res = await fetch(
    `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(address)}&format=json&limit=1`,
    { headers: { 'User-Agent': 'YourApp/1.0 (contact@example.com)' } },
  )
  const results = await res.json()
  return results[0] ? { lat: +results[0].lat, lng: +results[0].lon } : null
}
```

Nominatim **requires** a User-Agent identifying the app. Their public service is for low-volume use; for production, self-host Nominatim or use a paid provider (Mapbox, Google, MapTiler, LocationIQ).

### Reverse Geocoding (lat/lng → address)

Same endpoint, different params: `?lat=X&lon=Y&format=json`.

### Autocomplete

For "type to search" inputs, use a service with autocomplete: Mapbox Places, Google Places, MapTiler Geocoding. Debounce input (300ms) and cancel stale requests:

```ts
const debounced = useDeferredValue(input)

useEffect(() => {
  if (!debounced) return
  const ctrl = new AbortController()
  fetch(`/api/geocode?q=${encodeURIComponent(debounced)}`, { signal: ctrl.signal })
    .then((r) => r.json())
    .then(setResults)
    .catch(() => {})
  return () => ctrl.abort()
}, [debounced])
```

## Distance Calculation

Use the haversine formula for great-circle distance. Accurate enough for anything under a few thousand km:

```ts
export function distanceKm(a: LatLng, b: LatLng): number {
  const R = 6371
  const dLat = ((b.lat - a.lat) * Math.PI) / 180
  const dLng = ((b.lng - a.lng) * Math.PI) / 180
  const lat1 = (a.lat * Math.PI) / 180
  const lat2 = (b.lat * Math.PI) / 180
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2
  return 2 * R * Math.asin(Math.sqrt(h))
}
```

For server-side, PostgreSQL with PostGIS exposes `ST_Distance_Sphere`. Use it for radius queries — it's indexable and fast.

## Offline Maps

Tile caching for offline use is complex. Options in order of effort:

- **Service Worker** — cache visited tiles. Works for revisits to seen areas. Doesn't help unseen ones.
- **`leaflet.offline`** plugin — pre-download tiles for a region.
- **Vector tiles** with MapLibre + offline pack — best fidelity offline, more setup.

Don't promise full offline maps lightly. Storage budgets, tile licenses, and update strategies all need answers.

## Performance with Many Markers

- **Cluster** (above).
- **Canvas renderer** instead of SVG — Leaflet supports `preferCanvas={true}` on `MapContainer`. Faster for 500+ markers but loses per-marker DOM.
- **Render only what's visible** — filter to viewport bounds before passing markers:

```ts
const map = useMap()
const bounds = map.getBounds()
const visible = machines.filter((m) =>
  bounds.contains(L.latLng(m.lat, m.lng)),
)
```

- **Avoid `Popup` per marker** if many markers — they're DOM-expensive. Use a single shared popup component opened on marker click.

## Common Mistakes

- **Missing Leaflet CSS** — tiles render at 0×0, map looks blank.
- **Container with no height** — same result, easy to miss in CSS.
- **Default markers broken in bundlers** — Webpack/Vite mangle the icon URLs. Use DivIcon or fix the icon paths explicitly.
- **No timeout on `getCurrentPosition`** — promise hangs forever on some browsers.
- **Auto-requesting geolocation on page load** — denied by browser policies; user trust burned.
- **Hammering Nominatim from clients** — IP bans. Either proxy through your server with caching, or use a paid provider.
- **No `User-Agent` on Nominatim requests** — they will block you.
- **Rendering 5000 individual markers** — frame drops, dead browser. Cluster.
- **Computing distance with Pythagorean theorem on lat/lng** — wrong (lat/lng aren't a Euclidean plane). Use haversine.
- **Storing coordinates as floats with low precision** — round-trip errors. Store as `double precision` in Postgres or as numbers in JS; don't truncate.
- **Re-rendering the map on every state change** — `MapContainer` re-mount is expensive. Use `useMap()` and imperative updates for dynamic data.
- **No attribution** — OSM and most providers require it. Set on `TileLayer`. Don't hide it visually.
