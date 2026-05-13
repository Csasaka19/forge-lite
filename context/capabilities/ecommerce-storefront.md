# E-Commerce Storefront

How to build a product catalog, cart, checkout, and order flow that doesn't fall over at scale. Read before scoping any shop, marketplace, or one-product DTC site.

## Decision Tree

| Need | Pick |
|---|---|
| 1-5 SKUs, simple checkout | **Stripe Checkout hosted page** — minimal code |
| Full catalog, custom checkout | **Custom UI + Stripe `payment_intents`** + M-Pesa STK Push |
| Multi-vendor marketplace | **Stripe Connect** (out of scope here) |
| Headless commerce + complex backend | **Medusa**, **Shopify Storefront API** |
| Africa-focused | **M-Pesa Daraja STK Push** as primary; cards as fallback |

For most projects: **custom catalog + Stripe + M-Pesa**, see `payments.md`.

## Data Model

```ts
interface Category {
  id: string
  slug: string
  name: string
  parentId?: string             // hierarchy
  sortOrder: number
  imageUrl?: string
}

interface Product {
  id: string
  slug: string
  name: string
  description: string           // markdown
  shortDescription: string      // for cards (<160 chars)
  brand?: string
  categoryIds: string[]
  status: 'draft' | 'active' | 'archived'
  basePrice: number             // cents; variant price overrides
  currency: 'KES' | 'USD'
  taxable: boolean
  imageUrls: string[]           // ordered; first is primary
  attributes: Record<string, string>  // {"material": "cotton", "fit": "slim"}
  ratingAverage: number         // denormalized
  ratingCount: number
  createdAt: Date
  updatedAt: Date
}

interface Variant {
  id: string
  productId: string
  sku: string                   // unique inventory code
  name: string                  // "Large / Black"
  options: Record<string, string>  // {"size": "L", "color": "black"}
  price?: number                // override product.basePrice
  weight?: number               // grams, for shipping
  inventoryCount: number
  inventoryPolicy: 'deny' | 'continue'  // allow oversells?
}

interface Review {
  id: string
  productId: string
  userId: string
  rating: number                // 1-5
  title?: string
  body: string
  verifiedPurchase: boolean
  createdAt: Date
}

interface CartItem {
  id: string
  cartId: string
  variantId: string
  quantity: number
  priceSnapshot: number         // price at time of add
  addedAt: Date
}

interface Cart {
  id: string
  userId?: string               // null = guest
  sessionId?: string            // for guests
  status: 'active' | 'abandoned' | 'converted'
  updatedAt: Date
}

interface Order {
  id: string
  orderNumber: string           // human-readable: "ORD-2026-00042"
  userId?: string
  email: string                 // for guest checkout
  status: 'pending' | 'paid' | 'fulfilling' | 'shipped' | 'delivered' | 'cancelled' | 'refunded'
  subtotal: number
  shipping: number
  tax: number
  discount: number
  total: number
  currency: string
  shippingAddress: Address
  billingAddress?: Address
  paymentMethod: 'card' | 'mpesa'
  paymentIntentId?: string
  mpesaReceiptNumber?: string
  shippingMethod: string
  trackingNumber?: string
  createdAt: Date
  paidAt?: Date
  shippedAt?: Date
  deliveredAt?: Date
}

interface OrderItem {
  id: string
  orderId: string
  variantId: string
  quantity: number
  unitPrice: number             // snapshot
  productName: string           // snapshot for receipts after product edit
  variantName: string
  sku: string
}
```

Index `products (status, created_at desc)`, `variants (product_id)`, `orders (user_id, created_at desc)`, `cart_items (cart_id)`. See `database-patterns.md`.

**Snapshot product name/price into OrderItem.** Customers see the price they paid even if you edit the product later.

## UI Patterns

### Catalog (`/shop`, `/c/:slug`)

- **Sidebar filters**: price range, attributes (size, color), rating, in-stock toggle.
- **Sort** (popular, price asc/desc, newest, rating).
- **Grid** (3-4 cols desktop, 2 cols mobile).
- **Pagination** or infinite scroll (paginated URLs are more shareable + crawlable; see `seo-metadata.md`).

Filter state in URL (`?color=black&min=1000`); see `state-management.md` for URL state patterns and `search-filtering.md`.

### Product Card

