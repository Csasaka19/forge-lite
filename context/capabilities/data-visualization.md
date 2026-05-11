# Data Visualization

How to build charts and dashboards. Read before adding a chart, KPI tile, or analytics view.

## Library Choice

- **Recharts** — default for React. SVG-based, composable, easy. Best for typical dashboards.
- **Visx** — primitives for custom charts. Use when Recharts can't express what you need.
- **Chart.js** + **react-chartjs-2** — canvas, performant for many points. Less React-friendly.
- **ECharts** — feature-rich, large bundle. Reach for it only when nothing else fits.
- **D3** — for one-off bespoke visualizations. Don't use D3 to draw a bar chart.
- **Plotly** — scientific charts, 3D. Big bundle.

Default to Recharts. Switch only if you've measured a need.

## Chart Type Selection

Choose by the question, not by what looks impressive.

| Question | Chart |
|---|---|
| How does X change over time? | **Line** (continuous), **area** (with magnitude) |
| How do categories compare? | **Bar** (horizontal for long labels, vertical for time-ordered) |
| What's the proportion of the whole? | **Stacked bar** > pie. Use pie only for 2–4 slices, never more |
| How are two variables related? | **Scatter** |
| Distribution of values? | **Histogram**, **box plot** |
| Cumulative progress? | **Area**, **gauge** for single value |
| Multiple metrics in one view? | **Combo chart** (bar + line), **dual axis** (sparingly) |

### Never

- **3D pie charts.** Distort proportions, hard to read.
- **Pie with > 5 slices.** Use a bar chart.
- **Dual y-axes without clear labels.** Reader can't tell which line maps to which axis.
- **Truncated y-axis on bar charts.** Exaggerates differences. Always start at zero unless there's a specific reason.

## Recharts Basics

```bash
npm install recharts
```

```tsx
import { ResponsiveContainer, LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid } from 'recharts'

<ResponsiveContainer width="100%" height={300}>
  <LineChart data={data}>
    <CartesianGrid strokeDasharray="3 3" className="stroke-border" />
    <XAxis dataKey="date" />
    <YAxis />
    <Tooltip />
    <Line type="monotone" dataKey="revenue" stroke="hsl(var(--primary))" strokeWidth={2} />
  </LineChart>
</ResponsiveContainer>
```

### Rules

- Always wrap in `<ResponsiveContainer>`. Without it, the chart has no size.
- Set an explicit `height` on the container or its parent.
- Use theme tokens for colors (`hsl(var(--primary))`) — charts switch with dark mode for free.
- Hide gridlines on dense small charts; show them on full-size charts.

## Responsive Charts

Charts must work on mobile. Reduce density, not just scale.

```tsx
const isMobile = useMediaQuery('(max-width: 640px)')

<BarChart data={data}>
  <XAxis
    dataKey="month"
    interval={isMobile ? 2 : 0}   // show every 3rd label on mobile
    tick={{ fontSize: 12 }}
  />
  ...
</BarChart>
```

### Techniques

- **Reduce labels** on small screens. Show every Nth tick.
- **Rotate labels** when names are long: `<XAxis angle={-45} textAnchor="end" />`.
- **Hide gridlines and minor ticks** on small charts.
- **Sparklines for KPI tiles**: a tiny line chart with no axes, just trend.
- **Vertical bars on desktop, horizontal on mobile** for long category names.

## Real-Time Chart Updates

For live dashboards (streaming metrics, presence counts):

### Buffer and Throttle

```tsx
const [data, setData] = useState<Point[]>([])

useEffect(() => {
  const ws = new WebSocket(url)
  let buffer: Point[] = []
  let timer: number

  ws.onmessage = (e) => {
    buffer.push(JSON.parse(e.data))
    if (!timer) {
      timer = window.setTimeout(() => {
        setData((d) => [...d.slice(-99), ...buffer].slice(-100))
        buffer = []
        timer = 0
      }, 250)
    }
  }

  return () => { ws.close(); clearTimeout(timer) }
}, [])
```

- **Throttle updates** to 4–10 fps. Faster gains nothing; user can't see it.
- **Bound the dataset** — keep the last N points. Otherwise memory and render cost grow forever.
- **Animation off** on streaming charts (`isAnimationActive={false}`) — animations conflict with constant updates.

### Pause Updates Off-Screen

```tsx
const isVisible = usePageVisibility()
// only update state when isVisible === true
```

Browser tabs in the background don't need to update at 10 fps.

## Dashboard Layout Patterns

### Grid

```tsx
<div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
  <KpiCard title="Revenue" value="$12,400" trend="+8%" />
  <KpiCard title="Orders" value="324" trend="+12%" />
  <KpiCard title="Users" value="1,240" trend="+3%" />
  <KpiCard title="Conv. Rate" value="3.2%" trend="-0.4%" />
</div>

<div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
  <Card className="lg:col-span-2"><Chart /></Card>
  <Card><RecentActivity /></Card>
</div>
```

