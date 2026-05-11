# Search & Filtering

How to build search and filter UIs. Read before adding a search box or filter panel.

## Choose the Right Approach

Match the implementation to the dataset.

| Dataset size | Approach |
|---|---|
| < 1,000 items, all loaded | **Client-side filter** in memory |
| 1,000 – 100,000 items | **Server-side query** with SQL `ILIKE` or trigram |
| > 100,000 items, complex queries | **Full-text search** (Postgres FTS, Meilisearch, Typesense, Elasticsearch) |
| Cross-entity, fuzzy, ranked | **Dedicated search engine** (Meilisearch, Typesense, Algolia) |

Don't reach for Elasticsearch on day one. Most apps live their whole life on Postgres FTS.

## Client-Side Filtering (Small Datasets)

When the full dataset is already in memory (under ~1000 items, lightweight rows), filter in JS.

```tsx
const filtered = useMemo(
  () => items.filter((it) =>
    it.name.toLowerCase().includes(query.toLowerCase()) &&
    (status === 'all' || it.status === status),
  ),
  [items, query, status],
)
```

Wrap in `useMemo` so re-renders don't recompute. For 5,000+ items, consider `useDeferredValue` to keep the input responsive:

```tsx
const deferredQuery = useDeferredValue(query)
const filtered = useMemo(() => filter(items, deferredQuery), [items, deferredQuery])
```

### Fuzzy Match Client-Side

For typo tolerance, use Fuse.js:

```ts
import Fuse from 'fuse.js'
const fuse = new Fuse(items, { keys: ['name', 'description'], threshold: 0.3 })
const results = fuse.search(query).map((r) => r.item)
```

Don't load Fuse for datasets larger than ~5,000 items — server-side search is better for everything beyond that.

## Server-Side Search (Postgres)

### Simple ILIKE

For modest datasets and short queries:

```ts
const results = await prisma.product.findMany({
  where: { name: { contains: query, mode: 'insensitive' } },
  take: 50,
})
```

`ILIKE` works but doesn't use a regular index for `%foo%` patterns. Add a **trigram index** for fast contains-search:

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_products_name_trgm ON products USING gin (name gin_trgm_ops);
```

Now `WHERE name ILIKE '%foo%'` uses the index.

### Full-Text Search

For phrases, ranking, and language-aware tokenization:

```sql
ALTER TABLE products ADD COLUMN search_vector tsvector
  GENERATED ALWAYS AS (
    setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(description, '')), 'B')
  ) STORED;

CREATE INDEX idx_products_search ON products USING gin (search_vector);
```

Query:

```ts
const results = await prisma.$queryRaw<Product[]>`
  SELECT *, ts_rank(search_vector, plainto_tsquery('english', ${query})) AS rank
  FROM products
  WHERE search_vector @@ plainto_tsquery('english', ${query})
  ORDER BY rank DESC
  LIMIT 50
`
```

- `plainto_tsquery` handles raw user input safely.
- Weights (`A`, `B`, `C`, `D`) let you rank title-matches above description-matches.
- The generated column keeps the index synced with the data.

### When to Reach for a Search Engine

Move beyond Postgres FTS when you need:

- **Typo tolerance** (Meilisearch, Typesense, Algolia all do this; Postgres FTS doesn't natively).
- **Multi-language fuzzy match.**
- **Faceted aggregations** at scale (counts per facet, fast).
- **Cross-index search** ("find anything matching X across products, articles, users").

**Meilisearch** is the simplest for most teams — self-host, JSON in, JSON out, typo-tolerant by default. **Typesense** is similar. **Algolia** is hosted, premium pricing. **Elasticsearch** is powerful and operational overhead — reach for it only when smaller options can't keep up.

## Faceted Filtering

Filters that combine: category, status, price range, tags. Each shows a count of remaining items.

### URL State

**Filter state lives in the URL.** Shareable, back-button friendly, refresh-safe.

```tsx
import { useSearchParams } from 'react-router'

function MachineFilters() {
  const [params, setParams] = useSearchParams()
  const status = params.get('status') ?? 'all'
  const radius = Number(params.get('radius') ?? '10')

  return (
    <select
      value={status}
      onChange={(e) => setParams((p) => { p.set('status', e.target.value); return p })}
    >
      ...
    </select>
  )
}
```

Rules:

- Default values are not encoded — keep URLs clean (`?status=online` only when non-default).
- Multi-select uses comma-separated values: `?categories=a,b,c`.
- Numeric ranges: `?price_min=10&price_max=100`.

### UI

- **Sidebar filters** for desktop dashboards.
- **Bottom sheet / modal filters** for mobile.
- **Pills** at the top showing active filters with `×` to remove.
- **Counts per option** when feasible — "Online (12), Maintenance (3), Offline (1)."

### Counts Need a Two-Pass Query

Naive: filter the dataset, count what's left. But counts shown per facet need the dataset filtered by **all other** facets, not by the facet itself.

Search engines (Meilisearch, Algolia) handle this in one query. With Postgres, you write one count per facet or use `GROUPING SETS`.

## Debounced Search Input

Don't fire a query on every keystroke. Debounce by 200–300ms.

```tsx
import { useDeferredValue, useEffect, useState } from 'react'

