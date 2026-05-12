# Onboarding & Product Tours

How to help new users get from "signed up" to "got value" without holding their hand to death. Read before adding any "Welcome!" modal or interactive tour.

## Decision Tree

| User confused about | Use |
|---|---|
| What the product even does | **Empty states** that teach + first-screen tutorial |
| Where to find a specific feature | **Tooltips on hover/focus** of the relevant element |
| How a flow works (multi-step) | **Step-by-step tour** (React Joyride / Driver.js / Shepherd) |
| Whether they've set up the basics | **Checklist** (visible until completed) |
| Adopting a new feature post-launch | **Spotlight tooltip** anchored to the new control |

Tours are a heavy intervention. **Empty states and good defaults solve more problems with less friction.** Reach for tours when an empty state and tooltip can't carry the load.

## Empty States That Teach

A good empty state explains the value and offers the action. A bad one says "No data."

```tsx
function EmptyMachines() {
  return (
    <div className="text-center py-16">
      <MachineIcon className="size-12 mx-auto text-muted-foreground" />
      <h2 className="mt-4 text-lg font-semibold">No machines yet</h2>
      <p className="mt-2 text-muted-foreground max-w-md mx-auto">
        Operators register machines so customers can find them. Add your first machine to start tracking inventory and orders.
      </p>
      <Button className="mt-6" onClick={() => router.push('/machines/new')}>
        Add a machine
      </Button>
      <a className="block mt-3 text-sm text-primary" href="/docs/machines">
        Learn how it works
      </a>
    </div>
  )
}
```

### Pattern

- **Icon** — visual anchor.
- **One-line headline** — what's missing or what the user can do.
- **Short description** — why they'd want to do it.
- **Primary action button** — the most likely next step.
- **Secondary link** — learn more, watch a video.

Empty states are the cheapest, most-read documentation in your app. Invest in them.

## First-Run Detection

```ts
function useFirstRun() {
  const [seen, setSeen] = useState(() => Boolean(localStorage.getItem('onboarding.seen')))
  const markSeen = () => {
    localStorage.setItem('onboarding.seen', '1')
    setSeen(true)
  }
  return { isFirstRun: !seen, markSeen }
}
```

Server-side is more durable for paid products:

```prisma
model User {
  id                String   @id
  onboardingState   Json     @default("{}") @map("onboarding_state")
  // {"tour:dashboard": "completed", "checklist:setup": ["add-machine"]}
}
```

Two reasons to track server-side:

- Survives device switches and clearing browser data.
- Lets you re-trigger tours for users who joined before a tour existed.

## React Joyride (Tour Library)

```bash
npm install react-joyride
```

```tsx
import Joyride, { type Step } from 'react-joyride'

const steps: Step[] = [
  {
    target: '[data-tour="search-bar"]',
    content: 'Search for machines anywhere in your area.',
    disableBeacon: true,
  },
  {
    target: '[data-tour="map-view"]',
    content: 'Switch between map and list views.',
  },
  {
    target: '[data-tour="radius-filter"]',
    content: 'Adjust the radius to widen or narrow your search.',
  },
]

function MapTour() {
  const { isFirstRun, markSeen } = useFirstRun()

  return (
    <Joyride
      steps={steps}
      run={isFirstRun}
      continuous
      showProgress
      showSkipButton
      callback={({ status }) => {
        if (['finished', 'skipped'].includes(status)) markSeen()
      }}
      styles={{ options: { primaryColor: 'hsl(var(--primary))' } }}
    />
  )
}
```

### Rules

- **Anchor with `data-tour`** attributes, not class names or CSS selectors that might change. Stable, intentional.
- **Skip button always.** Users who don't want a tour shouldn't be forced.
- **3–5 steps max.** Past that, users zone out.
- **One tour per surface.** If a feature has 3 sub-pages, run a single coherent tour across them or tour each independently.
- **Don't auto-start tours after the first run.** Surface a "Tour" button in settings or help for return visits.

### Alternatives

- **Driver.js** — lightweight, framework-agnostic.
- **Shepherd.js** — popular, mature, more styling options.
- **Intro.js** — classic, the OG.
- **Onborda** — modern Next.js / React-first.

All similar in capability. Pick by API taste.

## Tooltip-Based Guidance

For ambient help, use tooltips bound to UI elements. Less invasive than tours.

```tsx
import { Tooltip } from '@base-ui-components/react/tooltip'

<Tooltip.Root>
  <Tooltip.Trigger render={<button aria-label="Help">?</button>} />
  <Tooltip.Popup>
    Click here to register a new machine.
  </Tooltip.Popup>
</Tooltip.Root>
```

For "new feature" highlights, a **spotlight tooltip** can pulse next to a control:

```tsx
{showSpotlight && (
  <div className="absolute -top-2 -right-2 size-3 bg-primary rounded-full animate-pulse">
    <span className="sr-only">New feature</span>
  </div>
)}
```

