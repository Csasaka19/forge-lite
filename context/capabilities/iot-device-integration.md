# IoT Device Integration

How to ingest telemetry from devices, send commands, and visualize state in real time. Read before connecting any sensor, vending machine, beacon, or embedded controller.

## Decision Tree

| Need | Pick |
|---|---|
| Many devices, low-bandwidth telemetry | **MQTT** broker (HiveMQ, Mosquitto, AWS IoT Core) |
| Hosted, batteries-included | **AWS IoT Core**, **Azure IoT Hub**, **GCP IoT Core (deprecated — use Pub/Sub)** |
| Self-host, lightweight | **EMQX** or **Mosquitto** |
| Real-time dashboards | **MQTT → backend → WebSocket/SSE → client** |
| Time-series storage | **TimescaleDB** (Postgres extension) or **InfluxDB** |
| Aggregations at scale | **ClickHouse** or **BigQuery** |
| Commands to device | **MQTT subscribe topic** per device |

For new projects, **MQTT + TimescaleDB + a managed broker (HiveMQ Cloud or AWS IoT)**.

## MQTT Basics

Lightweight pub/sub protocol designed for unreliable networks (sensors, mobile, embedded).

- **Broker** — central server (HiveMQ, Mosquitto). Devices and apps connect to it.
- **Topics** — hierarchical strings: `devices/<deviceId>/telemetry`, `devices/<deviceId>/commands`.
- **QoS levels**: 0 (at-most-once), 1 (at-least-once), 2 (exactly-once). Use 1 by default.
- **Retained messages** — last value on a topic is delivered to new subscribers (great for "current state").
- **Last Will and Testament (LWT)** — broker publishes a "device offline" message if the connection drops.

## Topic Design

```
devices/<deviceId>/telemetry/<sensorType>     # device → server
devices/<deviceId>/status                     # device → server (retained, with LWT)
devices/<deviceId>/commands/<action>          # server → device
devices/<deviceId>/commands/<action>/response # device → server
```

### Rules

- **Hierarchical, not flat.** Enables wildcard subscribes (`devices/+/telemetry/#`).
- **Include device ID early.** Authorization and routing are easier.
- **One concern per topic.** Don't squash telemetry, commands, and ack into one stream.
- **Avoid `$SYS` and other broker-reserved prefixes.**

## Node Client

```bash
npm install mqtt
```

```ts
import mqtt from 'mqtt'

const client = mqtt.connect(env.MQTT_URL, {
  username: env.MQTT_USERNAME,
  password: env.MQTT_PASSWORD,
  clientId: `backend-${process.pid}`,
  clean: false,
  reconnectPeriod: 5000,
  keepalive: 30,
})

client.on('connect', () => {
  client.subscribe('devices/+/telemetry/#', { qos: 1 })
})

client.on('message', async (topic, payload) => {
  const [, deviceId, , sensorType] = topic.split('/')
  const data = JSON.parse(payload.toString())
  await ingest({ deviceId, sensorType, value: data.value, ts: data.ts })
})
```

`clean: false` + a stable `clientId` means the broker queues messages for you while disconnected.

## Telemetry Ingestion

Devices publish on `devices/<id>/telemetry/<type>`. The backend subscribes with a wildcard and writes to storage.

### Pattern

```ts
async function ingest({ deviceId, sensorType, value, ts }: Telemetry) {
  await prisma.$executeRaw`
    INSERT INTO telemetry (device_id, sensor_type, value, ts)
    VALUES (${deviceId}, ${sensorType}, ${value}, to_timestamp(${ts / 1000}))
  `
}
```

### Rules

- **Validate at the edge.** Drop messages with bad shapes — never trust device payloads.
- **Batch inserts** — buffer N messages or N ms and bulk-insert. Per-message inserts crush Postgres.
- **Idempotent**: include a sequence number or timestamp; reject duplicates on (device, ts).
- **Backpressure**: if storage falls behind, drop oldest or push to a queue. Don't let the broker buffer indefinitely.

### Buffered Writes

```ts
const buffer: Telemetry[] = []
let flushTimer: NodeJS.Timeout | null = null

function enqueue(t: Telemetry) {
  buffer.push(t)
  if (buffer.length >= 1000) flush()
  else if (!flushTimer) flushTimer = setTimeout(flush, 500)
}

async function flush() {
  if (buffer.length === 0) return
  const batch = buffer.splice(0, buffer.length)
  flushTimer = null
  await prisma.telemetry.createMany({ data: batch, skipDuplicates: true })
}
```

## Time-Series Storage

### TimescaleDB

Postgres extension. Use it if you're already on Postgres.

```sql
CREATE EXTENSION IF NOT EXISTS timescaledb;

CREATE TABLE telemetry (
  device_id   TEXT NOT NULL,
  sensor_type TEXT NOT NULL,
  value       DOUBLE PRECISION NOT NULL,
  ts          TIMESTAMPTZ NOT NULL
);

SELECT create_hypertable('telemetry', 'ts');
CREATE INDEX ON telemetry (device_id, ts DESC);
```

### Continuous Aggregates

For "show me the last 24h average per device":

```sql
CREATE MATERIALIZED VIEW telemetry_hourly
WITH (timescaledb.continuous) AS
SELECT device_id, sensor_type,
       time_bucket('1 hour', ts) AS bucket,
       avg(value) AS avg, max(value) AS max, min(value) AS min
FROM telemetry
GROUP BY device_id, sensor_type, bucket;

SELECT add_continuous_aggregate_policy('telemetry_hourly',
  start_offset => INTERVAL '1 day',
  end_offset => INTERVAL '5 minutes',
  schedule_interval => INTERVAL '5 minutes'
);
```

