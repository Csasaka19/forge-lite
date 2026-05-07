# Default Design System

These are baseline visual conventions. Each project's `docs/design-brief.md` can override any of these.

## Typography
- Display / headings: use a serif or distinctive sans-serif. Not Inter, not Roboto, not system fonts.
- Body text: use a clean sans-serif (Geist, DM Sans, or similar).
- Monospace / technical labels: JetBrains Mono or Fira Code.
- Load fonts via `@fontsource` packages, not Google Fonts CDN.

## Color
- Every project defines its own palette in CSS variables.
- Minimum: --background, --foreground, --primary, --secondary, --muted, --accent, --destructive, --border.
- Support light and dark themes from day one. It's 3x harder to add later.
- Use shadcn's CSS variable system — it handles theme switching automatically.

## Layout
- Max content width: 1280px (centered).
- Consistent page padding: `px-4 sm:px-6 lg:px-8`.
- Every page has a `<main>` wrapper.
- Navigation is consistent across all pages (Header or Sidebar, not both for mobile).

## Components
- Use shadcn/ui as the base component library.
- Customize shadcn components by editing the source files directly.
- All interactive elements must have visible focus states.
- Buttons: have a clear primary action per page. Don't put 3 equally-weighted buttons next to each other.

## Motion
- Prefer CSS transitions over JS animation libraries for simple transitions.
- Use framer-motion only when CSS can't do it (layout animations, exit animations, gesture-driven).
- Keep transitions under 300ms. Entrance: 200-300ms. Exit: 150-200ms.
- Never animate something just because you can. Every animation should serve comprehension.

## Mobile
- Design mobile-first. Every layout must work at 375px before you add responsive breakpoints.
- Touch targets: minimum 44x44px.
- No horizontal scroll on any page at any viewport width.