```tsx
function ProductCard({ p }: { p: Product }) {
  return (
    <Link to={`/p/${p.slug}`} className="group">
      <div className="aspect-square overflow-hidden rounded-lg bg-muted">
        <img
          src={p.imageUrls[0]}
          alt={p.name}
          loading="lazy"
          className="size-full object-cover group-hover:scale-105 transition-transform"
        />
      </div>
      <div className="mt-3 space-y-1">
        <h3 className="font-medium line-clamp-2">{p.name}</h3>
        <p className="text-sm text-muted-foreground">{p.brand}</p>
        <div className="flex items-baseline gap-2">
          <span className="font-semibold">{formatMoney(p.basePrice, p.currency)}</span>
          {p.ratingCount > 0 && (
            <span className="text-sm">★ {p.ratingAverage.toFixed(1)} ({p.ratingCount})</span>
          )}
        </div>
      </div>
    </Link>
  )
}
```

### Product Page (`/p/:slug`)

Layout: image gallery left (or top on mobile) + buy box right.

- **Gallery** — main image + thumbnails. Zoom on hover. Swipe on mobile.
- **Title + brand**.
- **Price** — large.
- **Variant pickers** — color swatches, size buttons. Show "Out of stock" on disabled options.
- **Quantity stepper**.
- **Add to cart** — primary CTA, sticky on mobile scroll.
- **Description** (long form).
- **Specs / attributes** table.
- **Reviews** — average + distribution + list.
- **Related products** (same category, top sellers).

```tsx
function ProductPage({ product, variants }: Props) {
  const [selected, setSelected] = useState<Variant>(variants[0])
  const inStock = selected.inventoryCount > 0 || selected.inventoryPolicy === 'continue'

  return (
    <div className="grid lg:grid-cols-2 gap-8">
      <ImageGallery images={product.imageUrls} alt={product.name} />
      <div className="space-y-4">
        <h1 className="text-3xl font-bold">{product.name}</h1>
        <div className="text-2xl">{formatMoney(selected.price ?? product.basePrice, product.currency)}</div>
        <VariantPicker variants={variants} selected={selected} onChange={setSelected} />
        <Button disabled={!inStock} onClick={() => addToCart(selected.id, 1)}>
          {inStock ? 'Add to cart' : 'Out of stock'}
        </Button>
        <Tabs defaultValue="description">
          <TabsList>
            <TabsTrigger value="description">Description</TabsTrigger>
            <TabsTrigger value="specs">Specs</TabsTrigger>
            <TabsTrigger value="reviews">Reviews ({product.ratingCount})</TabsTrigger>
          </TabsList>
          {/* ... */}
        </Tabs>
      </div>
    </div>
  )
}
```

### Cart

- Slide-in drawer from right on add-to-cart, plus full cart page at `/cart`.
- Line items: thumbnail, name, variant, quantity stepper, price, remove.
- Subtotal, "Free shipping in N more".
- Promo code input.
- "Checkout" primary button.

### Checkout

Three-step or single-page (single is preferred for friction reduction; see `forms-wizards.md` for multi-step pattern).

1. **Contact + shipping address**.
2. **Shipping method** (with prices).
3. **Payment** — card via Stripe Elements, or M-Pesa phone number for STK Push.

Sticky right-side **order summary** with line items, subtotal, shipping, tax, total.

### Confirmation (`/orders/:orderNumber`)

Order number prominent. Items, totals, address, expected delivery. "Track order" button.

## Cart Persistence

- **Guest carts**: cookie or session. `sessionId` on Cart.
- **Logged-in**: scoped by `userId`. Persist across devices.
- **Merge on login** — when a guest with a cart logs in, merge their `sessionId` cart into the user's existing cart. Resolve duplicate variants by summing quantities (cap at inventory).

```ts
async function mergeGuestCart(sessionId: string, userId: string) {
  const guest = await prisma.cart.findFirst({ where: { sessionId, status: 'active' }, include: { items: true } })
  if (!guest) return
  const user = await prisma.cart.upsert({
    where: { userId_status: { userId, status: 'active' } },
    create: { userId, status: 'active' },
    update: {},
  })
  for (const item of guest.items) {
    await prisma.cartItem.upsert({
      where: { cartId_variantId: { cartId: user.id, variantId: item.variantId } },
      create: { cartId: user.id, variantId: item.variantId, quantity: item.quantity, priceSnapshot: item.priceSnapshot },
      update: { quantity: { increment: item.quantity } },
    })
  }
  await prisma.cart.delete({ where: { id: guest.id } })
}
```

## Inventory & Concurrency

When the customer hits "Pay":

