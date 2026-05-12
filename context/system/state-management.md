# State Management

Where state lives, and why. Read before reaching for Redux, before adding a context, before lifting state up.

## Decision Tree: Where Does This State Belong?

Walk through the list in order. Stop at the first match.

1. **Is it server data?** → **TanStack Query** (`useQuery` / `useMutation`).
2. **Is it filter/sort/pagination/tab state that should be shareable or survive refresh?** → **URL** (`useSearchParams`).
3. **Is it form input being edited?** → **`react-hook-form`** (or local `useState` for trivial cases).
4. **Does it belong to one component and its children?** → **`useState`** + props.
5. **Is it persistent user preference (theme, language)?** → **localStorage** behind a small hook.
6. **Is it global client state needed across unrelated trees (auth user, cart, UI flags)?** → **Zustand**.
7. **Is it slowly-changing config consumed in many places?** → **Context** (theme, i18n, auth context).

If you find yourself reaching for Redux, ask which of the above you're actually trying to solve. The answer is rarely Redux.

## Server State: TanStack Query

Most of what people call "state management" is **server state** — cached, stale-able, async. Don't store server data in component state, Redux, or Zustand. Use TanStack Query.

```ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'

function MachineList() {
  const { data, isLoading, error } = useQuery({
    queryKey: ['machines'],
    queryFn: getMachines,
    staleTime: 30_000,
  })

  if (isLoading) return <Spinner />
  if (error) return <ErrorMessage error={error} />
  return data.map((m) => <MachineCard key={m.id} machine={m} />)
}
```

### Mutations with Optimistic Update

```ts
const qc = useQueryClient()

const favorite = useMutation({
  mutationFn: (id: string) => api(`/machines/${id}/favorite`, { method: 'POST' }),
  onMutate: async (id) => {
    await qc.cancelQueries({ queryKey: ['machines'] })
    const prev = qc.getQueryData<Machine[]>(['machines'])
    qc.setQueryData<Machine[]>(['machines'], (old) =>
      old?.map((m) => (m.id === id ? { ...m, favorited: !m.favorited } : m)) ?? old,
    )
    return { prev }
  },
  onError: (_e, _id, ctx) => ctx?.prev && qc.setQueryData(['machines'], ctx.prev),
  onSettled: () => qc.invalidateQueries({ queryKey: ['machines'] }),
})
```

### Rules

- **Never duplicate server data in local state.** Don't `useState` of `data` from a query.
- **Invalidate after writes**, then let the cache refetch — don't manually re-call the query.
- **Hierarchical query keys**: `['machines']`, `['machines', id]`, `['machines', id, 'orders']`. Parent invalidation cascades.
- **`staleTime` is the freshness window**, `gcTime` is how long unused data lives in memory. Tune per endpoint.

## URL State

Filters, sorts, pagination, open tab, selected item — anything a user might bookmark, share, or refresh — lives in the URL.

```tsx
import { useSearchParams } from 'react-router'

function MachineFilters() {
  const [params, setParams] = useSearchParams()
  const status = params.get('status') ?? 'all'
  const radius = Number(params.get('radius') ?? '10')

  const update = (k: string, v: string) => {
    setParams((p) => {
      if (v && v !== defaults[k]) p.set(k, v)
      else p.delete(k)
      return p
    })
  }

  return (
    <>
      <Select value={status} onChange={(v) => update('status', v)} />
      <Select value={String(radius)} onChange={(v) => update('radius', v)} />
    </>
  )
}
```

### Rules

- **Strip defaults from the URL.** `?status=all` is noise.
- **Numeric and boolean params** — parse on read, stringify on write.
- **Multi-select** — comma-separated values, parse with `.split(',')`.
- **Refresh-safe.** Filter state survives reloads automatically.
- **Shareable.** Send the URL, get the same view.

### When NOT URL

- Ephemeral UI (modal open/closed, hover state, dropdown expanded).
- Secrets (tokens, PII).
- High-frequency state (animation values, drag positions).

## Local Component State

The default. Until proven otherwise, start with `useState`.

```tsx
function CommentBox() {
  const [text, setText] = useState('')
  const [isSubmitting, setSubmitting] = useState(false)
  // ...
}
```

