# SEO & Metadata

How to make pages findable, shareable, and indexable. Read before launching anything public-facing.

## Decision Tree

| Surface | Approach |
|---|---|
| Marketing site, blog, content | **SSR or SSG required.** Next.js, Astro, Remix. |
| App behind auth | **SPA fine.** No SEO need; minimal metadata. |
| Public app with shareable URLs (product pages, listings) | **SSR for the shareable routes**, SPA for the rest |
| SPA built with Vite (no SSR) | **`react-helmet-async`** + a prerender service for crawlers |

SPAs are invisible to most social-media crawlers (they don't run JS). For OpenGraph previews on Slack, Discord, Twitter, WhatsApp — you need server-rendered metadata.

## Title & Meta Tags

Every page needs:

- **Title** — under 60 characters. Most important for SEO and tab clarity.
- **Meta description** — 150–160 characters. Appears in search results.
- **Canonical URL** — prevents duplicate-content penalties.
- **OpenGraph tags** — for social previews.
- **Twitter Card tags** — for X previews.

```html
<title>Find water vending machines near you — Water Vending</title>
<meta name="description" content="Locate machines in seconds, see live availability, pay with M-Pesa. Available across Nairobi." />
<link rel="canonical" href="https://example.com/find" />

<meta property="og:title" content="Find water vending machines near you" />
<meta property="og:description" content="Locate machines in seconds, see live availability, pay with M-Pesa." />
<meta property="og:url" content="https://example.com/find" />
<meta property="og:image" content="https://example.com/og/find.png" />
<meta property="og:type" content="website" />
<meta property="og:locale" content="en_KE" />
<meta property="og:site_name" content="Water Vending" />

<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:image" content="https://example.com/og/find.png" />
```

## Per-Framework Setup

### Next.js (App Router) — Built-In

```ts
// app/machine/[id]/page.tsx
import type { Metadata } from 'next'

export async function generateMetadata({ params }): Promise<Metadata> {
  const machine = await getMachine(params.id)
  return {
    title: `${machine.name} — Water Vending`,
    description: `${machine.name} at ${machine.location.address}. ${machine.status === 'online' ? 'Available now.' : 'Currently unavailable.'}`,
    alternates: { canonical: `https://example.com/machine/${machine.id}` },
    openGraph: {
      title: machine.name,
      description: machine.location.address,
      url: `https://example.com/machine/${machine.id}`,
      images: [{ url: `https://example.com/og/machine/${machine.id}.png`, width: 1200, height: 630 }],
    },
    twitter: { card: 'summary_large_image' },
  }
}
```

Next.js renders these server-side automatically. No `<head>` editing.

### React Helmet (Vite SPA)

```bash
npm install react-helmet-async
```

```tsx
import { HelmetProvider, Helmet } from 'react-helmet-async'

<HelmetProvider>
  <App />
</HelmetProvider>

function MachineDetail({ machine }: Props) {
  return (
    <>
      <Helmet>
        <title>{machine.name} — Water Vending</title>
        <meta name="description" content={machine.location.address} />
        <link rel="canonical" href={`https://example.com/machine/${machine.id}`} />
        <meta property="og:title" content={machine.name} />
        <meta property="og:image" content={`https://example.com/og/machine/${machine.id}.png`} />
      </Helmet>
      {/* page body */}
    </>
  )
}
```

For SPAs, crawlers that **don't** run JS will still see your `index.html`'s default metadata. Either prerender (see below) or accept the limitation for routes that don't need social previews.

### Astro / Remix

Use their built-in head primitives. Astro renders to HTML by default — no extra work. Remix has `meta` exports per route.

## OpenGraph Images

Dynamic per-page OG images dramatically improve link-share appeal.

### Next.js Image Generation

```tsx
// app/og/machine/[id]/route.tsx
import { ImageResponse } from 'next/og'

export async function GET(req: Request, { params }: Params) {
  const machine = await getMachine(params.id)
  return new ImageResponse(
    (
      <div style={{
        width: '100%', height: '100%', display: 'flex',
        background: '#1A73E8', color: '#fff', padding: 80, fontSize: 64,
      }}>
        <div>
          <div style={{ fontSize: 32 }}>Water Vending</div>
          <div style={{ marginTop: 24 }}>{machine.name}</div>
          <div style={{ fontSize: 28, marginTop: 16 }}>{machine.location.address}</div>
        </div>
      </div>
    ),
    { width: 1200, height: 630 },
  )
}
```

Edge-runtime image generation; cached aggressively.

### Static OG Images

For sites without a dynamic image runtime, pre-generate per content piece with **`@vercel/og`** at build, or render via a service (Cloudinary, Bannerbear).

### Dimensions

- **1200 × 630** is the universal good size.
- **Under 5 MB** — Facebook rejects larger.
- **PNG or JPEG.** SVG isn't supported by crawlers.
- **Text readable at 600×315** (the thumbnail size some platforms render).

## JSON-LD Structured Data

Helps search engines understand the page's content type and surface rich results.

```tsx
<Helmet>
  <script type="application/ld+json">
    {JSON.stringify({
      '@context': 'https://schema.org',
      '@type': 'LocalBusiness',
      name: machine.name,
      address: {
        '@type': 'PostalAddress',
        streetAddress: machine.location.address,
        addressLocality: 'Nairobi',
        addressCountry: 'KE',
      },
      geo: {
        '@type': 'GeoCoordinates',
        latitude: machine.location.lat,
        longitude: machine.location.lng,
      },
      openingHours: `${machine.operatingHours.open}-${machine.operatingHours.close}`,
    })}
  </script>