function SearchBox() {
  const [input, setInput] = useState('')
  const deferred = useDeferredValue(input)

  useEffect(() => {
    if (!deferred) return
    const ctrl = new AbortController()
    fetch(`/api/search?q=${encodeURIComponent(deferred)}`, { signal: ctrl.signal })
      .then((r) => r.json())
      .then(setResults)
      .catch(() => {})
    return () => ctrl.abort()
  }, [deferred])

  return <input value={input} onChange={(e) => setInput(e.target.value)} />
}
```

### Rules

- **Cancel stale requests** via `AbortController`. Without it, a slow request returning after a fast one overwrites correct results.
- **Show a loading state** when a request is in flight. Otherwise the UI looks broken on slow networks.
- **Clear results on empty input** — don't leave stale data.
- **Debounce, but not too long.** 200–300ms feels live; 500ms feels sluggish.

With React Query:

```ts
const { data } = useQuery({
  queryKey: ['search', deferred],
  queryFn: ({ signal }) => fetch(`/api/search?q=${deferred}`, { signal }).then((r) => r.json()),
  enabled: deferred.length > 0,
})
```

React Query handles cancellation and caching automatically.

## Search Results Layout

### Components

- **Results count** at the top: "127 machines."
- **Sort selector**: relevance, newest, price.
- **Empty state**: "No machines match your filters. [Clear filters]."
- **Loading state**: skeleton rows, not a spinner.
- **Error state**: "Couldn't load results. [Retry]."
- **Pagination or infinite scroll**: cursor-based for large sets.

### Highlighting

Highlight matched terms in results. Most search engines return offsets; render with `<mark>`:

```tsx
function highlight(text: string, query: string) {
  if (!query) return text
  const parts = text.split(new RegExp(`(${escapeRegex(query)})`, 'gi'))
  return parts.map((p, i) =>
    p.toLowerCase() === query.toLowerCase() ? <mark key={i}>{p}</mark> : p,
  )
}
```

For full-text search, use `ts_headline()` server-side — it knows tokenization.

### Keyboard Navigation

Search inputs benefit from keyboard nav:

- **Up/Down arrows** highlight result.
- **Enter** selects highlighted.
- **Escape** closes.
- Combine with `cmdk` library for a polished command-palette feel.

## Saved Searches and Recent Queries

For power-user dashboards, let users save filter combinations:

```prisma
model SavedSearch {
  id     String @id @default(uuid())
  userId String @map("user_id")
  name   String
  url    String        // e.g. "?status=online&radius=50"
  createdAt DateTime @default(now())
}
```

Store recent queries in `localStorage` for the current user:

```ts
const recent = JSON.parse(localStorage.getItem('recent-searches') ?? '[]')
```

Cap at 10. Dedupe. Don't store empty queries.

## Common Mistakes

- **Loading the entire database into the client for "fast search."** Works at 100 rows, dies at 10,000.
- **Querying the DB on every keystroke.** Debounce or use deferred values.
- **Not cancelling stale requests.** Slow request comes back after the fast one and overwrites correct results.
- **`ILIKE '%query%'` without a trigram index.** Sequential scan on every search.
- **Filter state in component state, not URL.** Refresh loses filters, links don't share, back button does the wrong thing.
- **`?status=all` in every URL.** Strip defaults from the URL.
- **Storing arrays as `?tag=a&tag=b&tag=c`.** Some parsers handle it; CSV is more portable.
- **Counts based on filtered dataset, not per-facet logic.** Counts go wrong as soon as the user picks one filter.
- **Spinner on every keystroke.** UI feels flickery. Use skeleton-and-stale-data, or only show loading after 200ms.
- **No empty state.** "0 results" with a blank screen leaves users wondering if it's broken.
- **No keyboard nav on search results.** Power users feel the friction.
- **Search index out of sync with data.** Indexer falls behind on writes. Add a queue and monitor lag.
- **Trying to do typo-tolerant FTS in Postgres.** It can, but it's awkward. Reach for Meilisearch when typos matter.
- **Returning 10,000 results when the user typed `a`.** Cap server-side. Force the query to be specific.
- **No pagination/infinite scroll on long results.** Browsers choke. Cursor-paginate.