### When to Lift

Lift state to the lowest common ancestor when two siblings need it. Lift it once; don't keep lifting "in case." Premature lifting is as bad as global state.

### When NOT to Use `useState`

- **For server data** — use TanStack Query.
- **For filter state shared with the URL** — use `useSearchParams`.
- **For deeply prop-drilled state** — three or more levels of prop pass-through suggests context or a store.

## Forms: react-hook-form + Zod

Uncontrolled inputs by default. Validation via Zod. Re-renders only on submit and field-level errors.

```tsx
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

const schema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
})

type FormValues = z.infer<typeof schema>

function LoginForm() {
  const { register, handleSubmit, formState: { errors, isSubmitting } } = useForm<FormValues>({
    resolver: zodResolver(schema),
  })

  const onSubmit = async (values: FormValues) => {
    await login(values)
  }

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <input {...register('email')} aria-invalid={!!errors.email} />
      {errors.email && <p role="alert">{errors.email.message}</p>}
      <input type="password" {...register('password')} />
      <button disabled={isSubmitting}>Sign in</button>
    </form>
  )
}
```

### Rules

- **Schema is the source of truth.** Derive types and validation from one Zod schema.
- **Validate on blur**, not on every keystroke. Use `mode: 'onBlur'` or default.
- **Show server errors** by mapping API error responses into `setError` calls.
- **For trivial forms** (one or two fields, no validation), `useState` is fine.

## Global Client State: Zustand

For state that's needed across unrelated trees and changes from many places. Not for server data. Not for form state. Not for URL state.

```ts
import { create } from 'zustand'
import { persist } from 'zustand/middleware'

interface CartState {
  items: CartItem[]
  add: (item: CartItem) => void
  remove: (id: string) => void
  clear: () => void
}

export const useCart = create<CartState>()(
  persist(
    (set) => ({
      items: [],
      add: (item) => set((s) => ({ items: [...s.items, item] })),
      remove: (id) => set((s) => ({ items: s.items.filter((i) => i.id !== id) })),
      clear: () => set({ items: [] }),
    }),
    { name: 'cart-storage' },
  ),
)
```

### Selectors

Subscribe only to the slice you need. Without selectors, every component re-renders on every state change.

```tsx
// Bad — re-renders on any cart change
const cart = useCart()

// Good — only re-renders when items.length changes
const itemCount = useCart((s) => s.items.length)
```

For multi-field selections, use `useShallow` to avoid spurious re-renders:

```ts
import { useShallow } from 'zustand/react/shallow'

const { items, total } = useCart(useShallow((s) => ({
  items: s.items,
  total: s.items.reduce((sum, i) => sum + i.price * i.qty, 0),
})))
```

### Devtools

```ts
import { devtools } from 'zustand/middleware'

create<CartState>()(devtools(persist(/* ... */)))
```

Hooks into Redux DevTools — time-travel debugging, action log.

### When NOT Zustand

- For server data — use TanStack Query.
- For one component's state — use `useState`.
- For state that should appear in the URL — use `useSearchParams`.

## Context

React Context is for **slowly-changing values** consumed by many components. Theme, auth user, i18n, locale. Not for state that updates frequently.

```tsx
const AuthContext = createContext<{ user: User | null; signOut: () => void } | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const value = useMemo(() => ({ user, signOut: () => setUser(null) }), [user])
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used inside AuthProvider')
  return ctx
}
```

### Rules

- **Memoize the value object.** Without `useMemo`, every render of the provider re-creates the value reference, re-rendering every consumer.
- **Split contexts.** One enormous context with everything triggers every consumer on every change. Split by concern.
- **Throw if used outside the provider.** Saves an hour of debugging when someone forgets to wrap.

### When NOT Context

Anything updating more than a few times per minute. Mouse position, scroll position, chat messages, drag state — these in a context cause re-render storms across the tree. Use Zustand selectors instead.

## Derived State: Compute, Don't Store

The most common state bug: storing a value derived from other state, then forgetting to update it.

