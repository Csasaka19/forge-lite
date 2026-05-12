# Tables & Data Grids

How to build sortable, filterable, paginated, sometimes-virtualized tables. Read before building any list view with more than a handful of columns.

## Library Choice

- **TanStack Table v8** — headless. You bring the markup; it handles sorting/filtering/pagination/grouping. Default choice.
- **AG Grid** — full-featured, polished. Free Community tier + paid Enterprise. For complex enterprise grids.
- **Material React Table** / **Mantine React Table** — TanStack Table + opinionated UI.
- **`@tanstack/react-virtual`** — pair with TanStack Table for virtualized rendering past ~200 rows.

Default: **TanStack Table** for control + customization. **AG Grid** only when you need its commercial features (Excel export with formatting, pivot, complex row grouping).

## TanStack Table v8

```bash
npm install @tanstack/react-table
```

### Basic Table

```tsx
import {
  useReactTable, getCoreRowModel, getSortedRowModel, flexRender,
  type ColumnDef, type SortingState,
} from '@tanstack/react-table'

const columns: ColumnDef<Order>[] = [
  { accessorKey: 'id', header: 'ID' },
  { accessorKey: 'customer', header: 'Customer' },
  {
    accessorKey: 'total',
    header: 'Total',
    cell: ({ getValue }) => formatPrice(getValue<number>()),
  },
  { accessorKey: 'status', header: 'Status' },
]

function OrdersTable({ data }: { data: Order[] }) {
  const [sorting, setSorting] = useState<SortingState>([])
  const table = useReactTable({
    data,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
  })

  return (
    <table className="w-full">
      <thead>
        {table.getHeaderGroups().map((g) => (
          <tr key={g.id}>
            {g.headers.map((h) => (
              <th
                key={h.id}
                onClick={h.column.getToggleSortingHandler()}
                className="cursor-pointer text-left"
              >
                {flexRender(h.column.columnDef.header, h.getContext())}
                {{ asc: ' ↑', desc: ' ↓' }[h.column.getIsSorted() as string] ?? ''}
              </th>
            ))}
          </tr>
        ))}
      </thead>
      <tbody>
        {table.getRowModel().rows.map((row) => (
          <tr key={row.id}>
            {row.getVisibleCells().map((cell) => (
              <td key={cell.id}>{flexRender(cell.column.columnDef.cell, cell.getContext())}</td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  )
}
```

## Server-Side vs Client-Side Data

| Data size | Approach |
|---|---|
| < 1,000 rows, all loaded | **Client-side**: sort/filter/paginate in memory |
| 1,000 – 100,000 rows, server can paginate | **Server-side**: send page+sort+filter to API |
| > 100,000 rows | **Server-side + virtualization** for the rendered window |

For server-side, plug TanStack Table into the request lifecycle:

```ts
const table = useReactTable({
  data,
  columns,
  pageCount,
  state: { pagination, sorting, columnFilters },
  manualPagination: true,
  manualSorting: true,
  manualFiltering: true,
  onPaginationChange: setPagination,
  onSortingChange: setSorting,
  onColumnFiltersChange: setColumnFilters,
  getCoreRowModel: getCoreRowModel(),
})
```

URL-state pagination/sort/filter so refresh + share works:

```ts
const [params, setParams] = useSearchParams()
const sort = parseSort(params.get('sort'))
const page = Number(params.get('page') ?? 0)
```

## Sorting

Multi-column sorting is rarely needed; default to single-column.

- Click header → toggle asc → desc → unsorted.
- Show a visible indicator.
- For numeric columns, ensure values are numbers (not strings) — `accessorFn` to coerce.
- Server-side: pass `sort` to the API as `field:asc` or `field:desc`.

## Filtering

### Column Filters

```tsx
{ accessorKey: 'status', header: 'Status', filterFn: 'equals' }

// UI per-column
<select onChange={(e) => column.setFilterValue(e.target.value || undefined)}>
  <option value="">All</option>
  <option value="online">Online</option>
  ...
</select>
```

### Global Filter

```tsx
const [globalFilter, setGlobalFilter] = useState('')
useReactTable({
  ...,
  state: { globalFilter },
  onGlobalFilterChange: setGlobalFilter,
  getFilteredRowModel: getFilteredRowModel(),
})

<input value={globalFilter} onChange={(e) => setGlobalFilter(e.target.value)} placeholder="Search" />
```

For server-side, debounce input and put the filter value in URL state.

## Pagination

### Server-Side (Default for Real Data)

```ts
manualPagination: true,
pageCount,                          // from API response
state: { pagination: { pageIndex, pageSize } },
```

Fetch with `?page=N&limit=M` (or cursor — see `context/system/http-networking.md`).

### Client-Side (Small Datasets)

```ts
getPaginationRowModel: getPaginationRowModel(),
initialState: { pagination: { pageSize: 50 } },
```

### Controls

- **Page size selector**: 10, 25, 50, 100 — let users pick.
- **Page navigation**: First / Prev / Page N of M / Next / Last.
- **Total count** somewhere visible: "Showing 50 of 4,231."

## Column Resizing

```ts
useReactTable({
  ...,
  enableColumnResizing: true,
  columnResizeMode: 'onChange',
})
```

