# Landing Pages & Conversion

How to build marketing pages that load fast, communicate quickly, and convert. Read before shipping any homepage, product page, or campaign page.

## Decision Tree

| Need | Pick |
|---|---|
| Static marketing site | **Astro** or **Next.js SSG** — fastest, best SEO |
| Marketing + app sharing components | **Next.js App Router** (marketing in `(marketing)` segment) |
| Quick one-off | **Vite + react-helmet-async** + prerender; see `seo-metadata.md` |
| CMS-driven content | **Sanity / Contentful + Next.js ISR** |

For most projects: **Astro for pure marketing, Next.js when an app sits next to it.**

## The 5-Second Test

A visitor decides to stay or leave in ~5 seconds. The above-fold must answer:

1. **What is this?** (one sentence)
2. **Who is it for?** (audience signal)
3. **Why should I care?** (outcome / benefit)
4. **What do I do next?** (CTA)

If a stranger can't answer all four from the hero alone, rewrite it.

## Above-Fold Anatomy

```tsx
function Hero() {
  return (
    <section className="container py-20 lg:py-32 grid lg:grid-cols-2 gap-12 items-center">
      <div className="space-y-6">
        <Badge>New in 2026</Badge>
        <h1 className="text-4xl lg:text-6xl font-bold tracking-tight">
          Find water vending machines<br />near you, instantly.
        </h1>
        <p className="text-lg text-muted-foreground max-w-prose">
          Search 500+ machines across Nairobi. See live availability. Pay with M-Pesa. Get water in 60 seconds.
        </p>
        <div className="flex flex-col sm:flex-row gap-3">
          <Button size="lg" asChild>
            <Link to="/find">Find a machine</Link>
          </Button>
          <Button size="lg" variant="outline" asChild>
            <Link to="/how-it-works">How it works</Link>
          </Button>
        </div>
        <TrustSignals />
      </div>
      <HeroVisual />
    </section>
  )
}
```

### Headline

- **One thought.** Not two clauses joined by "and."
- **Outcome-driven.** "Find water in 60 seconds" beats "Powerful water vending platform."
- **Specific.** Numbers, places, names. "500+ machines across Nairobi" not "many locations."
- **≤ 12 words.** Longer = scannable + ignored.

### Subheadline

- 1-2 sentences expanding the headline.
- Concrete proof of value: how it works in one line.
- Avoid features list — that comes lower.

### CTA

- **One primary + one secondary.** Three competing CTAs split focus.
- **Action verb starting the label** ("Find a machine" not "Click here").
- **Above the fold, visible without scroll** on mobile and desktop.

### Hero Visual

- **Product screenshot** beats stock photo. Show the thing.
- **Annotated** if multi-step is the point.
- **Loop video** if motion is the value — autoplay-muted, < 5s, < 1MB.
- **Lazy-load anything below fold.**

## Value Proposition Structure

Below the hero, in order:

1. **Problem statement** — what hurts today.
2. **Solution overview** — 3 column / 3 row "How it works."
3. **Features → outcomes** — feature title, outcome description.
4. **Social proof** — logos, testimonials, numbers.
5. **Pricing** (if applicable).
6. **FAQ**.
7. **Final CTA** — same as hero.

```tsx
function HowItWorks() {
  return (
    <section className="py-20 container">
      <h2 className="text-3xl font-bold text-center mb-12">From thirst to refreshed in three steps</h2>
      <div className="grid md:grid-cols-3 gap-8">
        <Step n="1" icon={MapPinIcon} title="Find a machine" body="Search by neighborhood or open the map." />
        <Step n="2" icon={QrCodeIcon} title="Scan or tap" body="Each machine has a unique code." />
        <Step n="3" icon={SmartphoneIcon} title="Pay with M-Pesa" body="STK Push to your phone. Done." />
      </div>
    </section>
  )
}
```

Features should be framed as **outcomes** — not what the feature is, but what it does for the user.

| Feature framing (bad) | Outcome framing (good) |
|---|---|
| "Real-time inventory API" | "Know before you go — see exactly what's available" |
| "M-Pesa integration" | "Pay in 10 seconds — no card, no cash, no app" |
| "Multi-language support" | "Use it in English or Swahili" |

## Trust Signals

- **Customer logos** (with permission) — 5-7 above fold or just below.
- **Testimonials** with name, role, photo. Skip if you have nobody yet — don't fake.
- **Stats** — "10,000 users," "500 machines," "98% uptime." Real numbers.
- **Press / awards** — "As seen in TechCrunch" if true.
- **Certifications** — SOC2, GDPR, WCAG AA, etc.
- **Security & privacy** copy — short, near the email field.

Test: would a skeptical user read these and feel safer? If they'd raise an eyebrow, cut it.

## Pricing Tables

Three tiers (Free / Pro / Enterprise) is the convention. Highlight the middle one.

```tsx
function PricingTable() {
  return (
    <section className="container py-20">
      <div className="grid md:grid-cols-3 gap-6">
        <PricingCard tier="Starter" price="Free" features={[...]} cta="Start free" />
        <PricingCard tier="Pro" price="KES 1,500/mo" features={[...]} cta="Start trial" highlighted />
        <PricingCard tier="Business" price="Custom" features={[...]} cta="Talk to sales" />
      </div>
    </section>
  )
}
```

### Rules

- **Monthly + annual toggle** with annual discount (~20%).
- **No hidden fees.** State setup, transaction, overage fees plainly.
- **Most popular badge** on the recommended tier.
- **Feature differences highlighted** — bold the ones that differ between tiers.
- **CTA per tier**, not one global CTA.
- **Money-back guarantee** if you offer one.

## FAQ Accordion

Solves objections. Watch your support inbox; the top 10 questions go here.

