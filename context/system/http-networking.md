# HTTP & Networking

How to talk to backends from the browser and mobile. Read before adding an API call, fetching data, or wiring up real-time.

## Decision Tree: How to Fetch Data

| Situation | Use |
|---|---|
| Server data, anywhere in the app | **TanStack Query** (`useQuery`) |
| Mutation (POST/PATCH/DELETE) | **TanStack Query** (`useMutation`) |
| One-off imperative call (event handler, util) | **Centralized `apiClient`** built on Fetch |
| Streaming server → client | **EventSource** or fetch + ReadableStream |
| Bidirectional realtime | **WebSocket** |
| File upload with progress | **XMLHttpRequest** (Fetch can't track upload progress yet) |

Don't fetch in `useEffect` directly. Either use TanStack Query (declarative) or call an imperative `apiClient` from event handlers — never both patterns mixed in the same component.

## Centralized API Client

One module owns: base URL, auth headers, error transformation, retries, timeout. Components don't see Fetch directly.

```ts
// src/lib/api.ts
import { z } from 'zod'

const BASE_URL = import.meta.env.VITE_API_URL

export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    public details?: unknown,
    public requestId?: string,
  ) {
    super(`[${status}] ${code}`)
  }
}

const ErrorBody = z.object({
  error: z.object({
    code: z.string(),
    message: z.string().optional(),
    details: z.unknown().optional(),
    requestId: z.string().optional(),
  }),
})

export async function api<T>(
  path: string,
  init: RequestInit & { timeoutMs?: number } = {},
): Promise<T> {
  const { timeoutMs = 10_000, headers, ...rest } = init
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), timeoutMs)

  try {
    const res = await fetch(`${BASE_URL}${path}`, {
      ...rest,
      credentials: 'include',
      headers: {
        Accept: 'application/json',
        ...(rest.body && !(rest.body instanceof FormData) ? { 'Content-Type': 'application/json' } : {}),
        ...headers,
      },
      signal: init.signal ?? ctrl.signal,
    })

    if (!res.ok) {
      const body = await res.json().catch(() => null)
      const parsed = ErrorBody.safeParse(body)
      const err = parsed.success ? parsed.data.error : { code: 'HTTP_ERROR' }
      throw new ApiError(res.status, err.code, err.details, err.requestId)
    }

    if (res.status === 204) return undefined as T
    return (await res.json()) as T
  } finally {
    clearTimeout(timer)
  }
}
```

### Rules

- **One client per app.** Don't sprinkle `fetch` calls across components.
- **`credentials: 'include'`** when using cookie auth. Required cross-origin.
- **Timeout via `AbortController`.** Fetch has no native timeout. 10s is a sane default.
- **Transform errors at the boundary.** Components throw/catch `ApiError`, never raw `Response`.
- **Don't set `Content-Type` for FormData.** The browser sets it with the multipart boundary.

### Fetch API, Not Axios

Native fetch is built in, supports streaming, and works on every modern runtime. Axios adds bundle size and an extra abstraction. Use fetch.

The only thing fetch can't do yet is **upload progress** — for that, see the upload section below.

## Typed Responses

Pair the API client with runtime validation (Zod) at the boundary. Network responses are untrusted; treating them as typed-by-assertion produces silent corruption.

```ts
const Machine = z.object({
  id: z.string(),
  name: z.string(),
  status: z.enum(['online', 'offline', 'maintenance']),
  pricePerLiter: z.number(),
})
export type Machine = z.infer<typeof Machine>

export async function getMachine(id: string): Promise<Machine> {
  const raw = await api<unknown>(`/machines/${id}`)
  return Machine.parse(raw)
}
```

For high-trust internal APIs, you can skip Zod and trust generated types from OpenAPI. For anything external or evolving, validate.

## Retry Logic

```ts
async function withRetry<T>(
  fn: () => Promise<T>,
  { retries = 3, baseMs = 300 }: { retries?: number; baseMs?: number } = {},
): Promise<T> {
  let lastErr: unknown
  for (let i = 0; i <= retries; i++) {
    try {
      return await fn()
    } catch (err) {
      lastErr = err
      if (!isRetryable(err) || i === retries) break
      const delay = baseMs * 2 ** i * (0.5 + Math.random())
      await new Promise((r) => setTimeout(r, delay))
    }
  }
  throw lastErr
}

function isRetryable(err: unknown): boolean {
  if (err instanceof ApiError) return err.status >= 500 || err.status === 429
  if (err instanceof Error && err.name === 'AbortError') return false
  return true   // network failure
}
```

### Rules

- **Never retry 4xx** (except 408 Timeout and 429 Too Many Requests). 400, 401, 403, 404, 422 won't change on retry.
- **Always retry 5xx and network failures.** Up to 3 times.
- **Exponential backoff with jitter.** Base × 2^attempt × random(0.5–1.5). Without jitter, retries thunder herd.
- **Honor `Retry-After`** for 429 if the server sends it.
- **Don't retry mutations** (POST/PATCH/DELETE) unless you have idempotency keys — retries cause double-charges, double-creates.

TanStack Query handles this with sensible defaults — configure once at the QueryClient level.

## TanStack Query

```ts
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,         // 30s — don't refetch within this window
      gcTime: 5 * 60_000,        // 5m — keep unused cache for this long
      retry: (count, err) => isRetryable(err) && count < 3,
      refetchOnWindowFocus: true,
    },
    mutations: {
      retry: false,              // never retry mutations by default
    },
  },
})

<QueryClientProvider client={queryClient}>
  <App />
</QueryClientProvider>
```

### Query Keys

Keys are arrays. First element is the resource; subsequent elements are filters.

```ts
useQuery({ queryKey: ['machines'], queryFn: getMachines })
useQuery({ queryKey: ['machines', { status }], queryFn: () => getMachines({ status }) })
useQuery({ queryKey: ['machines', id], queryFn: () => getMachine(id) })
```

Rules:

- **Most specific resource first.** `['machines', id]` not `[id, 'machines']`.
- **Filters as objects, not concatenated strings.** Stable across re-renders, easier to invalidate.
- **Hierarchical** — `['machines']` invalidation refetches every `['machines', ...]`.

### Mutations

```ts
const mutation = useMutation({
  mutationFn: (input: CreateOrderInput) => api<Order>('/orders', {
    method: 'POST',
    body: JSON.stringify(input),
  }),
  onSuccess: () => {
    queryClient.invalidateQueries({ queryKey: ['orders'] })
  },
})

<button onClick={() => mutation.mutate({ machineId, volume: 5 })}>Order</button>
```

### Invalidation

After a successful mutation, invalidate related queries:

```ts
onSuccess: (newOrder) => {
  queryClient.invalidateQueries({ queryKey: ['orders'] })
  queryClient.invalidateQueries({ queryKey: ['machines', newOrder.machineId] })
}
```

For surgical updates, write directly to the cache:

```ts
queryClient.setQueryData(['orders', newOrder.id], newOrder)
```

## Pagination

### Cursor-Based (preferred)

```ts
const { data, fetchNextPage, hasNextPage, isFetchingNextPage } = useInfiniteQuery({
  queryKey: ['orders'],
  queryFn: ({ pageParam }) =>
    api<{ data: Order[]; nextCursor: string | null }>(
      `/orders?${pageParam ? `cursor=${pageParam}&` : ''}limit=20`,
    ),
  initialPageParam: null as string | null,
  getNextPageParam: (last) => last.nextCursor,
})

const orders = data?.pages.flatMap((p) => p.data) ?? []
```

### Infinite Scroll

Pair with IntersectionObserver to trigger `fetchNextPage`:

```tsx
function LoadMoreSentinel({ onIntersect }: { onIntersect: () => void }) {
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (!ref.current) return
    const obs = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting) onIntersect()
    }, { rootMargin: '200px' })
    obs.observe(ref.current)
    return () => obs.disconnect()
  }, [onIntersect])
  return <div ref={ref} />
}
```

Rules:

- **Always have a "load more" button fallback** — keyboard users can't scroll-trigger.
- **Show a clear end state** — "You've reached the end" rather than silent stop.
- **Save scroll position** when navigating away and back; `useInfiniteQuery` keeps the cache, but the scroll position is yours to manage.

### Offset Pagination

For small admin tables only. Past page ~50 it becomes slow and prone to skipping/duplicating rows during concurrent inserts.

## Optimistic Updates

For "feels instant" UX on writes:

```ts
const toggleFavorite = useMutation({
  mutationFn: (id: string) =>
    api(`/machines/${id}/favorite`, { method: 'POST' }),

  onMutate: async (id) => {
    await queryClient.cancelQueries({ queryKey: ['machines', id] })
    const prev = queryClient.getQueryData<Machine>(['machines', id])
    queryClient.setQueryData<Machine>(['machines', id], (old) =>
      old ? { ...old, favorited: !old.favorited } : old,
    )
    return { prev }
  },

  onError: (_err, id, ctx) => {
    if (ctx?.prev) queryClient.setQueryData(['machines', id], ctx.prev)
  },

  onSettled: (_data, _err, id) => {
    queryClient.invalidateQueries({ queryKey: ['machines', id] })
  },
})
```

The four hooks: `onMutate` (snapshot + apply), `onError` (rollback), `onSuccess` (often empty here), `onSettled` (re-sync from server).

## File Upload

### Multipart Form Data

```ts
async function uploadAvatar(file: File): Promise<{ url: string }> {
  const form = new FormData()
  form.append('file', file)
  form.append('purpose', 'avatar')

  return api<{ url: string }>('/uploads', {
    method: 'POST',
    body: form,
  })
}
```

Never set `Content-Type` manually — the browser writes `multipart/form-data; boundary=...`.

### Progress Tracking

Fetch can't track upload progress yet. Use XMLHttpRequest:

```ts
export function uploadWithProgress(
  url: string,
  file: File,
  onProgress: (pct: number) => void,
): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest()
    const form = new FormData()
    form.append('file', file)

    xhr.upload.addEventListener('progress', (e) => {
      if (e.lengthComputable) onProgress((e.loaded / e.total) * 100)
    })
    xhr.addEventListener('load', () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve(JSON.parse(xhr.responseText))
      else reject(new ApiError(xhr.status, 'UPLOAD_FAILED'))
    })
    xhr.addEventListener('error', () => reject(new ApiError(0, 'NETWORK_ERROR')))
    xhr.open('POST', url)
    xhr.withCredentials = true
    xhr.send(form)
  })
}
```

### Chunked / Resumable Upload

For files > 100 MB or unreliable networks, use a resumable protocol:

- **Tus** — open standard, libraries for browser and Node.
- **Provider-native**: S3 multipart upload (presigned URLs per chunk), Uppy companion.

Pattern: presign on the server, upload chunks directly to storage, finalize via your API.

## WebSocket

See `context/capabilities/realtime-features.md` for the full pattern. Quick reference:

```ts
function startWs() {
  const ws = new WebSocket(`wss://${location.host}/ws`)
  let pingTimer: number
  let attempt = 0

  ws.onopen = () => {
    attempt = 0
    pingTimer = window.setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'ping' }))
    }, 25_000)
  }

  ws.onmessage = (e) => { /* handle */ }

  ws.onclose = () => {
    clearInterval(pingTimer)
    const delay = Math.min(30_000, 1000 * 2 ** attempt) * (0.5 + Math.random())
    attempt++
    setTimeout(startWs, delay)
  }

  return ws
}
```

- **Heartbeat every 25s** — proxies close idle connections.
- **Reconnect with exponential backoff + jitter.**
- **Authenticate on the upgrade**, not in the first message.

## Network Detection

```ts
function useOnline() {
  const [online, setOnline] = useState(navigator.onLine)
  useEffect(() => {
    const on = () => setOnline(true)
    const off = () => setOnline(false)
    window.addEventListener('online', on)
    window.addEventListener('offline', off)
    return () => {
      window.removeEventListener('online', on)
      window.removeEventListener('offline', off)
    }
  }, [])
  return online
}
```

`navigator.onLine` is a hint, not a guarantee. It tells you the OS thinks the network is up — which doesn't mean your API is reachable. Use it for UX (show a banner) but verify with real requests for critical flows.

### Offline Queue

For mutations attempted while offline:

```ts
type Pending = { id: string; method: string; path: string; body: unknown }

