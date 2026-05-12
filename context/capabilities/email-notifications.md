# Email, SMS, Push & Notifications

How to deliver messages across channels. Read before adding any send-a-message feature.

## Provider Selection

### Email

- **Resend** — modern DX, generous free tier, React Email native. Default for new projects.
- **Postmark** — best deliverability for transactional. Premium.
- **SendGrid** — enterprise standard. Heavy admin UI; reliable.
- **AWS SES** — cheapest at scale. Bring-your-own everything (templates, suppression).
- **Loops / Customer.io** — marketing-flavored; transactional + lifecycle in one.

Never send transactional mail from Gmail or your office mail server. Use a real provider with proper SPF/DKIM/DMARC.

### SMS

- **Twilio** — global default. Expensive in some markets.
- **Africa's Talking** — East/West Africa. Cheaper than Twilio in Kenya, Uganda, Tanzania, Nigeria.
- **MessageBird / Vonage** — global, mid-tier pricing.

For Kenya specifically: Africa's Talking with a registered alphanumeric sender ID.

### Push

- **Expo Push** (React Native) — turnkey if you're on Expo.
- **Firebase Cloud Messaging (FCM)** — Android default; iOS via APNs.
- **OneSignal / Pusher Beams** — managed multi-platform.

## Email: Resend + React Email

```bash
npm install resend @react-email/components react-email
```

### Template as React

```tsx
// emails/order-confirmation.tsx
import { Html, Head, Body, Container, Text, Button, Section } from '@react-email/components'

export default function OrderConfirmation({ name, orderId, total }: Props) {
  return (
    <Html>
      <Head />
      <Body style={{ fontFamily: 'sans-serif', backgroundColor: '#f6f6f6' }}>
        <Container style={{ maxWidth: 600, margin: '0 auto', padding: 24, background: '#fff' }}>
          <Text>Hi {name},</Text>
          <Text>Your order #{orderId} is confirmed. Total: {total}.</Text>
          <Section style={{ marginTop: 24 }}>
            <Button href={`https://example.com/orders/${orderId}`} style={{ background: '#1A73E8', color: '#fff', padding: '10px 16px', borderRadius: 6 }}>
              View order
            </Button>
          </Section>
        </Container>
      </Body>
    </Html>
  )
}
```

### Send

```ts
import { Resend } from 'resend'
import OrderConfirmation from '../emails/order-confirmation'

const resend = new Resend(env.RESEND_API_KEY)

await resend.emails.send({
  from: 'Orders <orders@example.com>',
  to: user.email,
  subject: `Order #${order.id} confirmed`,
  react: OrderConfirmation({ name: user.name, orderId: order.id, total: '$24.00' }),
})
```

### Rules

- **Send from a real domain you control.** Configure SPF, DKIM, DMARC. Without these, mail goes to spam.
- **One sender per category** — `orders@`, `notifications@`, `auth@`. Helps users and gives you per-stream metrics.
- **Never send marketing from a transactional address.** Spam complaints poison your reputation for receipts.
- **Plaintext fallback** — Resend generates this automatically when you pass `react`.
- **Test rendering** with `react-email dev` locally. Outlook breaks otherwise-fine HTML.

## Triggering from Background Jobs

Never send mail from a request handler synchronously.

```ts
// route handler
await emailQueue.add('order-confirmation', { orderId: order.id })
res.status(201).json(order)

// worker
new Worker('email', async (job) => {
  if (job.name === 'order-confirmation') {
    const order = await prisma.order.findUnique({ where: { id: job.data.orderId }, include: { user: true } })
    await resend.emails.send({ /* ... */ })
  }
}, { connection: redis })
```

The request returns in 20ms. The email goes out within seconds.

## Deliverability Basics

- **SPF**: `v=spf1 include:resend.com -all` (or your provider's record).
- **DKIM**: signing key the provider gives you, added as a TXT record.
- **DMARC**: `v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com`. Start with `p=none` to monitor, tighten to `quarantine`/`reject`.
- **Bounces and complaints**: handle webhooks from your provider. Suppress addresses that bounce or complain.
- **Unsubscribe links** are legally required for anything marketing-flavored. Include `List-Unsubscribe` header.

## SMS

### Africa's Talking

```bash
npm install africastalking
```

```ts
import AfricasTalking from 'africastalking'

const at = AfricasTalking({ username: env.AT_USERNAME, apiKey: env.AT_API_KEY })

await at.SMS.send({
  to: ['+254712345678'],
  message: `Your order ${orderId} is ready for pickup.`,
  from: 'YourBrand',     // registered alphanumeric sender ID
})
```

### Twilio

```ts
import twilio from 'twilio'

