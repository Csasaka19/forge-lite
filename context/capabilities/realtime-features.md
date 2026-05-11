# Real-Time Features

How to build features that update without page reloads. Read before adding live dashboards, notifications, chat, or presence.

## Choose the Right Transport

Pick by the shape of the data flow.

| Need | Transport |
|---|---|
| Server → client only (notifications, live counter, dashboard) | **Server-Sent Events (SSE)** |
| Bidirectional (chat, collaborative editing, multiplayer) | **WebSockets** |
| Bursty updates, simple infra | **Long polling** |
| Periodic refresh, low-stakes | **Polling** |

Start with the simplest. Polling at 30s is usually fine for "is this thing still working." Reach for WebSockets when you actually need bidirectional or sub-second latency.

## Server-Sent Events

One-way streaming over HTTP. Simpler than WebSockets, works through proxies, automatic reconnection in the browser.

### Server (Hono / Express)

```ts
app.get('/events', requireAuth, (req, res) => {
  res.set({
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no',   // disable Nginx buffering
  })
  res.flushHeaders()

  const send = (data: unknown) => {
    res.write(`data: ${JSON.stringify(data)}\n\n`)
  }

  // Heartbeat every 25s — keeps proxies from closing the connection.
  const heartbeat = setInterval(() => res.write(':\n\n'), 25_000)

  const unsubscribe = eventBus.subscribe(req.user.id, send)

  req.on('close', () => {
    clearInterval(heartbeat)
    unsubscribe()
  })
})
```

### Client

```ts
const es = new EventSource('/events', { withCredentials: true })

es.onmessage = (e) => {
  const data = JSON.parse(e.data)
  // ...
}

es.onerror = () => {
  // EventSource auto-reconnects with exponential backoff. No action needed.
}
```

### Rules

- Send a heartbeat every 15–30s. Proxies close idle connections.
- Disable buffering on the proxy (`X-Accel-Buffering: no` for Nginx).
- One open connection per tab. Chrome limits HTTP/1.1 to 6 connections per origin — over HTTP/2 this is no longer a problem.
- Authenticate via cookies (`withCredentials: true`) — EventSource doesn't accept custom headers.

## WebSockets

Bidirectional and lower latency. Use when SSE isn't enough.

### Server (ws library)

```ts
import { WebSocketServer } from 'ws'

const wss = new WebSocketServer({ noServer: true })

server.on('upgrade', async (req, socket, head) => {
  const user = await authenticateUpgrade(req)
  if (!user) return socket.destroy()

  wss.handleUpgrade(req, socket, head, (ws) => {
    ws.userId = user.id
    wss.emit('connection', ws, req)
  })
})

wss.on('connection', (ws) => {
  ws.on('message', (raw) => {
    const msg = JSON.parse(raw.toString())
    // route by msg.type
  })
  ws.on('close', () => { /* cleanup */ })
})
```

For production, use **Socket.IO** when you need:
- Automatic reconnection with backoff.
- Rooms (broadcast to subsets).
- Fallback to long polling on networks that block WebSockets.

For raw WebSockets, you build those yourself.

### Authentication

WebSocket upgrade requests carry cookies (same-origin) — verify auth on the upgrade. Don't accept "send me a JWT in your first message" — by then, the connection is established and resource has been allocated.

### Heartbeats and Recovery

```ts
function startWs() {
  const ws = new WebSocket(`wss://${location.host}/ws`)
  let pingTimer: number

  ws.onopen = () => {
    pingTimer = window.setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: 'ping' }))
    }, 25_000)
  }

  ws.onclose = () => {
    clearInterval(pingTimer)
    setTimeout(startWs, backoffMs())     // reconnect with exponential backoff
  }

  return ws
}
```

Exponential backoff: 1s, 2s, 4s, 8s, capped at 30s. Add jitter to avoid thundering herd.

## Polling as Fallback

Always have a polling fallback. WebSockets fail on hotel wifi, corporate proxies, mobile carrier middleboxes.

### Pattern

```tsx
import { useQuery } from '@tanstack/react-query'