const queue: Pending[] = JSON.parse(localStorage.getItem('pending') ?? '[]')

async function enqueue(p: Pending) {
  queue.push(p)
  localStorage.setItem('pending', JSON.stringify(queue))
}

async function flushQueue() {
  while (queue.length) {
    const next = queue[0]
    try {
      await api(next.path, { method: next.method, body: JSON.stringify(next.body) })
      queue.shift()
      localStorage.setItem('pending', JSON.stringify(queue))
    } catch (e) {
      if (!isRetryable(e)) {
        queue.shift()                 // drop unrecoverable
        localStorage.setItem('pending', JSON.stringify(queue))
        continue
      }
      break                            // stop; will retry later
    }
  }
}

window.addEventListener('online', flushQueue)
```

For real offline-first, use IndexedDB instead of localStorage, and idempotency keys so retries don't duplicate.

## Common Mistakes

- **Fetch without timeout.** Hangs forever on flaky networks. Always `AbortController` + timer.
- **Retrying 4xx errors.** Won't change on retry. Filter retries to 5xx + 429 + network.
- **Retrying non-idempotent mutations.** Double-charges, duplicate writes. Use idempotency keys.
- **No jitter on retry backoff.** All clients reconnect at the same instant — herd takes the API down.
- **Fetch in `useEffect`.** No cancellation, no caching, no retries, no dedupe. Use TanStack Query.
- **Component-level `apiClient` configs.** Auth and base URL drift. One central client.
- **Setting `Content-Type: multipart/form-data` manually.** Missing boundary, server rejects.
- **`useQuery` with a function as the queryKey.** Re-creates the key every render, refetches forever. Use stable arrays.
- **No `staleTime`.** Default is 0 — refetches on every mount. Set sane defaults.
- **Invalidating `[]`.** Wipes the entire cache. Be specific.
- **Optimistic update without `cancelQueries`.** In-flight refetch lands on top, undoing the optimistic state.
- **Offset pagination on growing data.** Page contents shift under the user.
- **Trusting `navigator.onLine` absolutely.** It only reflects OS state, not your backend's reachability.
- **WebSocket without heartbeats.** Proxies kill idle connections silently.
- **Hand-rolled WebSocket auth via "first message JWT."** Authenticate on upgrade.
- **Reading response body twice.** `await res.json()` consumes the stream. Use `.clone()` or branch before reading.
- **`Promise.all` of dependent requests.** Slows things. Parallelize only independent calls; chain dependent ones.