```tsx
// Bad — fullName is derived state stored in useState
const [firstName, setFirstName] = useState('')
const [lastName, setLastName] = useState('')
const [fullName, setFullName] = useState('')   // ← bug magnet
useEffect(() => {
  setFullName(`${firstName} ${lastName}`)
}, [firstName, lastName])

// Good — compute on render
const [firstName, setFirstName] = useState('')
const [lastName, setLastName] = useState('')
const fullName = `${firstName} ${lastName}`

// Good — memoize if the computation is expensive
const sorted = useMemo(() => items.toSorted(sortBy), [items, sortBy])
```

Rules:

- **If you can compute it from other state, don't store it.**
- **`useMemo`** only when the computation is genuinely expensive or when reference equality matters for child memoization.
- **`useEffect` to derive state is almost always wrong.** Compute inline.

## Persistence

### localStorage

User preferences. Theme, language, last-used filter combo, dismissed banners.

```ts
function usePersistedState<T>(key: string, initial: T) {
  const [v, setV] = useState<T>(() => {
    try { return JSON.parse(localStorage.getItem(key) ?? '') as T } catch { return initial }
  })
  useEffect(() => { localStorage.setItem(key, JSON.stringify(v)) }, [key, v])
  return [v, setV] as const
}
```

### sessionStorage

Temporary state for the current tab. Multi-step form progress, scroll position to restore after a navigation cycle. Cleared when the tab closes.

### IndexedDB

For anything large (images, datasets, offline caches). Use **Dexie** or **idb** rather than raw IndexedDB. See `pwa-offline.md`.

### Cookies

Auth only. httpOnly, Secure, SameSite=Strict. Don't use cookies for app state — they're sent on every request and bloat the network.

### Rules

- **Never store secrets in localStorage.** XSS-stealable.
- **Bound the size.** localStorage caps at 5–10 MB and silently fails when full. Don't dump arbitrary user data into it.
- **Migrate old shapes.** When the structure changes, version the stored data and migrate on read.
- **Don't sync everything.** Only persist what's actually a user preference. Ephemeral UI doesn't need to survive a refresh.

## Putting It Together

A typical feature:

```tsx
function MachineMapPage() {
  // URL — filters, shareable
  const [params, setParams] = useSearchParams()
  const status = params.get('status') ?? 'all'

  // Server — machines list
  const { data: machines = [] } = useQuery({
    queryKey: ['machines', { status }],
    queryFn: () => getMachines({ status }),
  })

  // Derived — no useState here
  const onlineCount = machines.filter((m) => m.status === 'online').length

  // Local — UI-only
  const [selectedId, setSelectedId] = useState<string | null>(null)

  // Global — auth, available everywhere
  const { user } = useAuth()

  // Persisted preference
  const [view, setView] = usePersistedState<'map' | 'list'>('map-view', 'map')

  // ...
}
```

Each piece of state lives in exactly the right place.

## Common Mistakes

- **Server data in `useState` or Redux.** Reinvents caching, dedupe, retries. Use TanStack Query.
- **Filter state in component state.** Refresh loses it, links don't share. Use URL.
- **Everything in Redux.** Boilerplate for what `useState` and React Query already do better.
- **Everything in one giant context.** Every consumer re-renders on every change. Split contexts or use a store.
- **Context for high-frequency state.** Mouse position, scroll, drag. Use Zustand with selectors.
- **`useEffect` to keep two states in sync.** Compute one from the other instead.
- **Storing derived state.** `fullName` from `firstName` + `lastName` — compute, don't store.
- **Lifting state way up "just in case."** Lift to the lowest common ancestor that actually needs it.
- **Form values in `useState` per field.** Re-renders every keystroke across the form. Use react-hook-form.
- **Zod schema duplicated as a TS type.** Define schema, infer the type with `z.infer`.
- **localStorage for auth tokens.** XSS-stealable. Use httpOnly cookies.
- **No memoized context value.** Every parent render = every consumer re-renders.
- **Zustand without selectors.** Subscribes to the whole store. Always select.
- **Mixing TanStack Query with manual `useState({ loading, data, error })`.** Pick one. Query already gives you all three.
- **Persisting everything to localStorage on every change.** Slow, wasteful. Persist deliberately.
- **Optimistic updates without rollback.** Network fails, UI shows wrong state forever. Always `onError` restore.