const client = twilio(env.TWILIO_SID, env.TWILIO_AUTH_TOKEN)

await client.messages.create({
  to: '+254712345678',
  from: env.TWILIO_FROM,
  body: 'Your code is 123456',
})
```

### Rules

- **E.164 phone format**: `+<country><number>`, no spaces. Normalize at the boundary.
- **Keep messages short** — SMS is 160 chars per segment. Multi-segment costs more.
- **One-time codes**: 6 digits, expire in 5 minutes, rate-limit per number.
- **Include opt-out** for non-transactional: "Reply STOP to unsubscribe."
- **Verify sender IDs** with the carrier before launch (Africa's Talking, Twilio).

## Web Push

See `context/system/pwa-offline.md` for the full setup. Quick reference:

```ts
import webpush from 'web-push'

webpush.setVapidDetails('mailto:you@example.com', env.VAPID_PUBLIC, env.VAPID_PRIVATE)

await webpush.sendNotification(subscription, JSON.stringify({
  title: 'Order ready',
  body: 'Your water is ready for pickup.',
  url: '/orders/123',
}))
```

Handle `410 Gone` — the subscription is dead; delete it.

## Mobile Push: Expo

```ts
import { Expo } from 'expo-server-sdk'

const expo = new Expo()

const messages = subscribers.map((s) => ({
  to: s.pushToken,
  sound: 'default',
  title: 'Order ready',
  body: `Order #${order.id} is ready for pickup`,
  data: { orderId: order.id },
}))

const chunks = expo.chunkPushNotifications(messages)
for (const chunk of chunks) {
  await expo.sendPushNotificationsAsync(chunk)
}
```

Process **tickets** asynchronously to learn delivery outcomes — Expo returns a ticket ID; you fetch receipts later.

## In-App Notification Center

For a "bell icon with unread count" UX:

```prisma
model Notification {
  id        String   @id @default(uuid())
  userId    String   @map("user_id")
  type      String   // 'order.ready', 'message.received'
  title     String
  body      String
  data      Json?
  readAt    DateTime? @map("read_at")
  createdAt DateTime @default(now()) @map("created_at")
  @@index([userId, readAt])
}
```

Endpoints:

- `GET /notifications?cursor=...` — paginated.
- `POST /notifications/:id/read` — mark single read.
- `POST /notifications/read-all` — bulk.

Push real-time updates via SSE/WebSocket when a new notification is created. See `context/capabilities/realtime-features.md`.

## User Notification Preferences

Every user can opt in/out per channel per type.

```prisma
model NotificationPreference {
  userId  String @map("user_id")
  type    String           // 'order.ready', 'marketing.weekly'
  email   Boolean @default(true)
  push    Boolean @default(true)
  sms     Boolean @default(false)
  inApp   Boolean @default(true) @map("in_app")
  @@id([userId, type])
}
```

Before sending:

```ts
async function notifyOrderReady(order: Order) {
  const prefs = await getPrefs(order.userId, 'order.ready')

  await Promise.all([
    prefs.email && sendEmail(...),
    prefs.push && sendPush(...),
    prefs.sms && sendSms(...),
    prefs.inApp && createInApp(...),
  ].filter(Boolean))
}
```

Honor unsubscribe immediately. One-click, no confirmation page.

## Common Mistakes

- **Sending from `noreply@gmail.com` or your office address.** Goes to spam. Use a real provider with a configured domain.
- **No SPF/DKIM/DMARC.** Same outcome — spam folder.
- **Marketing and transactional from the same address.** A single complaint poisons your receipts.
- **Sending email synchronously from the request handler.** Slow SMTP = slow checkout. Queue it.
- **Hand-rolled HTML templates.** Outlook breaks. Use React Email + test renderer.
- **No bounce/complaint handling.** Suppression list never grows. Provider eventually shuts you off.
- **SMS without rate limits.** Abused for SMS pumping. Limit per number, per IP, per hour.
- **Non-E.164 phone numbers.** Twilio/Africa's Talking reject. Normalize before storing.
- **Push permission requested on page load.** Denial rate spikes. Ask in context.
- **Forgetting to delete dead push subscriptions.** Quota wasted, false delivery metrics.
- **No notification preferences.** Users get every notification on every channel. Eventually they unsubscribe from everything.
- **Unsubscribe behind a confirmation step.** Legally fragile in some jurisdictions. One click.
- **In-app notifications without a read state.** Bell icon counts forever.
- **Sending the same notification twice (email + push + SMS).** Annoying. Either let the user pick, or deliver to one channel and fall back only on non-delivery.
- **Free-text user-supplied content in SMS body.** XSS-equivalent for SMS — could include URLs, scams. Sanitize.