### Hierarchy

1. **Top row: KPIs.** The single numbers leadership wants to know.
2. **Main row: primary chart.** Trend over time.
3. **Secondary row: supporting detail.** Breakdowns, lists, tables.

### KPI Cards

```tsx
<Card>
  <div className="text-sm text-muted-foreground">Revenue</div>
  <div className="text-3xl font-bold">$12,400</div>
  <div className="text-sm text-success">+8% vs last week</div>
  <Sparkline data={trendData} />
</Card>
```

- **One big number.** Most important.
- **Comparison** — "vs last week" gives context.
- **Sparkline** — shows direction without claiming axes.
- **Color the trend**: green up, red down (but accessible — don't rely on color alone).

### Filters

Filters apply to the whole dashboard. Place them at the top, sticky:

```tsx
<div className="sticky top-0 bg-background border-b z-10 flex gap-2 py-2">
  <DateRangePicker />
  <Select label="Region" />
  <Select label="Segment" />
</div>
```

Encode filter state in the URL (see search-filtering.md).

### Empty / Loading / Error States

Every chart and tile handles all three:

- **Loading**: skeleton, not a spinner. Roughly the shape of the eventual content.
- **Empty**: "No data for this range. Try widening the dates."
- **Error**: "Couldn't load. [Retry]."

## Tables Alongside Charts

For dense numeric data, a table is often clearer than a chart. Pair them:

- Chart for trend.
- Table below for exact numbers.
- Both filter by the same controls.

Use `@tanstack/react-table` for sortable, virtualized tables.

## Export to Image / PDF

Users frequently want to download a chart for a slide deck.

### Image

```ts
import html2canvas from 'html2canvas'

async function exportChart(ref: HTMLElement) {
  const canvas = await html2canvas(ref, { backgroundColor: '#fff', scale: 2 })
  canvas.toBlob((blob) => {
    if (blob) saveAs(blob, 'chart.png')
  })
}
```

`scale: 2` for retina-quality PNGs. White background unless dark mode is intended.

### SVG

Recharts renders SVG. You can serialize it directly:

```ts
const svg = chartRef.current!.querySelector('svg')!
const xml = new XMLSerializer().serializeToString(svg)
const blob = new Blob([xml], { type: 'image/svg+xml' })
```

SVG is preferable for vector workflows — scales infinitely, smaller files.

### PDF

For multi-chart reports, use **jsPDF** or **pdf-lib**, or render server-side with **Puppeteer / Playwright**. Server-side gives consistent results across browsers; client-side avoids server cost.

For Puppeteer-driven exports:

1. App exposes a print-friendly route (`/reports/123/print`).
2. Server hits it with headless Chrome, prints to PDF.
3. PDF returned to user.

Style with `@media print` rules to remove navigation and adjust layout.

## Accessibility

Charts are notoriously bad at accessibility. Make them less bad.

- **Provide a text alternative.** A summary near the chart: "Revenue grew 12% from January to March."
- **Labelled axes** — never an unlabeled chart.
- **Color + shape/pattern** for multiple series. Color-blind readers can't distinguish red from green.
- **Sufficient contrast** between series colors and background.
- **Data table fallback** — link "View as table" beneath every chart for screen-reader users.

## Performance

- **Don't render 10,000 points** as DOM/SVG. Aggregate first, then render. Or use Canvas (Chart.js).
- **Virtualize legends** if there are many series.
- **Memoize chart data prep** — every parent re-render shouldn't recompute the dataset.
- **Code-split chart libraries** — Recharts is ~80 KB gzipped. Lazy load the dashboard route.

## Common Mistakes

- **No `ResponsiveContainer`.** Chart renders at 0×0.
- **Pie chart with 12 slices.** Unreadable. Use a horizontal bar chart.
- **Truncated y-axis on bar charts.** Visually misleads. Start at zero.
- **Dual y-axes without clear labels.** Readers can't tell which scale applies to which line.
- **Color-only differentiation.** Color-blind users can't distinguish red vs green. Add shape or pattern.
- **Live chart re-rendering at 60 fps.** Wastes CPU. Throttle to 4–10 fps; users can't see faster.
- **Unbounded streaming dataset.** Memory and render cost grow forever. Cap to the last N points.
- **Animation on real-time charts.** Animations interfere with updates and look jittery.
- **No empty state.** "No data" without explanation looks broken.
- **Chart without a title or context.** Reader can't tell what they're looking at.
- **Skeleton-less loading state.** Spinners on dashboards feel slower than skeletons.
- **Filters in component state.** Refresh loses everything. Put filters in the URL.
- **html2canvas at default scale.** Exported chart is pixelated. Use `scale: 2`.
- **Server-side PDF rendering with browser-specific styles.** Test the exact stylesheet that Puppeteer renders.
- **Rendering 50,000 points with SVG.** Browser stalls. Aggregate or move to canvas.
- **Tables and charts with different filters.** User changes the date range; only the chart updates. Wire them together.
