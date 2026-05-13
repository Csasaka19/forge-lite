# Crowdfunding & Pre-Sale Platforms

How to build Kickstarter-style campaigns: tier-based pledges, progress visualization, deadline urgency, payment collection, and backer engagement. Read before scoping any pre-sale, kickstarter clone, or community-funded product page.

## Decision Tree

| Question | Pick |
|---|---|
| All-or-nothing funding (charge only if goal hit) | **Stripe `payment_intent` with `capture_method: manual`** + capture on success |
| Flexible funding (charge immediately) | **Stripe Checkout** standard flow |
| Local + international backers | **Stripe + M-Pesa** (see `payments.md`) |
| Physical reward fulfillment | Track addresses + shipping status on Pledge |
| Digital-only rewards | Skip address; deliver on funded transition |
| Equity/regulated crowdfunding | **Don't build it yourself** — use Wefunder, Republic. Compliance is the product. |

For most projects: **Stripe Checkout + manual capture for all-or-nothing**, **Stripe + M-Pesa with immediate capture for flexible**.

## Data Model

```ts
interface Campaign {
  id: string
  slug: string                    // URL-friendly
  title: string
  tagline: string                 // one-liner under title
  description: string             // rich text / markdown
  heroImage: string
  heroVideo?: string              // optional explainer video URL
  creatorId: string
  goalAmount: number              // in minor units (cents)
  currency: 'KES' | 'USD' | 'EUR'
  fundingModel: 'all_or_nothing' | 'flexible'
  status: 'draft' | 'live' | 'funded' | 'closed' | 'cancelled'
  startsAt: Date
  endsAt: Date
  raisedAmount: number            // denormalized, updated on pledge
  backerCount: number             // denormalized
  createdAt: Date
}

interface Tier {
  id: string
  campaignId: string
  name: string                    // "Early Bird", "Founder"
  description: string
  pledgeAmount: number            // min pledge for this tier
  limitedQuantity?: number        // null = unlimited
  claimedQuantity: number         // denormalized
  estimatedDelivery: Date
  shippingRequired: boolean
  rewards: string[]               // ["1× T-shirt", "Signed poster"]
  sortOrder: number
}

interface Backer {
  id: string
  userId: string
  email: string
  displayName?: string            // shown publicly if opted in
  isPublic: boolean
}

interface Pledge {
  id: string
  campaignId: string
  backerId: string
  tierId: string
  amount: number
  currency: string
  status: 'pending' | 'authorized' | 'captured' | 'failed' | 'refunded'
  stripePaymentIntentId?: string
  mpesaCheckoutRequestId?: string
  shippingAddress?: Address
  message?: string                // optional note to creator
  createdAt: Date
  capturedAt?: Date
}

interface Update {
  id: string
  campaignId: string
  title: string
  body: string                    // markdown
  publishedAt: Date
  visibleTo: 'public' | 'backers_only'
}
```

Index `pledges (campaign_id, status)`, `tiers (campaign_id, sort_order)`, `campaigns (status, ends_at)` for lists.

## UI Patterns

### Campaign Page (`/c/:slug`)

Top-to-bottom structure:

1. **Hero** — large image or autoplay-muted video. Title + tagline.
2. **Progress block** — `raisedAmount / goalAmount`, percentage, backer count, days remaining. Sticky on scroll for mobile.
3. **Primary CTA** — "Back this project" — opens tier picker drawer/modal.
4. **About** — long-form description with images.
5. **Tiers** — vertical list, each as a card. Limited tiers show "X of Y claimed" or "SOLD OUT".
6. **Updates** — recent posts from the creator (newest first, 3 visible + "see all").
7. **FAQ** — accordion.
8. **Backers** — public backer list grid (avatar + display name).
9. **Creator** — profile card linking to other campaigns.

### Progress Bar

```tsx
function CampaignProgress({ campaign }: { campaign: Campaign }) {
  const pct = Math.min(100, (campaign.raisedAmount / campaign.goalAmount) * 100)
  const daysLeft = Math.max(0, Math.ceil((+campaign.endsAt - Date.now()) / 86_400_000))

  return (
    <div className="space-y-3">
      <div className="flex items-baseline justify-between">
        <div className="text-3xl font-bold">{formatMoney(campaign.raisedAmount, campaign.currency)}</div>
        <div className="text-sm text-muted-foreground">of {formatMoney(campaign.goalAmount, campaign.currency)}</div>
      </div>
      <div className="h-2 bg-muted rounded-full overflow-hidden">
        <div className="h-full bg-primary transition-all" style={{ width: `${pct}%` }} />
      </div>
      <div className="flex justify-between text-sm">
        <span><strong>{campaign.backerCount}</strong> backers</span>
        <span><strong>{daysLeft}</strong> days left</span>
      </div>
    </div>
  )
}
```

### Tier Card

- Pledge amount at the top, bold.
- Tier name + description.
- Reward bullets.
- Estimated delivery.
- "X claimed of Y" if limited.
- Disabled with "Sold out" badge when claimed >= limit.
- "Select" button → opens pledge flow.

### Countdown

Persistent in the page header once `endsAt - now < 48h`:

```tsx
function UrgencyBanner({ endsAt }: { endsAt: Date }) {
  const ms = +endsAt - Date.now()
  if (ms > 48 * 3600_000 || ms < 0) return null
  const hours = Math.floor(ms / 3600_000)
  const minutes = Math.floor((ms % 3600_000) / 60_000)
  return (
    <div className="bg-amber-500 text-white px-4 py-2 text-center text-sm font-medium">
      Only {hours}h {minutes}m left to back this campaign
    </div>
  )
}
```

## Campaign Lifecycle