```ts
await prisma.$transaction(async (tx) => {
  for (const item of order.items) {
    const v = await tx.variant.findUnique({ where: { id: item.variantId } })
    if (!v) throw new Error('Variant not found')
    if (v.inventoryPolicy === 'deny' && v.inventoryCount < item.quantity) {
      throw new OutOfStockError(item.variantId)
    }
    await tx.variant.update({
      where: { id: item.variantId },
      data: { inventoryCount: { decrement: item.quantity } },
    })
  }
  await tx.order.create({ data: orderData })
})
```

For high-concurrency drops, use `SELECT ... FOR UPDATE` (Postgres) on the variant row inside the transaction. Optimistic locking with a version column also works.

## Order Status Lifecycle

```
pending → (payment succeeds) → paid → fulfilling → shipped → delivered
                            └→ failed (timeout/decline)
paid → (refund) → refunded
any → cancelled
```

Webhook from payment provider transitions `pending → paid`. See `payments.md` for Stripe/M-Pesa webhook patterns and signature verification.

Trigger emails on each transition (`email-notifications.md`):

- `paid` — receipt.
- `shipped` — tracking number.
- `delivered` — review request (delay 3 days).
- `refunded` — confirmation.

Idempotency: each transition logged with `(orderId, fromStatus, toStatus, at)`. Replay-safe.

## Search & Filtering

Implement product search per `search-filtering.md`: Postgres FTS on `(name, description, brand)`, trigram for typo tolerance, filter facets from indexed columns.

## SEO

Per `seo-metadata.md`:

- Server-render product and category pages (SSR or SSG).
- Each product: structured data `@type: Product` with price, availability, rating.
- Each category: `BreadcrumbList`.
- Canonical URLs (no trailing slash, no tracking params).
- OG image per product = first product image.

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Product",
  "name": "{{product.name}}",
  "image": ["{{product.imageUrls[0]}}"],
  "description": "{{product.shortDescription}}",
  "brand": { "@type": "Brand", "name": "{{product.brand}}" },
  "offers": {
    "@type": "Offer",
    "url": "https://example.com/p/{{product.slug}}",
    "priceCurrency": "{{product.currency}}",
    "price": "{{product.basePrice / 100}}",
    "availability": "{{inStock ? 'InStock' : 'OutOfStock'}}"
  },
  "aggregateRating": {
    "@type": "AggregateRating",
    "ratingValue": "{{product.ratingAverage}}",
    "reviewCount": "{{product.ratingCount}}"
  }
}
</script>
```

## Common Mistakes

- **Product price NOT snapshot into OrderItem.** Customer disputes show new price, not what they paid. Always snapshot.
- **Inventory check outside a transaction.** Two customers buy the last unit; oversell. Wrap in DB transaction with row lock.
- **Cart items reference variantId only, no priceSnapshot.** Prices change between add and checkout — customer confused. Snapshot on add, re-check on checkout, prompt if changed.
- **Variant out-of-stock disables the entire product page.** Just disable that variant button. Show "Out of stock" tag.
- **Stripe webhook doesn't verify signature.** Spoofed `payment_intent.succeeded` marks unpaid orders as paid. See `payments.md`.
- **No idempotency on order creation.** Double-submit creates two orders. Idempotency key from client or hash of cart contents.
- **`Cart` shared across guest sessions.** Cookie collisions; users see each other's carts. Generate unique session ID per device.
- **Guest cart not merged on login.** User adds item, logs in, item gone. Merge.
- **Inventory `inventoryCount` decremented only on payment success.** Race window between add-to-cart and pay. For limited drops, reserve at add-to-cart with TTL.
- **Promo code not validated server-side at checkout.** Discount manipulation. Always re-validate on the server.
- **Tax computed in browser.** Tampering. Server-side only.
- **Shipping address validation missing.** Bad addresses = lost packages. Use address validation (Google Places, Lob).
- **No order detail page after checkout.** Users refresh the success page; data gone. Use stable `/orders/:orderNumber`.
- **Review submission allows non-purchasers without flag.** Fake reviews. Add `verifiedPurchase: boolean`.
- **Product listings refetched on every filter change without debounce.** Server hammered. Debounce + URL state.
- **No `aria-label` on quantity steppers.** Inaccessible. See `accessibility-deep.md`.
- **Product images served as 4MB JPEGs.** Page weight tanks. Use Sharp/`next/image` per `image-media-processing.md`.
- **Status transitions allowed in any order.** "Delivered" before "shipped". Enforce in a state machine.
- **No abandoned-cart recovery emails.** Lost revenue. Trigger after 1h, 24h, 72h.
