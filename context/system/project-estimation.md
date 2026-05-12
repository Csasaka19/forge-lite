# Project Estimation & Planning

How to scope, estimate, and ship on time. Read before writing a roadmap, breaking down a feature, or committing to a date.

## Decision Tree: How Much Planning

| Situation | Approach |
|---|---|
| One-day spike, exploring a tech | **No estimate.** Time-box. |
| 1–2 week feature, one engineer | **Hour-level breakdown** into tasks < 4 hours |
| 1–2 month initiative, multi-engineer | **T-shirt sizing** + milestones + risk plan |
| Quarter-plus roadmap | **T-shirt sizes** only. Re-estimate at the milestone boundary. |
| Hard external deadline | **Reverse-plan from the date** — what falls off the scope? |

Over-planning small work wastes time. Under-planning large work ships late. Match the planning depth to the commitment.

## Feature Decomposition

The unit of work is a task that one person can finish in **under 4 hours**. Anything bigger is a project; anything smaller is busywork.

### Method

1. **Write the user-visible outcome first.** "Customer can filter machines by radius."
2. **List the API contract changes.** New endpoint, new param, new response field.
3. **List the database changes.** New column, new index, new table.
4. **List the UI changes.** New component, new state, new route.
5. **For each, write tasks under 4 hours.**

```
Feature: Radius filter on machine map

Backend
- [ ] Add `radius_km` query param to GET /machines (parse, default 10)        (1h)
- [ ] Filter results by haversine distance from `near` coords                  (2h)
- [ ] Update OpenAPI spec with new param + example                             (30m)

Frontend
- [ ] Add radius selector component (10/25/50/200 km)                          (1h)
- [ ] Wire selector to URL state (?radius=)                                    (30m)
- [ ] Pass radius to API client + invalidate query on change                   (1h)
- [ ] Empty-state copy when no machines in radius                              (30m)
- [ ] Manual test on slow 3G + permission-denied path                          (1h)

Tests
- [ ] API: radius parsing + boundary cases                                     (1h)
- [ ] Component: selector renders + emits change                               (30m)
```

Total estimated: ~9 hours. One engineer, 2–3 days.

### Rules

- **Tasks have a verifiable outcome.** "Done" is testable, not "in progress."
- **Tasks under 4 hours are believable.** Past that, estimation accuracy collapses.
- **List the boring tasks.** Documentation, test data, deploy steps. They add up.
- **Don't decompose features you haven't designed.** Estimating an undefined feature produces fiction.

## Estimation Techniques

Pick by the time horizon.

### T-Shirt Sizing (Roadmap)

For quarter-plus planning, when details are fuzzy.

| Size | Rough effort | Examples |
|---|---|---|
| **XS** | < 1 day | Copy change, small bug fix |
| **S** | 1–3 days | Single endpoint, single component |
| **M** | 1–2 weeks | A coherent feature with backend + frontend |
| **L** | 3–6 weeks | A new section of the product |
| **XL** | 2+ months | A major surface or capability |

T-shirts compare; they don't sum precisely. Use them for "what fits in this quarter," not "ship date is March 14."

### Hour Estimates (Sprint)

For 2-week sprints, break Ms into hour-level tasks (above). Sum them. Multiply by **1.5×** for unknowns — review cycles, integration debugging, environment issues. This buffer is not slop; it's the actual cost of shipping.

### Reference Class Forecasting

Instead of estimating from imagination, **find a similar past project** and adjust. "We built the operator dashboard in 5 weeks. The admin dashboard is similar with two extra tables; call it 6 weeks."

Reference class beats inside-view estimation by a wide margin. Maintain a small log of "feature → actual time" to draw from.

### Three-Point Estimates

For risky work, estimate best/typical/worst case and use a weighted average:

```
estimate = (best + 4 × typical + worst) / 6
```

A feature with best=3d / typical=5d / worst=15d → ~5.7 days, with the worst case dragging the estimate up rightly.

