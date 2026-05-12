# PDF & Document Generation

How to generate PDFs (invoices, reports, receipts, fillable forms). Read before adding any "export to PDF" or "download document" feature.

## Decision Tree

| Need | Pick |
|---|---|
| Component-based PDFs, full programmatic control | **@react-pdf/renderer** |
| HTML/CSS rendering pixel-accurate to a web page | **Puppeteer** or **Playwright** |
| Templated invoices/receipts with consistent layout | **react-pdf** or **PDFKit** |
| Fillable forms (PDF AcroForms) | **pdf-lib** |
| Merging / splitting / extracting pages | **pdf-lib** |
| Server-side at scale | **Puppeteer cluster** or hosted (DocRaptor, Gotenberg) |
| Client-side download of a chart/dashboard | **html2canvas + jsPDF** |

Run heavy generation in a **background job**. PDFs take 0.5–5s; that's too long for a request handler.

## react-pdf (Component-Based)

```bash
npm install @react-pdf/renderer
```

Best for templates you want to compose with React thinking.

```tsx
import { Document, Page, Text, View, StyleSheet, pdf } from '@react-pdf/renderer'

const styles = StyleSheet.create({
  page: { padding: 40, fontSize: 11, fontFamily: 'Helvetica' },
  header: { fontSize: 18, marginBottom: 16 },
  row: { flexDirection: 'row', borderBottomWidth: 1, borderColor: '#eee', paddingVertical: 6 },
  cellName: { flex: 2 },
  cellQty: { flex: 1, textAlign: 'right' },
  cellTotal: { flex: 1, textAlign: 'right' },
})

function Invoice({ order }: { order: Order }) {
  return (
    <Document>
      <Page size="A4" style={styles.page}>
        <Text style={styles.header}>Invoice #{order.id}</Text>
        <Text>Bill to: {order.customerName}</Text>
        <View style={{ marginTop: 24 }}>
          {order.items.map((item) => (
            <View key={item.id} style={styles.row}>
              <Text style={styles.cellName}>{item.name}</Text>
              <Text style={styles.cellQty}>{item.qty}</Text>
              <Text style={styles.cellTotal}>{formatPrice(item.total)}</Text>
            </View>
          ))}
        </View>
        <Text style={{ marginTop: 24, textAlign: 'right' }}>
          Total: {formatPrice(order.total)}
        </Text>
      </Page>
    </Document>
  )
}

// Server-side render to buffer
const buffer = await pdf(<Invoice order={order} />).toBuffer()
```

### Rules

- **`StyleSheet.create` only.** Inline style props work but you lose validation.
- **Flexbox layout only.** No grid, no absolute positioning (mostly). Layout in flex.
- **Register custom fonts** with `Font.register({ family, src })` before the first render.
- **Avoid large images inline.** Pre-resize before embedding.
- **No external resources fetched at render time.** Inline assets or fetch ahead.

## Puppeteer (HTML → PDF)

```bash
npm install puppeteer
```

Best for "pixel-accurate to this web page." Reuses your existing HTML/CSS.

```ts
import puppeteer from 'puppeteer'

async function htmlToPdf(html: string): Promise<Buffer> {
  const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox'] })
  try {
    const page = await browser.newPage()
    await page.setContent(html, { waitUntil: 'networkidle0' })
    return await page.pdf({
      format: 'A4',
      printBackground: true,
      margin: { top: '20mm', bottom: '20mm', left: '15mm', right: '15mm' },
    })
  } finally {
    await browser.close()
  }
}
```

### Use a Print-Friendly Route

Don't render the whole app to PDF — make a dedicated `/print/invoice/:id` route with print-specific styles:

```css
@media print {
  nav, footer, .no-print { display: none; }
  body { color: #000; background: #fff; }
}
@page {
  size: A4;
  margin: 20mm;
}
```

Puppeteer hits the route as a logged-in user, prints to PDF.

### Reuse the Browser

Launching Puppeteer per request is slow (1–2s). Reuse:

```ts
let browser: puppeteer.Browser | null = null

async function getBrowser() {
  if (!browser || !browser.isConnected()) {
    browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox'] })
  }
  return browser
}
```

For high throughput, use **puppeteer-cluster** to run a pool of browsers.

### Serverless

Vanilla Puppeteer doesn't fit serverless (large binary). Options:

- **`@sparticuz/chromium`** + **puppeteer-core** for Lambda/Vercel.
- **Browserless.io / DocRaptor / Gotenberg** — hosted PDF services. Trade infra work for a per-render fee.

## pdf-lib (Edit, Merge, Fill)

```bash
npm install pdf-lib
```

For manipulating existing PDFs, filling AcroForm fields, merging pages.

### Fill a Form