```tsx
import { Accordion } from '@base-ui-components/react/accordion'

<Accordion.Root>
  <Accordion.Item value="q1">
    <Accordion.Trigger>Do I need to download an app?</Accordion.Trigger>
    <Accordion.Panel>No. It works in your browser.</Accordion.Panel>
  </Accordion.Item>
  {/* ... */}
</Accordion.Root>
```

### Rules

- **5-10 questions max.** More = the page becomes a help center.
- **Real user questions**, not made-up "advantages."
- **Direct answers.** "Yes." "No." "It costs X." Then a sentence of detail.
- **Schema.org `FAQPage`** structured data — see `seo-metadata.md`.

## Mobile Optimization

Most marketing traffic is mobile. Design mobile first.

- **Single-column layout.** Hero stacks: text → image (or image first if visual is the value).
- **Tap targets ≥ 44px.**
- **Forms minimal** — name + email + send.
- **Sticky bottom CTA** on long pages.
- **No autoplay videos with sound.** Killed by browsers and annoying anyway.
- **Test on real device** — Chrome DevTools throttle ≠ a Samsung A20 on 3G.

## Performance (Above-Fold < 1.5s)

Marketing pages must load fast or the ad spend is wasted. See `web-performance.md` for full Core Web Vitals.

### Budgets

- **LCP**: < 1.5s on 4G.
- **CLS**: < 0.05 — no layout shift on font/image load.
- **JS bundle for marketing page**: < 80KB gzipped above-fold.
- **Hero image**: < 200KB (WebP/AVIF + responsive `srcset`).

### Techniques

- **Static rendering** (SSG/ISR) — no SSR latency, no API on path.
- **Hero image preload** in `<head>`:

```html
<link rel="preload" as="image" href="/hero.webp" fetchpriority="high" />
```

- **Font display swap** — `font-display: swap` on @font-face.
- **No third-party scripts above fold.** Analytics, chat widgets, ad pixels load after hydration.
- **Defer non-critical CSS.**
- **Compress images** — Sharp + AVIF/WebP; see `image-media-processing.md`.

## Analytics & Conversion Tracking

### UTM Parameters

```
https://example.com/?utm_source=google&utm_medium=cpc&utm_campaign=launch_q1&utm_content=ad_a
```

Capture on landing; persist to a first-party cookie for the session so the eventual signup attributes correctly.

```ts
function captureUTM() {
  const params = new URLSearchParams(window.location.search)
  const utm: Record<string, string> = {}
  for (const k of ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term']) {
    const v = params.get(k)
    if (v) utm[k] = v
  }
  if (Object.keys(utm).length) {
    document.cookie = `utm=${encodeURIComponent(JSON.stringify(utm))}; path=/; max-age=2592000; samesite=lax`
  }
}
```

### Conversion Events

Track in this order of importance:

1. **Page view** — baseline traffic.
2. **CTA click** — the primary buttons.
3. **Form start** — focused first field.
4. **Form submit** — actual conversion.
5. **Account created / sale** — the money event.

Send to Posthog / Plausible / GA4 — pick one (`logging-observability.md`).

### Pixel Implementations

- **Server-side conversion API** (Facebook CAPI, Google Enhanced Conversions) is more reliable than browser pixels (ad blockers).
- **Consent first.** Per GDPR, don't fire tracking before consent. See `security-practices.md`.

## A/B Testing Foundations

Don't ship A/B tests without:

- **A single primary metric** per test.
- **A minimum sample size calculated** in advance (use a calculator — 1000 visitors per variant is a floor, not a ceiling).
- **A pre-registered hypothesis** — "We expect copy variant B to increase signups by 15%."
- **A predetermined run time** — at least one full week to cover day-of-week variance.

Tooling:

- **GrowthBook** (open source, self-hostable).
- **Posthog Experiments**.
- **Optimizely** / **VWO** (commercial).

See `feature-flags.md` for the flagging substrate.

## Common Mistakes

- **Headline that describes the product.** "World's most advanced X." Doesn't tell visitor what they get.
- **Three competing CTAs above fold.** Decision paralysis. One primary.
- **Hero video autoplays with sound.** Browsers block; users rage. Muted + loop, < 5s.
- **Pricing tier names that say nothing.** "Bronze / Silver / Gold" — meaningless. Use audience-named: "Solo / Team / Business."
- **No FAQ for an objection-heavy product.** Visitors bounce to find answers elsewhere. Add the top 8 questions.
- **Testimonials with no name or photo.** "— Happy Customer" = fake. Real name + role + photo.
- **Trust logos of customers you don't actually have.** Lawsuit + brand damage.
- **A/B test stopped at p<0.05 after 2 days.** Multiple comparisons inflate false positives. Predetermine duration.
- **Analytics pixels firing before consent.** GDPR violation. Gate behind consent banner.
- **Hero image as a 3MB JPEG.** LCP 5s. Compress + preload.
- **No mobile sticky CTA.** Long page; users scroll past hero CTA, can't find another. Sticky.
- **Page renders with skeletons that flash before content.** CLS spike. SSG/SSR the above fold.
- **Chat widget loads in head, blocking render.** Defer or load after idle.
- **One generic CTA for paid + free.** Different audiences. Two distinct paths.
- **No `<title>` and `<meta description>` per page.** Search results show garbage. See `seo-metadata.md`.
- **All copy is "we / us / our".** Make it "you / your." Customer-centered.
- **Newsletter signup as the primary CTA.** Vanity metric. Convert to the actual product.
- **Marketing page bundled with app code.** App's 800KB bundle loads to read a static page. Separate route or static export.
- **Pricing tier highlighted is the cheapest.** Underprices yourself. Highlight what you want most users on.