## Velocity Tracking

Track **estimated hours vs actual hours per sprint**. Plot the trend.

| Sprint | Planned | Completed | Carry-over |
|---|---|---|---|
| 12 | 80h | 64h | 16h |
| 13 | 80h | 72h | 8h |
| 14 | 80h | 88h (incl. carry) | 0h |

Patterns to watch:

- **Consistent over-estimation by 30%+** — you're padding. Trust your numbers more.
- **Consistent under-estimation by 30%+** — you're optimistic. Apply a multiplier next sprint.
- **High variance** — feature breakdowns aren't fine-grained enough.

Velocity is for **calibration**, not for performance review. Engineers gaming velocity is a worse outcome than missing a date.

## MVP Scoping

The MVP is the smallest thing that lets you learn whether the idea works.

### Identify the Riskiest Assumption

The MVP exists to test that assumption. If it's "users will find machines on a map," the MVP is the map. If it's "users will pay," the MVP is the payment flow with a hand-coded backend.

### Cut Mercilessly

Three categories of work, only one is in scope for the MVP:

- **Core** — without this, the assumption can't be tested. Ship.
- **Quality** — needed for a public launch but not for an experiment. Defer.
- **Optimization** — nice-to-have, performance-tuning, edge cases. Defer.

If you're not embarrassed by the first version, you launched too late.

### MVP Anti-Patterns

- **Building auth, billing, and admin before there's a feature worth using.** Yak shaving.
- **"We need it polished before showing it to users."** Polish is for things that already work; an unpolished MVP is faster feedback.
- **Generalizing to all users on day one.** Pick one user, one use case, one path. Expand later.

## Risk Identification

Most projects fail in predictable ways. Name the failure modes before you start.

### Pre-Mortem

Before kickoff, ask the team: "It's three months from now and we shipped late and broken. Why?" Brainstorm honestly.

Typical risks:

- **Unknown integration** — a third-party API behaves weirdly.
- **Data quality** — production data has shapes the schema doesn't anticipate.
- **Scope creep** — stakeholders add requirements mid-build.
- **Single point of knowledge** — one engineer knows the legacy system; they leave.
- **Performance under load** — works for 10 users, dies at 10,000.
- **Browser/device coverage** — works on Chrome, broken on Safari.

### De-Risk First

Order the work so the riskiest unknown gets resolved earliest. If the integration might not work, build a thin slice that exercises it in week one — not week eight.

This sometimes means doing the "hardest" thing first, not the "easiest." That's the point.

## Milestone Planning

Break the project into **2-week milestones** with binary pass/fail criteria.

```
Milestone 1 (Week 1–2): Operator can log in and view their machines.
Pass criteria: One operator account can log in via the new UI, see their
3 assigned machines, and the list matches what's in the database.

Milestone 2 (Week 3–4): Operator can mark a machine for maintenance.
Pass criteria: Status updates persist, customers see "under maintenance"
on the map within 30s.

Milestone 3 (Week 5–6): Operator dashboard shows last 7 days of orders.
Pass criteria: Chart renders, totals match the DB, mobile layout works.
```

### Rules

- **Binary pass/fail.** "Mostly working" is failure. Either the criteria are met or they aren't.
- **Demo at each checkpoint.** To stakeholders, ideally to real users.
- **Replan after each milestone.** Estimates that were guesses become facts; update the plan.
- **Cut, don't slip.** If you're behind, cut scope from the next milestone, not the date.

## Technical Debt Budget

Reserve **20% of every sprint for technical debt** — refactoring, dependency updates, test improvements, documentation, dev-tool fixes.

Without an explicit budget, debt accumulates until it grinds a team to a halt. With the budget, debt stays manageable.

### What Counts as Debt

- Refactoring code paid down before the next feature touches it.
- Upgrading dependencies behind their major versions.
- Increasing test coverage on critical paths.
- Improving build/deploy speed.
- Documenting an undocumented system.