</Helmet>
```

### Common Types

- `Organization` / `LocalBusiness` — about the company.
- `Product` — product pages with price, rating, availability.
- `Article` — blog posts and news.
- `BreadcrumbList` — page hierarchy.
- `FAQPage` — FAQ sections; sometimes shown directly in search results.
- `Event` — for events with dates and venues.

Validate with **Google's Rich Results Test** (`search.google.com/test/rich-results`) before declaring victory.

## Sitemap

Tells crawlers what URLs exist and when they last changed.

### Generation

Generate at build time for static sites; dynamically for app-driven sites.

```ts
// app/sitemap.ts (Next.js)
import type { MetadataRoute } from 'next'

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const machines = await prisma.machine.findMany({ select: { id: true, updatedAt: true } })
  return [
    { url: 'https://example.com/', changeFrequency: 'weekly', priority: 1.0 },
    { url: 'https://example.com/find', changeFrequency: 'daily', priority: 0.9 },
    ...machines.map((m) => ({
      url: `https://example.com/machine/${m.id}`,
      lastModified: m.updatedAt,
      changeFrequency: 'daily' as const,
      priority: 0.7,
    })),
  ]
}
```

For Vite SPAs, generate `public/sitemap.xml` in a build script.

### Rules

- **Only include canonical URLs.** No duplicates, no auth-gated pages.
- **Cap at 50,000 URLs / 50 MB per sitemap.** Use a sitemap index for more.
- **Submit to Google Search Console** and **Bing Webmaster Tools**.
- **Reference from `robots.txt`**.

## robots.txt

```
# public/robots.txt
User-agent: *
Allow: /
Disallow: /admin/
Disallow: /api/
Disallow: /dashboard/

Sitemap: https://example.com/sitemap.xml
```

### Rules

- **Disallow auth-protected and internal routes.**
- **Don't disallow** assets, JS, CSS — Google needs to render the page to rank it.
- **`Disallow: /` blocks everything.** Don't ship this to production by accident — the most common SEO disaster.
- **Different `robots.txt` per environment.** Staging should fully disallow; production should allow.

## Canonical URLs

When the same content is reachable at multiple URLs, declare the canonical:

```html
<link rel="canonical" href="https://example.com/find" />
```

### When You Need It

- Trailing-slash vs no-trailing-slash variants.
- URLs with tracking parameters (`?utm_source=...`).
- Query-filterable views that should consolidate to one canonical.
- Mobile-specific subdomains.

Combine with 301 redirects where possible — the redirect is stronger than the canonical link.

## SSR / SSG for SEO

Crawlers vary in JS execution:

- **Googlebot** runs JS but with delays. Heavy SPAs rank worse and slower.
- **Most social crawlers** (Facebook, Twitter, LinkedIn, Slack) do **not** run JS.
- **Bingbot, DuckDuckGo** — limited JS execution.

### Strategy

- **Marketing site, blog, product pages**: SSG or SSR. Pure HTML on first response.
- **App pages behind auth**: SPA is fine. Crawlers don't index them anyway.
- **Public app routes that get shared**: SSR so social previews work.

For Vite SPAs that need crawler-friendly pages, use a **prerender service** (Prerender.io, Rendertron) or selectively SSR critical routes via a Node middleware.

## Testing Previews

Always validate before shipping.

- **Twitter/X**: `cards-dev.twitter.com/validator`
- **Facebook / LinkedIn**: `developers.facebook.com/tools/debug` and `linkedin.com/post-inspector`
- **Slack/Discord**: paste the URL in a private channel; check the unfurl.
- **Google Rich Results**: `search.google.com/test/rich-results`

Cache invalidation: after fixing OG tags, force Facebook/LinkedIn to re-scrape via their debugger. Otherwise the stale preview sticks around.

## Hreflang for i18n

For multilingual sites:

```html
<link rel="alternate" hreflang="en" href="https://example.com/en/find" />
<link rel="alternate" hreflang="sw" href="https://example.com/sw/find" />
<link rel="alternate" hreflang="x-default" href="https://example.com/find" />
```

Self-reference: each language page must list itself and all alternates.

## Common Mistakes

- **SPA + social-shareable URL with no SSR.** Previews show "Loading…" or worse. Render the metadata server-side.
- **`Disallow: /` in production `robots.txt`.** Site disappears from Google. Most common SEO disaster.
- **No canonical URL.** Trailing-slash duplicates split ranking.
- **OG image 4 KB or 4 MB.** Too small = pixelated; too large = rejected. 1200×630 PNG/JPEG ~100–500 KB.
- **Different metadata per render.** Server renders A, client hydrates B; crawler that doesn't run JS sees A only.
- **Title over 60 characters.** Truncated in search results. Keep tight.
- **Description as a marketing slogan, not a useful summary.** Lower click-through.
- **JSON-LD with invalid schema.** Tools accept it; Google ignores it silently. Validate.
- **Sitemap submitted but never refreshed.** New content not discovered. Regenerate on deploy.
- **Same OG image for every page.** Misses the "wow, that page looks shareable" lift. Dynamic per page.
- **`robots.txt` blocks JS/CSS.** Google can't render; pages rank worse. Only block content paths.
- **Hreflang with mismatched URLs.** Reciprocal links must be exact and self-referential.
- **No `og:locale`.** Right-to-left languages render with default LTR direction in unfurls.
- **OG image cached forever by social platforms.** Append a version (`?v=2`) when you change the design.
- **Staging environment indexable.** `staging.example.com` shows up in search, confusing users and splitting authority. Block via password, header check, or noindex.
