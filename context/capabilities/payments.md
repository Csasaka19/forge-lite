# Payments

How to build payment features. Read before integrating any payment provider or touching billing logic.

## Provider Selection

- **Stripe** — global card payments, subscriptions, marketplaces. Default for non-African card markets.
- **M-Pesa (Daraja API)** — mobile money in Kenya/Tanzania/Uganda. Required for most East African consumer apps.
- **Flutterwave / Paystack** — pan-African aggregators. Cover cards + mobile money across multiple countries in one integration.
- **PayPal** — global, lower preference. Add only if users demand it.

Pick by user geography, not by what you've used before. East African retail consumers expect M-Pesa.

## PCI Compliance Basics

The shortest path to PCI compliance is **never touching card numbers**.

- **Never store PAN, CVV, or expiration directly.** Even logging is a violation.
- **Use the provider's hosted fields or SDK** so card data never reaches your server.
  - Stripe Elements, Stripe Checkout, Payment Element.
  - PayPal SDK.
  - Flutterwave Inline / Paystack Inline.
- This puts you in **SAQ A** scope — the lightest tier. Filling out a self-assessment questionnaire annually is all most apps need.

What's safe to store: tokens returned by the provider (`pm_...`, `cus_...`), the last 4 digits, card brand, expiration month/year (for display only).

## Stripe Integration

### Setup

```bash
npm install stripe @stripe/stripe-js @stripe/react-stripe-js
```

```ts
// server
import Stripe from 'stripe'
export const stripe = new Stripe(env.STRIPE_SECRET_KEY, { apiVersion: '2024-12-18.acacia' })
```

Always pin `apiVersion`. Stripe ships breaking changes on dated versions; pinning avoids surprises.

### Payment Intent Flow (one-time payment)

```ts
// POST /api/payments/intent
const intent = await stripe.paymentIntents.create({
  amount: order.totalCents,
  currency: 'usd',
  metadata: { orderId: order.id, userId: req.user.id },
  automatic_payment_methods: { enabled: true },
})
res.json({ clientSecret: intent.client_secret })
```

```tsx
// client
import { loadStripe } from '@stripe/stripe-js'
import { Elements, PaymentElement, useStripe, useElements } from '@stripe/react-stripe-js'

const stripePromise = loadStripe(import.meta.env.VITE_STRIPE_PUBLISHABLE_KEY)

<Elements stripe={stripePromise} options={{ clientSecret }}>
  <CheckoutForm />
</Elements>
```

Inside `CheckoutForm`, call `stripe.confirmPayment` and let Stripe handle 3DS, redirects, and failure UX.

### Subscriptions

```ts
const customer = await stripe.customers.create({
  email: user.email,
  metadata: { userId: user.id },
})

const subscription = await stripe.subscriptions.create({
  customer: customer.id,
  items: [{ price: priceId }],
  payment_behavior: 'default_incomplete',
  expand: ['latest_invoice.payment_intent'],
})

return {
  subscriptionId: subscription.id,
  clientSecret: (subscription.latest_invoice as Stripe.Invoice).payment_intent.client_secret,
}
```

Manage the subscription **lifecycle from webhooks**, not from client confirmations. The client tells you the intent succeeded; the webhook tells you the subscription state.

### Refunds

```ts
await stripe.refunds.create({
  payment_intent: paymentIntentId,
  reason: 'requested_by_customer',
  metadata: { orderId, refundedBy: req.user.id },
})
```

Record refunds in your own database with timestamps and reasons. Reconcile against Stripe's records monthly.

## M-Pesa (Daraja API)

Daraja is Safaricom's API for M-Pesa. Sandbox is free; production requires a paybill or till number.

### STK Push (Customer-Initiated Payment)

```ts
async function initiateStkPush(phone: string, amount: number, accountRef: string) {
  const token = await getDarajaAccessToken()
  const timestamp = formatDate(new Date()) // YYYYMMDDHHMMSS
  const password = Buffer.from(
    env.MPESA_SHORTCODE + env.MPESA_PASSKEY + timestamp,
  ).toString('base64')

  return await fetch('https://api.safaricom.co.ke/mpesa/stkpush/v1/processrequest', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      BusinessShortCode: env.MPESA_SHORTCODE,
      Password: password,
      Timestamp: timestamp,
      TransactionType: 'CustomerPayBillOnline',
      Amount: amount,
      PartyA: phone,             // 2547XXXXXXXX
      PartyB: env.MPESA_SHORTCODE,
      PhoneNumber: phone,
      CallBackURL: `${env.API_URL}/webhooks/mpesa/stkpush`,
      AccountReference: accountRef,
      TransactionDesc: 'Payment',
    }),
  }).then((r) => r.json())
}
```

### Rules

- **Phone format**: `2547XXXXXXXX` — no `+`, no leading `0`. Normalize at the boundary.
- **Amount**: integer KES. M-Pesa doesn't accept fractional shillings via STK Push.
- **Idempotency**: store the `CheckoutRequestID` returned by Daraja before responding to the user. The callback arrives later — match by this ID.
- **Sandbox**: paybill `174379`, test phone `254708374149`, passkey from the Daraja dashboard.

### Callbacks

Daraja calls your `CallBackURL` with the result. Validate the IP if you can (Safaricom publishes ranges), and always look up the local record by `CheckoutRequestID` before acting.