const { data } = useQuery({
  queryKey: ['dashboard'],
  queryFn: fetchDashboard,
  refetchInterval: 30_000,        // 30s
  refetchIntervalInBackground: false,
})
```

- **Don't poll in the background tab** by default. Wastes battery and bandwidth.
- **Increase interval** with visibility: 30s when visible, 5min when hidden.
- **Long polling** (server holds the request open until data arrives) is acceptable but harder to scale than SSE.

### Adaptive Polling

Combine real-time and polling: subscribe to SSE/WebSocket; if the connection drops, fall back to polling until it recovers.

## Real-Time Dashboards

### Architecture

1. App writes events to a queue (or commits to DB and publishes a notification).
2. A worker aggregates events into dashboard state.
3. Dashboard state lives in Redis (or a memory cache) for fast reads.
4. Clients subscribe via SSE; server pushes updates when state changes.

Don't query the database on every tick for every connected client. That doesn't scale past a handful of users.

### Update Throttling

Don't push every tiny change. Batch updates server-side at ~250ms intervals so clients don't drown in re-renders.

```ts
let pending: Update[] = []
setInterval(() => {
  if (pending.length === 0) return
  broadcast({ type: 'batch', updates: pending })
  pending = []
}, 250)
```

## Presence Indicators

"Who is online right now?"

### Implementation

- Each client sends a heartbeat (every 30s) or maintains a connection.
- Server tracks last-seen per user in Redis with a 60s TTL.
- "Online" = present in Redis.
- "Last active" = max(last heartbeat, last activity).

```ts
async function markOnline(userId: string) {
  await redis.set(`presence:${userId}`, Date.now(), 'EX', 60)
}

async function isOnline(userId: string) {
  return (await redis.exists(`presence:${userId}`)) === 1
}
```

For displays of "5 people viewing this document," use a Redis sorted set keyed by document ID, with user IDs as members and timestamps as scores. Periodically prune entries older than 60s.

## Notifications

### Server-Initiated

- **In-app**: push via the user's open SSE/WebSocket connection. Fall back to "unread count" on next page load.
- **Email**: queue a background job; never block on the SMTP call.
- **Push (web/mobile)**: Firebase Cloud Messaging, Apple Push Notification service, or Web Push API for browsers.
- **SMS / WhatsApp**: Twilio, Africa's Talking. Expensive; reserve for high-value notifications.

### Delivery Semantics

Notifications are **at-least-once** by default. Make the client side dedupe by ID. Store delivered notifications per user with a unique ID so retries don't show twice.

### User Preferences

For every notification type, let users:

- Opt in/out per channel (email, push, SMS).
- Set quiet hours.
- Unsubscribe with one click.

Honor unsubscribe immediately. No "confirm" step.

## Connection Recovery

Real-time connections drop. Plan for it.

### Token Refresh

If using JWT for WebSocket auth and tokens are short-lived, refresh before they expire:

```ts
setTimeout(() => {
  ws.send(JSON.stringify({ type: 'refresh-auth', token: newToken }))
}, accessTokenLifetimeMs - 60_000)
```

Or close the socket on token expiry and let the reconnect logic re-auth.

### Catch-Up on Reconnect

After reconnecting, the client may have missed events. Two strategies:

- **Resume by ID**: client sends "I last saw event 42"; server replays events since then. Requires a durable event log.
- **Resync state**: client refetches current state, ignores the gap. Simpler. Works for state-rather-than-event clients (dashboards).

Pick the right one per feature. Resync for dashboards, resume for chat.

### Backoff with Jitter

```ts
function backoff(attempt: number) {
  const base = Math.min(30_000, 1000 * 2 ** attempt)
  return base * (0.5 + Math.random())
}
```

Without jitter, every client reconnects at the same instant after an outage — DDoS-ing your own recovery.

## Common Mistakes

- **WebSockets when SSE would do.** SSE is simpler, proxies handle it better, browser reconnects for free.
- **No heartbeats.** Proxies close idle connections; clients think they're connected and silently lose updates.
- **Authenticating after the upgrade.** Resources are already allocated. Auth in the upgrade handler.
- **Polling in the background tab at 1s intervals.** Battery dies, mobile data depleted. Pause on `visibilitychange`.
- **Querying the DB per connected client per tick.** Doesn't scale. Cache aggregates in Redis; push from there.
- **Streaming raw event after raw event** to a dashboard. Re-render storm. Batch server-side.
- **No reconnect logic.** First wifi blip and the user has to refresh.
- **Reconnects without jitter.** Thundering herd takes down recovery.
- **Notifications without unique IDs.** Retries show duplicates. Always dedupe client-side.
- **Email/SMS sent synchronously from the request handler.** Slow SMTP makes /signup take 4 seconds. Queue it.
- **No SSE/WebSocket fallback for restrictive networks.** Hotel wifi, corporate proxies. Polling fallback or Socket.IO.
- **Presence based on last login timestamp.** Users marked "online" who left hours ago. Use a TTL key.
- **Trusting `Sec-WebSocket-Protocol` or message-level auth.** Authenticate the connection, then trust the user ID server-side.
- **Sending sensitive data to all subscribers of a topic.** Scope by user/room on the server side, never filter on the client.
- **Forgetting to clean up listeners on `req.on('close')`.** Memory leak, eventually crashes the process.
