# Feature Flags

How to ship code dark, roll out gradually, and run experiments. Read before merging a risky change behind an `if`.

## Decision Tree

| Need | Pick |
|---|---|
| One developer, < 5 flags | **Static JSON / env var** |
| Small team, < 50 flags, want a UI | **GrowthBook** (open-source) or **Unleash** (self-hosted) |
| Experiments, attribution, mature analytics | **LaunchDarkly**, **Statsig**, **Optimizely** |
| Cost matters more than features | **PostHog feature flags** (bundled with analytics) |

Never use a `git branch` as a long-lived feature flag. Flag in code, merge to main, decide later.

## Simple JSON Flags

For a small project, a config file is plenty.

```ts
// src/lib/flags.ts
import flagsJson from '../../config/flags.json'

type FlagName = keyof typeof flagsJson

interface Context {
  userId?: string
  tenantId?: string
}

export function isEnabled(flag: FlagName, ctx: Context = {}): boolean {
  const def = flagsJson[flag]
  if (typeof def === 'boolean') return def
  if (def.users?.includes(ctx.userId ?? '')) return true
  if (def.tenants?.includes(ctx.tenantId ?? '')) return true
  if (def.percentage) return hash(`${flag}:${ctx.userId}`) % 100 < def.percentage
  return false
}
```

```json
// config/flags.json
{
  "new-checkout": { "percentage": 10, "users": ["u_test_1"] },
  "operator-dashboard-v2": { "tenants": ["t_acme"] },
  "killswitch.search": true
}
```

Deploy to update flags. Doesn't scale, but works for a small project before you need a real service.

## GrowthBook (Open Source, Self-Host)

```bash
npm install @growthbook/growthbook-react
```

```tsx
import { GrowthBook, GrowthBookProvider, useFeatureIsOn } from '@growthbook/growthbook-react'

const gb = new GrowthBook({
  apiHost: env.GROWTHBOOK_API_HOST,
  clientKey: env.GROWTHBOOK_CLIENT_KEY,
  attributes: { id: user.id, tenantId: user.tenantId, plan: user.plan },
})

await gb.init()

<GrowthBookProvider growthbook={gb}>
  <App />
</GrowthBookProvider>

function CheckoutPage() {
  const newFlow = useFeatureIsOn('new-checkout')
  return newFlow ? <NewCheckout /> : <LegacyCheckout />
}
```

### Targeting

Configure in the GrowthBook UI:

- Percentage rollout per attribute.
- Specific user IDs / tenant IDs.
- Boolean expressions on attributes (`plan == 'enterprise' AND signup_date > '2026-01-01'`).
- Schedules (enable on a specific date).

Same evaluation on server and client — pass attributes consistently.

## LaunchDarkly (Hosted, Enterprise)

```ts
import { init } from '@launchdarkly/node-server-sdk'

const ld = init(env.LD_SDK_KEY)
await ld.waitForInitialization()

const ctx = { kind: 'user', key: user.id, tenantId: user.tenantId }
const enabled = await ld.variation('new-checkout', ctx, false)
```

Same model — context attributes drive the evaluation. UI handles rollouts, experiments, prerequisites between flags, segments.

LaunchDarkly is expensive. Worth it for teams running many experiments with attribution analytics. For pure on/off flags, GrowthBook or Unleash is plenty.

## Gradual Rollout

Standard cadence for a risky change:

```
Day 0   Enable for internal team (employee userIds).
Day 1   Enable for 1% of users. Watch error rates.
Day 2   10%. Watch latency, conversion.
Day 4   50%.
Day 7   100%.
Day 14  Remove the flag from code (PR), delete from the flag service.
```

Rules:

- **Watch the right metric.** Error rate, latency, conversion — define before the rollout.
- **Half-step at each level if metrics wobble.** Don't double down.
- **Kill switch ready.** A single boolean to revert. Test it before launching.
- **Roll by tenant for B2B**, not by user — splitting one tenant in half is confusing.