```ts
app.post('/webhooks/mpesa/stkpush', async (req, res) => {
  const { Body: { stkCallback } } = req.body
  const requestId = stkCallback.CheckoutRequestID

  // Always 200 immediately — Daraja retries on non-2xx, causing duplicates.
  res.status(200).json({ ResultCode: 0, ResultDesc: 'Accepted' })

  await processStkCallback(stkCallback)
})
```

Process **after** responding. Daraja's retry policy doubles down on slow callbacks.

## Webhook Handling

Every payment integration relies on webhooks. Get them right.

### Verify Signatures

**Stripe**:

```ts
import express from 'express'

app.post('/webhooks/stripe', express.raw({ type: 'application/json' }), (req, res) => {
  let event: Stripe.Event
  try {
    event = stripe.webhooks.constructEvent(req.body, req.headers['stripe-signature']!, env.STRIPE_WEBHOOK_SECRET)
  } catch {
    return res.status(400).send('Invalid signature')
  }
  // ...
})
```

Use **raw body** for signature verification. JSON parsing before verification breaks the hash.

### Idempotency

Webhooks are at-least-once. Stripe retries for 3 days. Daraja retries on non-200. **Always assume the same event will arrive multiple times.**

```ts
// Insert the event ID before processing. Unique constraint blocks dupes.
await prisma.processedWebhookEvent.create({
  data: { provider: 'stripe', eventId: event.id },
}).catch((e) => {
  if (e.code === 'P2002') return null  // duplicate, ignore
  throw e
})
```

Or use the database's `INSERT ... ON CONFLICT DO NOTHING` semantics.

### Respond Fast

Webhook endpoints should respond in < 1 second. Move heavy work to a queue:

```ts
app.post('/webhooks/stripe', verify, async (req, res) => {
  const event = req.event
  res.status(200).end()              // ack immediately
  await webhookQueue.add('stripe-event', event)
})
```

The queue worker is allowed to retry, fail, dead-letter. The webhook endpoint is not.

### Handle Out-of-Order Events

Webhooks can arrive out of order. `payment_intent.succeeded` may arrive before `payment_intent.created` if the network shuffles them.

- Make handlers idempotent and order-tolerant. Check current state, advance only if the event is "newer" by timestamp or status.
- Use the event's `created` timestamp; ignore events older than the current state.

## Idempotency on the Client Side

When initiating a payment, attach an idempotency key so retrying doesn't double-charge:

```ts
const idempotencyKey = `order_${order.id}_${Date.now()}`
await stripe.paymentIntents.create(
  { amount: 1000, currency: 'usd' },
  { idempotencyKey },
)
```

Stripe stores the key for 24 hours and returns the original response for the same key.

## Subscription Billing

### Source of Truth

Stripe holds the subscription state. Your DB caches it. Whenever a billing event happens, sync from Stripe.

```prisma
model Subscription {
  id                String   @id
  userId            String   @unique @map("user_id")
  stripeSubId       String   @unique @map("stripe_sub_id")
  status            String   // 'active' | 'past_due' | 'canceled' | ...
  currentPeriodEnd  DateTime @map("current_period_end")
  cancelAtPeriodEnd Boolean  @default(false) @map("cancel_at_period_end")
}
```

Update via webhook on `customer.subscription.created`, `.updated`, `.deleted`, `invoice.paid`, `invoice.payment_failed`.

### Proration and Plan Changes

Let Stripe handle proration:

```ts
await stripe.subscriptions.update(subId, {
  items: [{ id: itemId, price: newPriceId }],
  proration_behavior: 'create_prorations',
})
```

Don't compute proration yourself. You'll get it wrong.

### Grace Periods

When `invoice.payment_failed` fires, don't immediately revoke access. Stripe's Smart Retries try again over ~3 weeks. Show a "payment failed, update card" banner. Revoke only on `customer.subscription.deleted` or after manual review.

## Refunds and Disputes

- **Refunds**: initiated by you. Reverse the charge, update local order status, notify user.
- **Disputes**: initiated by cardholder. Funds held immediately. Respond with evidence within the deadline (usually 7–21 days). Stripe Dashboard guides you through it.

Log every refund and dispute with `actorId`, `reason`, `timestamp`. Auditors will ask.

## Common Mistakes

- **Storing card numbers.** Never. Tokenize via the provider.
- **Trusting client `amount`.** Compute server-side from cart contents. The client says $1; the user pays $100 if you don't check.
- **No webhook signature verification.** Anyone with the URL can spoof "payment succeeded." Verify.
- **JSON-parsing the webhook body before verifying.** Breaks Stripe's signature check. Use raw body.
- **No idempotency.** Webhook retries double-charge users or double-fulfill orders.
- **Doing heavy work inside the webhook handler.** Timeouts trigger retries, which compound. Ack first, work after.
- **Sandbox keys in production by accident.** Different env vars, validated at boot, fail loud.
- **Updating subscription state from the client.** Webhooks are the source of truth.
- **Hard-coded currency.** Multi-currency apps need currency stored with the amount and provider-side conversion.
- **Storing amounts as floats.** `0.1 + 0.2 !== 0.3`. Use integer cents.
- **Refunding without recording it locally.** Customer claims they were refunded, your DB still shows them as paid. Reconcile.
- **STK Push without idempotency on CheckoutRequestID.** Duplicate callbacks create duplicate orders.
- **Phone numbers with `+` or leading `0` for M-Pesa.** Daraja rejects. Normalize to `2547XXXXXXXX`.
- **Revoking access on first failed invoice.** Grace periods exist. Stripe retries. Don't kick paying customers for a transient bank decline.
- **No PCI SAQ on file.** Even SAQ-A requires the form. Don't skip.