```ts
import { PDFDocument } from 'pdf-lib'
import fs from 'node:fs/promises'

const templateBytes = await fs.readFile('templates/contract.pdf')
const doc = await PDFDocument.load(templateBytes)
const form = doc.getForm()

form.getTextField('full_name').setText(user.name)
form.getTextField('date').setText(formatDate(new Date()))
form.getCheckBox('agreed').check()
form.flatten()    // make fields non-editable in the output

const out = await doc.save()
```

### Merge

```ts
const merged = await PDFDocument.create()
for (const file of files) {
  const src = await PDFDocument.load(file)
  const pages = await merged.copyPages(src, src.getPageIndices())
  pages.forEach((p) => merged.addPage(p))
}
const out = await merged.save()
```

### Split / Extract

```ts
const src = await PDFDocument.load(bytes)
const chunk = await PDFDocument.create()
const [page] = await chunk.copyPages(src, [0, 1, 2])
chunk.addPage(page)
const out = await chunk.save()
```

## Templates: Invoice and Report Patterns

### Invoice Skeleton

- **Header**: logo, invoice number, issue date, due date.
- **From / To**: your details, customer details.
- **Line items table**: description, qty, unit price, total.
- **Totals**: subtotal, tax, total.
- **Footer**: payment instructions, contact, terms.

Store template metadata (logo, address, tax IDs) in env or settings — never hard-code.

### Report Skeleton

- **Cover page**: title, date range, generated-by.
- **Summary**: key metrics, charts.
- **Detail tables**: paginated, page breaks after natural section boundaries.
- **Appendix**: methodology, definitions.

For charts in PDF: render them server-side with **node-canvas** or render in Puppeteer and let CSS handle it.

## Page Numbering and Headers/Footers

### react-pdf

```tsx
<Page>
  <Text
    style={{ position: 'absolute', bottom: 20, right: 40 }}
    render={({ pageNumber, totalPages }) => `${pageNumber} / ${totalPages}`}
    fixed
  />
</Page>
```

`fixed` repeats on every page.

### Puppeteer

```ts
await page.pdf({
  displayHeaderFooter: true,
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:right;padding-right:15mm">Invoice #' + orderId + '</div>',
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:right;padding-right:15mm"><span class="pageNumber"></span> / <span class="totalPages"></span></div>',
})
```

The header/footer templates are real HTML with special classes (`pageNumber`, `totalPages`, `date`, `title`, `url`).

## Performance and Serving

- **Generate in a background job**, not in the request handler.
- **Cache** generated PDFs in object storage with a content-hashed key.
- **Serve via signed URLs** — never embed PDF bytes in API responses.
- **For user downloads**: redirect to the signed URL with `Content-Disposition: attachment; filename="invoice-123.pdf"`.

```ts
async function generateAndStore(order: Order) {
  const pdf = await pdf(<Invoice order={order} />).toBuffer()
  const key = `invoices/${order.id}.pdf`
  await s3.send(new PutObjectCommand({
    Bucket: env.BUCKET,
    Key: key,
    Body: pdf,
    ContentType: 'application/pdf',
    ContentDisposition: `attachment; filename="invoice-${order.id}.pdf"`,
  }))
  return key
}
```

## Common Mistakes

- **Generating PDFs in the request handler.** 3-second checkout response. Queue it.
- **Launching Puppeteer per request.** Adds 1–2s per call. Reuse the browser.
- **Puppeteer without `--no-sandbox` in Docker.** Crashes. Add the flag (and run as non-root user).
- **No print stylesheet.** Web nav and ads end up in the PDF. Use `@media print`.
- **External images that 404.** Puppeteer renders blank space. Inline as base64 or pre-fetch.
- **Fonts that fail to load.** Falls back to a system font, layout shifts. Register and inline fonts.
- **Float-based or grid layouts in react-pdf.** Unsupported. Use flex.
- **Hard-coded paths to template PDFs.** Doesn't survive deploys. Bundle as assets or fetch from storage.
- **AcroForm filled but not flattened.** Users edit your filled fields in their reader. Always `form.flatten()` for finals.
- **No page breaks on long tables.** Rows split across pages awkwardly. Use `page-break-inside: avoid` or react-pdf's `wrap={false}`.
- **Returning the PDF bytes from an API endpoint.** Slow, memory-heavy, no caching. Store in S3, return a signed URL.
- **Same filename for every download.** Browser deduplicates. Include the entity ID and a timestamp.
- **Locale-naive number/date formatting.** "1,000.50" looks wrong to European customers. Use `Intl`.
- **Serverless Puppeteer with default Chromium binary.** Lambda zip is too big. Use `@sparticuz/chromium`.
- **No fallback when generation fails.** User sees a broken download. Catch and present a clear error.