```
draft → (creator submits) → review → live → (endsAt reached)
                                          ├─ funded   (goal hit, all-or-nothing)
                                          ├─ closed   (goal hit OR flexible)
                                          └─ closed   (goal missed, all-or-nothing)
```

Transitions:

- **draft → live** — creator clicks "Launch", admin approves (or skip for trusted creators). `startsAt = now()`.
- **live → funded** — scheduled job at `endsAt` checks `raisedAmount >= goalAmount` for all-or-nothing.
- **funded → captured** — server-side job iterates authorized pledges and captures via Stripe. See `payments.md` and `background-jobs.md`.
- **live → closed (missed)** — for all-or-nothing, release authorizations (Stripe `payment_intent.cancel`).
- **any → cancelled** — creator or admin halts. Refund captured pledges.

## All-or-Nothing Implementation

For all-or-nothing campaigns, authorize the card immediately but capture only on success:

```ts
import Stripe from 'stripe'

async function createPledge(input: CreatePledgeInput) {
  const intent = await stripe.paymentIntents.create({
    amount: input.amount,
    currency: input.currency.toLowerCase(),
    capture_method: 'manual',
    customer: input.stripeCustomerId,
    metadata: { campaignId: input.campaignId, tierId: input.tierId },
  })

  await prisma.pledge.create({
    data: {
      campaignId: input.campaignId,
      backerId: input.backerId,
      tierId: input.tierId,
      amount: input.amount,
      currency: input.currency,
      status: 'authorized',
      stripePaymentIntentId: intent.id,
    },
  })

  return { clientSecret: intent.client_secret }
}
```

On `funded`:

```ts
async function captureFundedPledges(campaignId: string) {
  const pledges = await prisma.pledge.findMany({
    where: { campaignId, status: 'authorized' },
  })
  for (const p of pledges) {
    await capturePledge(p)               // enqueue, don't run inline
  }
}
```

**Authorization expires after 7 days on Stripe.** If your campaign runs longer than that, re-authorize as the end approaches or use a SetupIntent + off-session charge pattern.

## Email Sequences

Use `email-notifications.md` patterns. Triggers and templates:

| Trigger | Template |
|---|---|
| Pledge created (authorized) | "Thanks for backing — we'll charge you only if we hit the goal" |
| Campaign 48h from end, < 80% funded | "We're at X% — final push" (creator → all backers) |
| Campaign funded | "We did it! Your card will be charged in 24h" |
| Pledge captured | "Receipt + what happens next" |
| Pledge capture failed | "Card declined — update payment in 7 days" |
| Campaign closed unfunded | "We didn't make it — your authorization has been released" |
| Update posted | "New update from [creator]" |
| Estimated delivery 30 days out | "Reward shipping update" |
| Reward shipped | "Tracking: ..." |

Use a per-campaign `email_log` table to enforce **send-once-per-trigger** idempotency.

## Urgency & Scarcity UX

- **Live raised count** — animate increment when new pledge lands (via SSE; see `realtime-features.md`).
- **"Last X tiers left"** badges when `limitedQuantity - claimedQuantity <= 3`.
- **Countdown** activates within last 48h.
- **Recent activity** — "Aisha from Nairobi just backed at KES 5,000" (with opt-out).
- **Social proof** — show backer count, average pledge, top tiers.

**Don't fake it.** Fake counters and "only 1 left!" lies destroy trust. Show real data or nothing.

## Backer Dashboard (`/me/pledges`)

Each pledge row:

- Campaign title + thumbnail.
- Tier name + pledge amount.
- Status (Authorized / Captured / Refunded / Failed).
- Estimated delivery + shipping status.
- Edit shipping address (until lock date).
- Cancel pledge button (until lock date or capture).

After fulfillment, link to the creator's shipped tracking.

## Analytics

Track per campaign:

- Page views (anonymous + identified).
- Pledge starts (clicked "Back this project").
- Pledge completions.
- Conversion rate (starts → completions).
- Average pledge amount.
- Tier-level breakdown.

Funnel events to Posthog / Mixpanel; see `web-performance.md` for Core Web Vitals.

## Common Mistakes

- **Capture before campaign funded for all-or-nothing.** Backers see "Charged" before the goal hits — angry refund requests if it misses. Use `capture_method: manual`.
- **Authorization expires mid-campaign.** Stripe holds for 7 days. Long campaigns must re-authorize or use off-session charging.
- **No idempotency on capture-all job.** Job retries double-charge. Use Stripe's idempotency keys on capture calls.
- **Tier `claimedQuantity` not transactional with Pledge create.** Two backers grab the last slot. Wrap in DB transaction with a `SELECT FOR UPDATE`.
- **Raised amount counted from authorized + captured.** Refunded pledges still in the total. Subtract refunded/failed.
- **Same campaign shown live before `startsAt` or after `endsAt`.** Index `(status, starts_at, ends_at)` and filter explicitly.
- **No public backer opt-in/opt-out.** Privacy complaints. Default to anonymous.
- **Refund flow forgotten.** Backers can't get money back; chargebacks spike. Build refund UI for support.
- **No M-Pesa for local markets.** International cards-only blocks African backers. See `payments.md` for STK Push.
- **Update emails sent every time creator edits.** Spam. Only on publish, with confirm.
- **No "campaign closed" page.** Old URLs 404. Show final state, total raised, thanks.
- **Countdown showing negative time after end.** Cap at 0; switch to "Closed" badge.
- **Fake scarcity ("1 left!").** Trust killer. Use real `claimedQuantity` only.
- **Address collected at pledge for digital-only rewards.** Friction with no benefit. Conditional on `shippingRequired`.
- **No webhook signature verification.** Stripe events spoofable; see `payments.md`.
- **`raisedAmount` recomputed via aggregate on every page load.** Slow. Denormalize; update on pledge transitions.