Dismiss permanently after first click of the feature.

## Onboarding Checklist

For products with a multi-step setup, surface the steps as a visible checklist:

```tsx
type Step = { id: string; label: string; done: boolean; href: string }

function OnboardingChecklist({ steps }: { steps: Step[] }) {
  const remaining = steps.filter((s) => !s.done).length
  if (remaining === 0) return null

  return (
    <Card className="sticky bottom-4 right-4 max-w-sm">
      <CardHeader>
        <CardTitle>Get started ({steps.filter((s) => s.done).length}/{steps.length})</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        {steps.map((s) => (
          <Link key={s.id} to={s.href} className="flex items-center gap-2">
            <Checkbox checked={s.done} disabled />
            <span className={s.done ? 'line-through text-muted-foreground' : ''}>{s.label}</span>
          </Link>
        ))}
      </CardContent>
    </Card>
  )
}
```

### Rules

- **3–7 steps** in the checklist. More feels overwhelming.
- **Order by dependency**: each step unblocks the next.
- **Persist state across sessions** (server-side preferred for paid products).
- **Dismissible** — power users completing manually shouldn't see it forever.
- **Disappears on completion** — auto-collapse or remove.
- **Resumable** — picks up where the user left off.

Examples of good first-checklist items:

- "Verify your email."
- "Add your first machine."
- "Invite a teammate."
- "Connect Stripe."

## Progressive Disclosure

Don't show every feature on day one. Reveal as users progress.

```ts
const canAccessAdvanced = user.onboardingState['basics'] === 'complete'

{canAccessAdvanced && <AdvancedSettings />}
```

Or feature-flag-style:

```ts
const showFeature = (id: string) => userMilestones.includes(id) || isAdmin
```

Examples:

- Don't surface API keys until the user has used the UI for a week.
- Hide bulk actions until they have 10+ items.
- Defer advanced reporting until the first export.

Users who feel mastery want more; users who feel overwhelmed leave. Tune the unlock cadence to confidence, not to time.

## Aha Moments

The **aha moment** is when a user first feels the product's value. Track it.

For a vending app: "I found a machine and got water." That's the moment. Measure:

- Time from signup → first order.
- Drop-off between signup and aha.

Onboarding's goal is to compress this distance. Cut any step that doesn't directly serve it.

### Onboarding Metrics

- **D1 retention** — % of users returning the day after signup.
- **Time to value** — seconds/minutes from signup to first action that delivers value.
- **Activation rate** — % completing the core action.
- **Checklist completion rate** — per step.

Tour-specific:

- **Tour completion rate** — what % finish vs skip.
- **Per-step drop-off** — where users abandon.

If a step has 60% drop-off, it's either confusing or unnecessary. Cut or fix.

## Re-onboarding for New Features

When you launch something significant for existing users:

- **In-app announcement** (modal or banner) — once, dismissible.
- **Tooltip on the new control** — pulses until first use.
- **Optional re-tour** — for users who want a refresher.

Don't ambush returning users with a 6-step tour. They're back to do work, not read.

## Accessibility

- **Tour skipping** — Escape key always works.
- **Focus management** — when the tour advances, move focus to the next target.
- **Screen reader announcements** — describe each step's anchor and instruction.
- **Don't trap focus** without an escape.
- **Visual focus indicators** on tour targets — high contrast, animated outline.

Tour libraries vary widely on accessibility. Test with VoiceOver / NVDA before launch.

## Common Mistakes

- **Tour on first login that the user can't skip.** Hostile. Always show skip.
- **8-step tour covering "the whole product."** Users zone out by step 3. Cut to the essential 3.
- **Tour anchored to CSS classes that change with the next CSS refactor.** Use stable `data-tour` attributes.
- **No analytics on tour completion.** Can't tell if it's helping.
- **Re-running the tour on every visit.** Once is plenty; surface a manual button after that.
- **Empty state that says "No data" with no action.** Wasted teaching opportunity.
- **Checklist with 12 items.** Overwhelms. Cut to 3–7 essential steps.
- **Checklist that's not resumable.** Loses progress on refresh.
- **Modal popup on first login that explains 5 things.** Read by nobody. Use in-context tooltips instead.
- **"New!" badges that never go away.** Eventually banners that are "new" become wallpaper. Dismiss per user.
- **Tracking onboarding state in localStorage only.** Lost on device switch; user re-sees the tour.
- **Tour can't be triggered manually.** New employees, returning users have no way to see it.
- **No skip on the spotlight.** Pulse indicator can't be dismissed by users who don't care.
- **Aha moment measured in vanity metrics.** "Signed up" is not aha; "got value" is. Measure that.
- **No re-onboarding when shipping a major feature.** Existing users never discover it.
