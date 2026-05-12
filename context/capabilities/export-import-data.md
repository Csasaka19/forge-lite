# Export & Import Data

How to move data in and out of the app. Read before adding any "Export to CSV," "Download report," or "Bulk import" feature.

## Decision Tree

| Need | Pick |
|---|---|
| User-facing export, simple tabular data | **CSV** via PapaParse |
| User-facing export, formulas/multi-sheet/styling | **Excel (.xlsx)** via ExcelJS or SheetJS |
| Machine-to-machine, web client | **JSON** |
| Bulk import from spreadsheet | **PapaParse** (CSV) or **ExcelJS** (XLSX), validated row-by-row |
| Very large export (> 100k rows) | **Streaming CSV** via Node streams |
| Compliance / data portability | **JSON** + a documented schema |

Don't generate exports synchronously in a request handler if they're more than a few seconds of work — queue, store, link.

## CSV: PapaParse

```bash
npm install papaparse
npm install -D @types/papaparse
```

### Generate (Client)

```ts
import Papa from 'papaparse'

function exportOrders(orders: Order[]) {
  const csv = Papa.unparse(orders.map((o) => ({
    id: o.id,
    customer: o.customerName,
    total: (o.totalCents / 100).toFixed(2),
    status: o.status,
    createdAt: o.createdAt.toISOString(),
  })))

  const blob = new Blob(['﻿', csv], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `orders-${Date.now()}.csv`
  a.click()
  URL.revokeObjectURL(url)
}
```

The `﻿` is a BOM — makes Excel open UTF-8 CSVs without character mangling.

### Parse (Import)

```ts
Papa.parse(file, {
  header: true,
  skipEmptyLines: true,
  dynamicTyping: false,    // strings; we'll coerce explicitly
  complete: (result) => {
    const errors = result.errors
    const rows = result.data as Record<string, string>[]
    processRows(rows, errors)
  },
})
```

### Rules

- **Always include the BOM** when generating CSV for non-developer users — Excel mangles UTF-8 without it.
- **Quote fields containing commas, quotes, or newlines** — PapaParse handles this automatically.
- **`header: true`** for object mode — column names become keys.
- **Don't trust `dynamicTyping`.** Parse strings, coerce explicitly with Zod.

## Excel: ExcelJS

```bash
npm install exceljs
```

When you need: multi-sheet workbooks, formulas, cell styling, frozen rows, column widths, conditional formatting.

```ts
import ExcelJS from 'exceljs'

async function generateReport(orders: Order[]): Promise<Buffer> {
  const wb = new ExcelJS.Workbook()
  wb.creator = 'Water Vending'
  wb.created = new Date()

  const sheet = wb.addWorksheet('Orders', {
    views: [{ state: 'frozen', ySplit: 1 }],
  })

  sheet.columns = [
    { header: 'ID', key: 'id', width: 20 },
    { header: 'Customer', key: 'customer', width: 24 },
    { header: 'Total (KES)', key: 'total', width: 14, style: { numFmt: '#,##0.00' } },
    { header: 'Status', key: 'status', width: 14 },
    { header: 'Created', key: 'createdAt', width: 18, style: { numFmt: 'yyyy-mm-dd hh:mm' } },
  ]

  sheet.getRow(1).font = { bold: true }
  sheet.getRow(1).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFEEEEEE' } }

  orders.forEach((o) => {
    sheet.addRow({
      id: o.id,
      customer: o.customerName,
      total: o.totalCents / 100,
      status: o.status,
      createdAt: o.createdAt,
    })
  })

  return Buffer.from(await wb.xlsx.writeBuffer())
}
```

### SheetJS Alternative

SheetJS (`xlsx`) is the older library — more features (older formats, complex parsing), worse DX. Use ExcelJS by default.

### Rules

- **Set column widths.** Default Excel columns are too narrow.
- **Freeze the header row.** `ySplit: 1`.
- **Use number formats**, not strings. `100.00` as a number with `#,##0.00`; Excel sorts and sums correctly.
- **ISO date strings vs Date objects**: pass `Date` to ExcelJS and set a format; that's what Excel expects.

## JSON Export

Trivial but worth noting:

```ts
function exportJson(data: unknown, filename: string) {
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  // ... same download dance
}
```

Pretty-print with `JSON.stringify(data, null, 2)` for human-readable exports. Use compact form for machine-to-machine.

For compliance/GDPR data portability, JSON is the right answer — preserves nested structure and types.

## Bulk Import

The hardest direction. Users upload spreadsheets with typos, wrong columns, mixed formats, and impossible values.

### Pattern: Parse → Validate → Stage → Confirm → Apply

1. **Parse** the file (CSV/XLSX) into an array of objects.
2. **Validate** each row with Zod. Collect errors with row numbers.
3. **Stage** valid rows in a temporary table or in-memory.
4. **Show preview** to the user: row count, errors, sample rows.
5. **User confirms.** Apply in a transaction.
6. **Report results.** Success count, failure count, downloadable error report.

