# Accessibility (Deep)

How to build interfaces that work for everyone. Read before shipping any UI — accessibility is not a polish step, it's the foundation.

## Target: WCAG 2.2 AA

WCAG 2.2 Level AA is the legal floor in most jurisdictions (ADA in the US, EAA in the EU, AODA in Ontario) and the practical baseline for "we ship to humans."

- **A** — minimum (don't ship below this).
- **AA** — what you aim for. Required by most laws.
- **AAA** — aspirational, sometimes impractical (contrast 7:1, sign language for video).

If you can pass AA on every page and AAA on critical flows (signup, checkout, search), you're doing well.

## Decision Tree: How Deep to Go

| Surface | Target |
|---|---|
| Internal tool used by one team | Sane defaults: keyboard nav, labels, contrast |
| Public-facing app | **WCAG 2.2 AA** on every flow |
| Government, healthcare, education | **WCAG 2.2 AA** legally; AAA on critical flows |
| Marketing site | AA + careful with animation and contrast |

Accessibility is not "checked at the end." Bake it into the component library — every Button, Input, Modal, Card primitive built once with accessibility correct, used everywhere.

## Semantic HTML

The right element does most of the work. Custom elements + ARIA exist to fill gaps, not to replace built-ins.

### Element Choice

| Use | Don't use |
|---|---|
| `<button>` for actions | `<div onClick>` |
| `<a href>` for navigation | `<button>` that calls `router.push` for normal nav |
| `<nav>` for site navigation | `<div class="nav">` |
| `<main>` for primary content | unwrapped page content |
| `<h1>`–`<h6>` for headings, in order | styled `<div>` |
| `<ul>`/`<ol>` for lists | comma-separated `<span>`s |
| `<label for="x">` paired with `<input id="x">` | bare placeholder text |
| `<dialog>` or proper modal pattern | `<div class="modal">` |
| `<table>` for tabular data | divs styled as a grid |

### Headings

One `<h1>` per page, describing the page. `<h2>` for sections, `<h3>` for subsections. Never skip levels (`h2` → `h4`) — screen readers use headings to navigate.

```html
<h1>Find machines near you</h1>
<section>
  <h2>Filters</h2>
  <h3>Radius</h3>
  <h3>Status</h3>
</section>
<section>
  <h2>Results</h2>
</section>
```

### Buttons vs Links

- **Button** — does something on the same page (open a modal, submit a form, toggle state).
- **Link** — navigates to a new URL or anchor.

Right-click "Open in new tab" should work on links. It shouldn't apply to buttons. That's the test.

## Keyboard Navigation

Every interactive element must be reachable and operable by keyboard.

### Tab Order

- **Logical order** — top-to-bottom, left-to-right (or right-to-left in RTL).
- **Native interactive elements** (`<button>`, `<a>`, `<input>`, `<select>`, `<textarea>`) are tabbable by default. Don't break this.
- **Custom interactive elements** need `tabIndex={0}` and keyboard handlers.

```tsx
// If you absolutely must use a div as a button:
<div
  role="button"
  tabIndex={0}
  onClick={onAction}
  onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') onAction() }}
>
  Action
</div>
```

But the answer is almost always: use `<button>` instead.

### Don't Trap Focus (Except in Modals)

- **`tabIndex={-1}`** — focusable programmatically, not tabbable.
- **Negative tabindex other than -1** — broken, removed from spec.
- **Positive tabindex** — never. Always order in source instead.

### Focus Trapping in Modals

When a modal opens:

1. Move focus into the modal (usually the first focusable element).
2. Trap Tab and Shift+Tab inside the modal.
3. Escape closes the modal.
4. On close, return focus to the element that opened it.

Don't roll your own. Use:

- **Native `<dialog>`** with `showModal()` — Tab is trapped automatically.
- **`focus-trap-react`** for hand-rolled modals.
- **Radix UI / Base UI / Headless UI** — all handle trap correctly.

```tsx
import { Dialog } from '@base-ui-components/react/dialog'

<Dialog.Root open={open} onOpenChange={setOpen}>
  <Dialog.Backdrop />
  <Dialog.Popup>
    <Dialog.Title>Confirm action</Dialog.Title>
    {/* focus is trapped here; Escape closes */}
  </Dialog.Popup>
</Dialog.Root>
```

### Skip-to-Content Link

The first focusable element on every page should let keyboard users skip past navigation:

```tsx
<a
  href="#main"
  className="sr-only focus:not-sr-only focus:absolute focus:left-2 focus:top-2 focus:z-50 focus:bg-background focus:px-3 focus:py-2"
>
  Skip to main content
</a>
<main id="main" tabIndex={-1}>...</main>
```

Visible on focus, invisible otherwise. Critical for users tabbing through dozens of nav links.

### Visible Focus

**Never** `outline: none` without a replacement. The default focus ring is ugly but functional — if you replace it, make the new style at least as visible.

```css
:focus-visible {
  outline: 2px solid hsl(var(--ring));
  outline-offset: 2px;
}
```

`:focus-visible` shows the ring only when the user is navigating with keyboard, not on mouse click — best of both worlds.

## Screen Reader Testing

Automated tools catch ~30% of accessibility issues. The rest needs a screen reader.

### Tools by Platform

- **macOS**: **VoiceOver** (`Cmd+F5` to toggle). Works with Safari, partial in Chrome.
- **Windows**: **NVDA** (free, recommended) or **JAWS** (paid, used by many real users).
- **iOS**: **VoiceOver** (Settings → Accessibility → VoiceOver, or triple-click Home/Side).
- **Android**: **TalkBack** (Settings → Accessibility → TalkBack).

### Test on Each

Don't assume "VoiceOver works → screen readers work." NVDA and JAWS behave differently from VoiceOver, especially around ARIA live regions, table navigation, and modal interactions.

### Test Plan

For each major flow:

1. Turn off your monitor or close your eyes. Use only the screen reader.
2. Tab through the page. Are all interactive elements reachable?
3. Are they announced correctly? "Button, Search" not "Search" alone.
4. Submit a form. Are errors read out?
5. Open a modal. Does focus move? Can you escape?
6. Trigger a live update (toast, notification). Is it announced?

### Common Patterns

```tsx
// Announce dynamic changes
<div role="status" aria-live="polite">{message}</div>

// Critical alerts
<div role="alert" aria-live="assertive">{error}</div>

// Hide decorative content
<svg aria-hidden="true">...</svg>

// Visually hidden text for context
<button>
  <TrashIcon aria-hidden />
  <span className="sr-only">Delete order #{order.id}</span>
</button>
```

## Color Contrast

WCAG 2.2 AA contrast ratios:

- **Normal text (under 18pt / 14pt bold)**: **4.5:1**.
- **Large text (18pt+ or 14pt+ bold)**: **3:1**.
- **UI components and graphical objects** (icons, focus indicators, form borders): **3:1**.

### Tools

- **Browser DevTools** — the color picker in Chrome/Firefox shows contrast inline.
- **WebAIM Contrast Checker** — `webaim.org/resources/contrastchecker`.
- **Axe DevTools** — flags every contrast failure on the page.
- **Stark** — Figma/Sketch plugin, catches issues at design time.

### Test Both Themes

Light and dark theme must independently pass. A light theme tuned for AA can fail in dark mode if the same hue is used at a different lightness.

### Don't Rely on Color Alone

Never communicate state with color only:

- Error states: red **plus** an icon and text.
- Required fields: asterisk **plus** "required" text on focus.
- Chart series: color **plus** shape/pattern.

Color-blind users (~8% of men, ~0.5% of women) can't distinguish your green-vs-red status pills.

## ARIA Patterns

**First rule of ARIA: don't use ARIA if a native element does the job.** Wrong ARIA is worse than no ARIA.

### When to Use Which

- **`aria-label`** — labels an element when no visible text serves. Icon buttons.
- **`aria-labelledby`** — points to another element's text as the label.
- **`aria-describedby`** — points to supplementary description (helper text, error message).
- **`aria-expanded`** — for toggles that show/hide content (disclosures, dropdowns).
- **`aria-current`** — current page or step in a sequence. `aria-current="page"` on nav.
- **`aria-live`** — `"polite"` for non-critical updates, `"assertive"` for urgent.
- **`role="status"`** / **`role="alert"`** — shorthand for common live regions.

### Common Mistakes

- **`role="button"` on a `<button>`.** Redundant.
- **`aria-label` on visible text.** The visible text already labels it.
- **`aria-hidden="true"` on focusable elements.** Screen readers skip them, keyboard users still tab in — broken state.
- **`role` on the wrong element.** `<div role="navigation">` instead of `<nav>`.
- **Custom `role="dialog"` without focus management.** Half a dialog. Use a real dialog or a library.
- **`tabindex="0"` on `<div>` to "fix" keyboard access** — then forgetting Enter/Space handlers.

### Disclosure (Show / Hide)

```tsx
<button
  aria-expanded={open}
  aria-controls="advanced-filters"
  onClick={() => setOpen(!open)}
>
  Advanced filters
</button>
<div id="advanced-filters" hidden={!open}>
  ...
</div>
```

### Listbox / Combobox

For autocomplete inputs, follow the WAI-ARIA Authoring Practices pattern carefully — or use a library (Downshift, Radix Combobox, Headless UI). Hand-rolled comboboxes are a common accessibility minefield.

## Form Accessibility

### Labels

**Every input has a label.** Always. No exceptions.

```tsx
// Best — explicit label
<label htmlFor="email">Email</label>
<input id="email" type="email" name="email" />

// Acceptable — wrapped label
<label>
  Email
  <input type="email" name="email" />
</label>

// Last resort — visually hidden label (icon-only contexts)
<label htmlFor="search" className="sr-only">Search</label>
<input id="search" type="search" />
```

Placeholder is **not** a label. It disappears on input, fails contrast, and confuses screen readers.

### Error Messages

```tsx
<label htmlFor="email">Email</label>
<input
  id="email"
  type="email"
  aria-invalid={!!error}
  aria-describedby={error ? 'email-error' : undefined}
/>
{error && (
  <p id="email-error" role="alert" className="text-destructive">
    {error}
  </p>
)}
```

- **`aria-invalid`** marks the field as failing validation.
- **`aria-describedby`** points to the message so screen readers read it.
- **`role="alert"`** announces the error when it appears.

### Inline Validation

Validate **on blur**, not on every keystroke. Aggressive validation is hostile — show errors after the user has stopped typing.

For submit-only validation: focus the first invalid field and scroll it into view.

### Required Fields

```tsx
<label htmlFor="name">
  Name <span aria-hidden>*</span>
  <span className="sr-only">required</span>
</label>
<input id="name" name="name" required />
```

Visual asterisk for sighted users, "required" text for screen readers.

## Motion Sensitivity

Some users get nauseated by motion. `prefers-reduced-motion` is a system preference; honor it.

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

For JS-driven animation (Framer Motion, Reanimated):

```tsx
import { useReducedMotion } from 'framer-motion'

const reduce = useReducedMotion()
<motion.div animate={reduce ? {} : { x: 100 }} />
```

### Rules

- Parallax, large-area animation, autoplay video: respect the preference.
- Subtle UI feedback (button press, hover): usually fine to keep, just shorter.
- Loading spinners: smooth is fine; flashing is not. Avoid > 3 flashes per second always.

## Mobile Accessibility

### Touch Targets

**Minimum 44×44 CSS pixels** (Apple HIG, WCAG AAA 2.5.5). 48×48 (Material) is safer. Spacing of at least 8px between targets.

```tsx
<button className="size-11">      {/* 44px */}
  <Icon />
</button>
```

Tiny tap targets next to each other cause mis-taps; honor the spacing rule.

### Dynamic Type

Users set their preferred font size at the OS level. Apps must scale.

- **Web**: use `rem` for font sizes, not `px`. Browser font-size setting scales `rem` automatically.
- **React Native**: use the `allowFontScaling` prop (defaults to true). Test at 200% system size — does the layout break?

### Gesture Alternatives

Every gesture has a button equivalent:

- Swipe-to-delete → also a "Delete" button.
- Pinch-to-zoom on a map → also `+` / `−` controls.
- Long-press → also a context menu button.

Users with motor disabilities can't always perform precise gestures.

### Native Accessibility Props

```tsx
// React Native
<Pressable
  accessibilityLabel="Delete order"
  accessibilityHint="Removes the order from your list"
  accessibilityRole="button"
>
  <TrashIcon />
</Pressable>
```

VoiceOver and TalkBack read `accessibilityLabel`. The hint is read after a pause.

## Automated Testing

Automated checks catch low-hanging issues — missing alt text, color contrast, ARIA errors. They don't catch real-world usability problems but they catch regressions.

### axe-core

```bash
npm install -D @axe-core/react
```

```ts
// src/main.tsx — dev only
if (import.meta.env.DEV) {
  import('@axe-core/react').then(({ default: axe }) =>
    axe(React, ReactDOM, 1000),
  )
}
```

axe logs violations to the console. Fix them as they appear.

### In Tests

```tsx
import { render } from '@testing-library/react'
import { axe, toHaveNoViolations } from 'jest-axe'
expect.extend(toHaveNoViolations)

test('MachineCard is accessible', async () => {
  const { container } = render(<MachineCard machine={mock} />)
  expect(await axe(container)).toHaveNoViolations()
})
```

### Lighthouse in CI

```yaml
- uses: treosh/lighthouse-ci-action@v11
  with:
    urls: |
      https://preview.example.com/
    configPath: ./.lighthouserc.json
```

`.lighthouserc.json`:

```json
{
  "ci": {
    "assert": {
      "assertions": {
        "categories:accessibility": ["error", { "minScore": 0.95 }]
      }
    }
  }
}
```

Fail the build if accessibility drops below 0.95.

## Common Mistakes

- **`<div onClick>` instead of `<button>`.** No keyboard access, no role announcement, no focus ring.
- **Removing `outline` without replacement.** Keyboard users can't see where they are.
- **Placeholder as the only label.** Disappears on input, fails contrast.
- **Color-only state communication.** Color-blind users miss it. Add icons and text.
- **Modals without focus trap.** Tab moves to background content, screen reader reads it.
- **No "skip to content" link.** Keyboard users tab through 30 nav items every page.
- **Hand-rolled comboboxes / dropdowns / dialogs.** Each one's an a11y bug. Use a library.
- **`aria-label` slapped onto everything.** Often overrides better native semantics.
- **`tabindex` greater than 0.** Breaks natural order. Never use.
- **Auto-playing video with sound.** Hostile. Auto-play, no sound, with controls is the limit.
- **Flashing content faster than 3 Hz.** Seizure risk. WCAG 2.3.1 — non-negotiable.
- **No alt text on images.** Decorative images: `alt=""`. Meaningful ones: descriptive alt.
- **Empty headings or buttons.** Screen reader announces "button," then nothing.
- **Form errors that aren't announced.** Errors appear visually; screen reader users never know. Use `role="alert"`.
- **Touch targets smaller than 44×44.** Mis-tap rate skyrockets.
- **`prefers-reduced-motion` ignored.** Nausea-inducing animations on every page.
- **Testing only with VoiceOver on macOS.** NVDA and TalkBack behave differently. Test on each platform you ship to.
- **Treating Lighthouse 100 as "done."** Automated tools catch ~30%. Real users uncover the rest.