## A/B Testing

When the question isn't "does this work" but "which is better." Treat as a science experiment, not a permanent fork.

### Setup

```ts
const variant = await gb.evalFeature('checkout-button-color')
// returns { value: 'green' | 'blue' | 'red', source: 'experiment' }

track('checkout_started', { variant: variant.value })
```

Each user gets a stable assignment (hash of user ID + experiment ID). Track outcomes by variant.

### Rules

- **Define the hypothesis up front.** "Blue button increases checkout conversion by 5%."
- **Pre-register the metric and the duration.** No fishing for significant p-values.
- **Power your sample size.** Need a couple thousand events per variant minimum for most effects.
- **Don't peek and decide.** Wait until the planned end before calling a winner.
- **One experiment per page at a time.** Otherwise effects confound.

## Flag Types and Lifecycle

Flags decay. The dangerous flags are the old ones nobody remembers.

### Categories

- **Release flag** — ship dark, roll on, remove within 2 weeks.
- **Experiment flag** — A/B test, remove when concluded (1–4 weeks).
- **Operational flag** — kill switch for a dependency, performance toggle. May live indefinitely; document why.
- **Permission flag** — feature gating by plan/role. Lives as long as the feature does; use a real auth system, not a flag.

### Lifecycle Discipline

For every flag:

- **Owner** — a person, not a team.
- **Removal date** — even if it slips, the date keeps it on the radar.
- **Status** — alive, deprecated, kill-switch-only.

Review monthly. Any flag past its removal date gets a ticket.

## Stale Flag Cleanup

After rollout finishes:

1. **PR** removes the `if`, keeps only the winning branch.
2. **Delete** the flag in the management UI.
3. **Confirm** no code still references the flag name (grep).

```bash
# Lint rule or grep check in CI
git grep -l 'isEnabled.*old-flag-name' && exit 1 || exit 0
```

Tools that detect dead flags: **GrowthBook** has a "stale flags" report; **LaunchDarkly** has Code References. Use them.

## Server vs Client Evaluation

- **Server-side** — flag evaluated on the API, response is already the variant. Best for behavior that affects backend logic.
- **Client-side** — flag evaluated in the browser, conditionally renders. Best for UI variants.
- **Edge** — evaluated at the CDN (Cloudflare Workers, Vercel Edge Middleware). Combines low latency with personalization.

For privacy-sensitive flags (don't tell the client about variants they don't get), prefer server or edge.

## Common Mistakes

- **Long-lived branches as flags.** Merge to main, flag in code, decide later.
- **No owner per flag.** Nobody knows whether to remove it. Becomes permanent.
- **Flag rollout without monitoring.** Ship to 50%, regression invisible. Watch error rate and the success metric.
- **Hardcoded flag values in tests.** Tests pass with the flag on, break in prod when off. Test both branches.
- **Permission gating with a feature flag.** Use real authorization. Flags are for rollouts and experiments.
- **No kill switch.** Bad day, no fast revert. Always have one.
- **Flag dependencies — flag B requires flag A.** Hard to reason about. Flatten or use a flag service that supports prerequisites explicitly.
- **Reusing a flag name after removal.** Stored attribution data points at the new flag. Use a fresh name.
- **Peeking at A/B results daily and stopping early.** False positives. Pre-register and wait.
- **Same flag evaluated on both server and client with different attributes.** Inconsistent UX. Pass attributes the same way.
- **No fallback default.** Flag service down → flag returns undefined → app crashes. Always pass a default.
- **Flag changes deployed via flag service for a critical regression.** Service is unavailable, your kill switch doesn't fire. Have a code-level fallback for the most critical kill switches.
- **More than ~20 flags in one component.** Refactor; flags should be sparse decision points, not pervasive branching.
- **Forgetting to delete after rollout.** Three years later, 40% of the codebase is dead branches. Quarterly audit.