### Validation with Zod

```ts
import { z } from 'zod'

const ImportRow = z.object({
  email: z.string().email(),
  name: z.string().min(1).max(100),
  role: z.enum(['customer', 'operator', 'admin']),
  phone: z.string().regex(/^\+\d{10,15}$/).optional(),
})

type ImportRow = z.infer<typeof ImportRow>

function validateRows(rows: Record<string, string>[]): { valid: ImportRow[]; errors: Array<{ row: number; message: string }> } {
  const valid: ImportRow[] = []
  const errors: Array<{ row: number; message: string }> = []

  rows.forEach((row, i) => {
    const parsed = ImportRow.safeParse(row)
    if (parsed.success) valid.push(parsed.data)
    else errors.push({ row: i + 2, message: parsed.error.issues.map((iss) => `${iss.path.join('.')}: ${iss.message}`).join('; ') })
    //                              ^ +2: header is row 1, data starts at row 2
  })

  return { valid, errors }
}
```

### Apply in a Transaction

```ts
await prisma.$transaction(async (tx) => {
  for (const row of valid) {
    await tx.user.upsert({
      where: { email: row.email },
      create: row,
      update: { name: row.name, role: row.role },
    })
  }
})
```

For very large imports (10k+ rows), break into smaller transactions — one giant transaction holds locks too long.

### Error Report

When validation fails, give the user a downloadable CSV that mirrors the input plus an `error` column:

```ts
const errorReport = Papa.unparse(
  errors.map((e) => ({ row: e.row, error: e.message })),
)
```

Don't dump errors into a UI list — let the user re-edit the source file with errors next to the offending rows.

## Progress Tracking for Large Imports

For imports beyond ~10 seconds:

1. **Accept the file**, return a job ID immediately.
2. **Process in a background job** (BullMQ, Inngest).
3. **Update progress** every N rows.
4. **Client polls** `/imports/:id` or subscribes to SSE.

```ts
new Worker('import', async (job) => {
  const rows = await readStagedRows(job.data.importId)
  for (let i = 0; i < rows.length; i++) {
    await processRow(rows[i])
    if (i % 100 === 0) await job.updateProgress((i / rows.length) * 100)
  }
})
```

Show progress with a bar plus "Processing 4,231 of 10,000…"

## Streaming Large Exports

A 1M-row CSV in memory at once kills the server. Stream it:

```ts
import { Readable } from 'node:stream'
import Papa from 'papaparse'

app.get('/exports/orders.csv', async (req, res) => {
  res.set({
    'Content-Type': 'text/csv',
    'Content-Disposition': 'attachment; filename="orders.csv"',
  })
  res.write('﻿')

  res.write(Papa.unparse([['id', 'customer', 'total']], { header: false }) + '\n')

  const cursor = prisma.order.findMany({ /* ... */ })
  for await (const order of cursor) {
    res.write(Papa.unparse([[order.id, order.customer, order.total]], { header: false }) + '\n')
  }

  res.end()
})
```

Better: write to S3, return a presigned URL to the user. Then the request returns instantly and the user gets a download link.

## Filename Conventions

```ts
function exportFilename(prefix: string, ext: string): string {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
  return `${prefix}-${stamp}.${ext}`
}
// orders-2026-05-11T14-32-08.csv
```

ISO-8601 in the filename sorts naturally and survives copies between systems.

## Common Mistakes

- **CSV without BOM.** Excel renders `Ó©` instead of `é`. Always prepend `﻿`.
- **`dynamicTyping: true` and trusting it.** "Phone: 0712345678" becomes the number 712345678. Coerce explicitly.
- **CSV escaping done by hand.** Quotes within fields produce broken rows. Use PapaParse.
- **`new Date(row.date)` without a format spec.** Different machines parse "5/11/2026" differently.
- **Synchronous 100k-row export from a request handler.** Times out. Queue and link.
- **One giant transaction for 100k imports.** Locks held for minutes. Chunk.
- **Validating before parsing.** Bad CSV → confusing errors. Parse first, validate the structured rows.
- **No row numbers in error messages.** User has 5,000 rows; "email invalid" tells them nothing.
- **Apply before confirm.** User imports the wrong file, no undo. Always preview + confirm.
- **No streaming for big exports.** 500 MB CSV held in memory. Crash.
- **Dumping the entire DB on "Export."** Users want a filtered view. Respect their query.
- **PII in exports without access control.** Anyone with the link reads everyone's data. Authenticate the download.
- **No filename versioning.** Two downloads same minute overwrite each other. Include a timestamp.
- **XLSX produced from CSV by changing the extension.** Excel opens it but it's still CSV with a wrong MIME — confusing.
- **Trusting that "email" column is always called "email."** Headers vary. Map known synonyms or let the user pick columns.
- **Importing without an upsert/idempotency key.** Re-running the same file creates duplicates. Key by `email` or external ID.