```tsx
<th style={{ width: header.getSize() }}>
  {flexRender(...)}
  <div onMouseDown={header.getResizeHandler()} className="cursor-col-resize" />
</th>
```

Persist widths to localStorage so users don't re-resize every visit.

## Row Selection

```ts
const [rowSelection, setRowSelection] = useState({})

useReactTable({
  ...,
  state: { rowSelection },
  onRowSelectionChange: setRowSelection,
  enableRowSelection: true,
})
```

```tsx
{
  id: 'select',
  header: ({ table }) => (
    <input
      type="checkbox"
      checked={table.getIsAllRowsSelected()}
      onChange={table.getToggleAllRowsSelectedHandler()}
    />
  ),
  cell: ({ row }) => (
    <input
      type="checkbox"
      checked={row.getIsSelected()}
      onChange={row.getToggleSelectedHandler()}
    />
  ),
}
```

### Bulk Actions Toolbar

When 1+ rows selected, show a toolbar:

```tsx
{selectedCount > 0 && (
  <div className="sticky top-0 bg-background border-b px-4 py-2 flex justify-between">
    <span>{selectedCount} selected</span>
    <div className="flex gap-2">
      <button onClick={bulkArchive}>Archive</button>
      <button onClick={bulkDelete} className="text-destructive">Delete</button>
    </div>
  </div>
)}
```

Confirm destructive actions: "Delete 23 orders? This can't be undone."

For server-side selection across pages, store IDs explicitly. The table only knows about loaded rows; "select all" should ask: this page (default) or every match (explicit click).

## Virtual Scrolling for Large Datasets

For 10,000+ rows, render only visible rows.

```bash
npm install @tanstack/react-virtual
```

```tsx
import { useVirtualizer } from '@tanstack/react-virtual'

const parentRef = useRef<HTMLDivElement>(null)
const rows = table.getRowModel().rows
const rowVirtualizer = useVirtualizer({
  count: rows.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 40,
  overscan: 8,
})

return (
  <div ref={parentRef} className="h-[600px] overflow-auto">
    <table>
      <thead>{/* sticky header */}</thead>
      <tbody style={{ height: rowVirtualizer.getTotalSize(), position: 'relative' }}>
        {rowVirtualizer.getVirtualItems().map((vItem) => {
          const row = rows[vItem.index]
          return (
            <tr
              key={row.id}
              style={{
                position: 'absolute',
                top: 0,
                transform: `translateY(${vItem.start}px)`,
                width: '100%',
              }}
            >
              {row.getVisibleCells().map((c) => (
                <td key={c.id}>{flexRender(c.column.columnDef.cell, c.getContext())}</td>
              ))}
            </tr>
          )
        })}
      </tbody>
    </table>
  </div>
)
```

### Rules

- **Fixed row height** preferred for `estimateSize`. Variable heights work but cost more.
- **Sticky header** in CSS — virtualization doesn't touch it.
- **Reasonable `overscan`** (4–10 rows). More wastes; less causes blank frames during fast scroll.

## Column Visibility

Power users want to hide columns they don't care about.

```ts
const [columnVisibility, setColumnVisibility] = useState({})
useReactTable({
  ...,
  state: { columnVisibility },
  onColumnVisibilityChange: setColumnVisibility,
})
```

Persist to localStorage. Reset button somewhere.

## Empty / Loading / Error

Every table renders all three states:

- **Loading**: skeleton rows matching column structure.
- **Empty (no data)**: "No orders yet. [Create one]"
- **Empty (filtered)**: "No matches for your filters. [Clear filters]"
- **Error**: "Couldn't load orders. [Retry]"

Never a blank table.

## Mobile

Tables don't fit on phones. Two options:

- **Horizontal scroll** with a sticky first column.
- **Card layout** — collapse rows to vertical cards on small screens.

```tsx
{isMobile
  ? <OrderCardList orders={data} />
  : <OrdersTable data={data} />}
```

Don't try to squeeze a 10-column table onto a 375px viewport.

## Common Mistakes

- **Client-side sort/filter on a 100k-row dataset.** Don't load 100k rows. Server-side it.
- **No URL state for filter/sort/page.** Refresh loses everything; links don't share.
- **Re-rendering the whole table on cell change.** Memoize cell components or use TanStack's row model correctly.
- **No virtualization past 200 visible rows.** Scroll jank, slow renders.
- **Selection state lost on pagination.** Save selected IDs, not just rendered rows.
- **"Select all" that means "all on this page" without saying so.** Confusing. Distinguish page-select from global-select.
- **Sort header without a visual indicator.** Users don't know what's sorted.
- **Indeterminate select-all checkbox not used.** When some-but-not-all rows are selected, show indeterminate state.
- **Bulk delete without confirmation.** Disasters happen. Always confirm destructive bulk actions.
- **Editable cells without optimistic update and conflict handling.** Two users edit, last write wins silently.
- **No persisted column widths/visibility.** Power users hate re-configuring every visit.
- **Tables that don't degrade on mobile.** 10 columns on a 375px screen. Cards or horizontal scroll.
- **Loading spinner over empty table.** Skeleton rows feel faster.
- **No empty state.** Blank table looks broken.
- **`cell` returning a freshly-allocated component on every render.** Breaks memoization. Use stable refs or pre-defined components.