Pre-aggregated buckets keep dashboard queries fast.

### Retention

```sql
SELECT add_retention_policy('telemetry', INTERVAL '90 days');
```

Raw data 90 days; aggregates kept longer.

### InfluxDB

Purpose-built time-series DB. Better for very high cardinality. Trade-off: another system to operate. Pick TimescaleDB unless you have InfluxDB-specific needs.

## Real-Time Dashboards

Push live updates to dashboards via SSE or WebSocket — don't have the browser subscribe directly to MQTT.

```
Device → MQTT Broker → Backend Worker → Redis Pub/Sub → SSE / WS → Browser
```

### Why Not Direct MQTT in the Browser

- Auth surface — broker credentials in the browser are messy.
- Topic-level authorization per user is hard.
- Browsers don't speak raw MQTT — only MQTT-over-WebSocket.
- Backend filters and aggregates before pushing.

If you do want browser MQTT (kiosk dashboards, internal tools), use **MQTT.js** over WebSocket with short-lived tokens.

### Throttling

```ts
const buckets = new Map<string, { latest: any; timer: NodeJS.Timeout | null }>()

function pushUpdate(deviceId: string, data: any) {
  let b = buckets.get(deviceId)
  if (!b) buckets.set(deviceId, b = { latest: data, timer: null })
  else b.latest = data

  if (!b.timer) {
    b.timer = setTimeout(() => {
      sse.broadcast(`device:${deviceId}`, b!.latest)
      b!.timer = null
    }, 250)
  }
}
```

Dashboards don't need 100 updates/second per device. 4 updates/second is plenty for smooth motion.

## Device Management

### Status

Devices publish status with `retain: true` and LWT:

```ts
// Device-side (TypeScript-ish, would be C/embedded in reality)
client.publish('devices/abc/status', JSON.stringify({ state: 'online' }), { retain: true, qos: 1 })

// LWT set at connect:
will: {
  topic: 'devices/abc/status',
  payload: JSON.stringify({ state: 'offline' }),
  retain: true,
  qos: 1,
}
```

Backend subscribes to `devices/+/status` and updates the DB. Retained messages mean a fresh subscriber learns current state immediately.

### Commands

Server publishes:

```ts
await mqttClient.publish(
  `devices/${id}/commands/restart`,
  JSON.stringify({ requestId: crypto.randomUUID(), at: Date.now() }),
  { qos: 1 },
)
```

Device subscribes to its commands topic, executes, publishes ack to `commands/restart/response`.

Track command status server-side with the `requestId`:

```prisma
model DeviceCommand {
  id         String   @id @default(uuid())
  deviceId   String
  action     String
  status     String   // 'pending' | 'sent' | 'acked' | 'failed' | 'timeout'
  sentAt     DateTime
  ackedAt    DateTime?
  payload    Json
}
```

Time out commands the device doesn't ack within N seconds. Alert if a device starts missing acks.

## Offline Device Handling

Devices on flaky networks need:

- **MQTT `keepalive`** — 30–60 seconds. Lower = quicker offline detection; higher = less battery / bandwidth.
- **Local buffering on the device** — when offline, queue telemetry; flush on reconnect.
- **Server-side gap detection** — if no telemetry arrives for N minutes, flag the device.
- **Reconnect with backoff + jitter** on the device side, same as web clients.

### Backfill

When a device reconnects after hours offline, it may send a flood of buffered telemetry. Backend should:

- Accept it with timestamps as-is, **not "now."**
- De-dupe on (device, sensor_type, ts).
- Throttle ingest so a reconnecting flock doesn't overwhelm storage.

## Security

- **TLS only** (`mqtts://`). Plaintext MQTT leaks credentials and data.
- **Per-device credentials.** Never one shared username/password — compromise of one device shouldn't equal compromise of all.
- **Topic-level ACLs** on the broker. Device `abc` can only publish to `devices/abc/#` and subscribe to `devices/abc/commands/#`.
- **Rotate credentials** when a device is decommissioned or stolen.
- **Sign or encrypt sensitive payloads** end-to-end if the broker itself isn't trusted.

## Common Mistakes

- **Browser subscribes directly to MQTT broker.** Auth and topic-scoping nightmare. Backend filters and pushes.
- **One shared MQTT credential** for all devices. One leak = total breach.
- **No QoS specified.** Default QoS 0 loses messages. Use QoS 1 for telemetry.
- **`retain: false` on status topics.** New subscribers don't see current state until the next publish.
- **No LWT.** Device drops; backend doesn't notice. Always set LWT.
- **Per-row inserts** for high-volume telemetry. Postgres melts. Batch.
- **Trusting device timestamps with no sanity check.** Devices have wrong clocks. Reject far-future / far-past timestamps; consider server-side timestamping.
- **Direct dashboard updates per message.** Browser drowns. Throttle server-side.
- **No retention policy on telemetry.** Storage grows forever.
- **Same `clientId`** used by two clients. Broker disconnects one. Always unique.
- **`clean: true` for the backend.** Misses messages during reconnect. Use `clean: false` with a stable client ID.
- **MQTT over plaintext on a public network.** Use TLS.
- **Commands without ack handling.** Send-and-pray. Track request IDs and timeouts.
- **No backfill protection.** Flock reconnects, ingest pipeline collapses.
- **Telemetry payload that's a long string.** Use compact JSON; smaller wire format. CBOR for very constrained devices.