What doesn't count:

- New features dressed as "refactors."
- Cleanup nobody asked for, on code that's stable.
- Aesthetic preferences with no measurable benefit.

### Tracking

Tag debt tickets distinctly. Review monthly: are we paying it down, or just naming it?

## Communication Cadence

### Daily Standup (15 min)

Three questions per person:

1. What I shipped yesterday (linked PR/ticket).
2. What I'm working on today.
3. What's blocking me.

Rules:

- **15 minutes hard cap.** If a topic needs longer, take it offline.
- **Blockers get owners and follow-ups**, not just acknowledgment.
- **Skip standup on quiet days.** Async update in chat works.

### Weekly Status

```
Week of 2026-05-11

Shipped
- Operator dashboard MVP (PR #142)
- Radius filter on machine map (PR #145)

In flight
- Order confirmation page — 70%, blocked on Stripe webhook signature setup

Risks / blockers
- Daraja sandbox returning intermittent 500s; opened ticket with Safaricom
- Need design review on the operator notification UX by Wed

Next week
- Finish order confirmation
- Start admin user management
```

Send to the team channel. Stakeholders pull it; you don't push it to everyone.

### Blocker Escalation

A blocker is anything you can't unblock yourself within a day.

1. **Hour 1**: try to unblock alone.
2. **Hour 4**: ask the team in chat.
3. **End of day**: escalate to your manager or DRI.
4. **Day 2**: it should not still be blocking you.

Silent suffering is the most expensive blocker pattern.

## Definition of Done

A task is done when **all** of these are true. Adapt per project but write it down.

```
Definition of Done (Feature)

Code
- [ ] Implementation merged to main
- [ ] No new lint errors
- [ ] TypeScript passes with no `any`
- [ ] Unit/integration tests written and passing
- [ ] Manual test on the golden path + 1 edge case
- [ ] Code reviewed and approved by at least 1 teammate

Deploy
- [ ] Shipped to staging
- [ ] Smoke-tested on staging
- [ ] Feature flag gated (if risky)
- [ ] Shipped to production

Documentation
- [ ] Changelog entry
- [ ] README/docs updated if user-visible commands changed
- [ ] Demo recorded or screenshot in the PR

Observability
- [ ] Logs at appropriate levels
- [ ] Metrics dashboard updated if SLO-relevant
- [ ] Alerts configured if production-critical
```

"Done" without this checklist means "shipped to staging and forgotten."

## Common Mistakes

- **Estimating to please.** Optimistic estimates produce missed dates. Estimate to be honest.
- **No buffer.** 8 hours of work in 8 hours of estimate ships late every time. Multiply by 1.5×.
- **Tasks over 4 hours.** "Build the dashboard, 3 days." Doesn't expose the unknowns. Decompose further.
- **No reference class.** Estimating from scratch every time. Keep a log of actuals.
- **Velocity weaponized.** Engineers inflate estimates so velocity looks good. Velocity is for calibration only.
- **MVP that includes auth + billing + admin.** Ship the feature first; ship the supporting cast later.
- **De-risking last.** Spending 6 weeks on the easy stuff, then the third-party integration doesn't work.
- **Milestones with no demo.** Stakeholders surprised at week 8. Demo every 2 weeks.
- **Slipping instead of cutting.** "We'll catch up next sprint." You won't. Cut scope.
- **No tech debt budget.** Debt grows; six months later, every feature takes twice as long.
- **Daily standup turning into design discussion.** Move it offline. Keep standup short.
- **No definition of done.** "Shipped" means different things to different people. Write it down.
- **Estimating a feature that hasn't been designed.** Fiction. Design first, then estimate.
- **Single-engineer bus factor.** "Only Sara knows the auth service." Pair, document, rotate.
- **Reverse-planning by squeezing.** The date is the date; scope is the variable. Squeeze produces failure, not delivery.
