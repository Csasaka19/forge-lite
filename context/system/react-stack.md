# React + Vite + TypeScript + Tailwind + shadcn/ui — Stack Reference

## Project Structure Convention

```
src/
├── main.tsx                    # Entry point. BrowserRouter wraps App.
├── App.tsx                     # Route definitions only.
├── index.css                   # Tailwind import + CSS variables for theming.
├── lib/
│   └── utils.ts                # cn() helper from shadcn. Add other utilities here.
├── components/
│   ├── ui/                     # shadcn primitives (auto-generated, editable)
│   ├── layout/
│   │   ├── Header.tsx
│   │   ├── Footer.tsx
│   │   └── Sidebar.tsx
│   └── shared/                 # App-specific reusable components
│       ├── ThemeToggle.tsx
│       └── ...
├── pages/                      # One file per route. Default export.
│   ├── HomePage.tsx
│   ├── DashboardPage.tsx
│   └── ...
├── hooks/                      # Custom React hooks
│   └── useTheme.ts
├── data/                       # Mock data, API client, types
│   ├── mock.ts
│   ├── api.ts
│   └── types.ts
└── assets/                     # Static images, fonts
```

## TypeScript Conventions

- Enable strict mode in tsconfig.json.
- Define types in `data/types.ts` — one file for the whole app in Phase 1.
- Use `interface` for object shapes, `type` for unions and intersections.
- No `any`. Use `unknown` when the type is genuinely unknown, then narrow.
- Props interfaces go in the same file as the component, above the component.

## React Conventions

- Functional components only.
- Prefer `const Component = () => { ... }` with named export for shared components.
- Prefer `export default function PageName()` for page components.
- Keep components under 150 lines. Extract sub-components when they grow.
- State that multiple components need → lift to the nearest common ancestor or use context.
- Side effects in useEffect with proper dependency arrays. No empty deps unless truly mount-only.

## Tailwind Conventions

- Mobile-first: write `className="p-4 md:p-6 lg:p-8"`, not the other way around.
- Use the `cn()` helper from shadcn for conditional classes: `cn("base-classes", condition && "conditional-classes")`.
- Color tokens via CSS variables (defined in index.css) so theming works.
- No custom CSS files. If you need something Tailwind can't do, use inline `style={}` as a last resort.

## shadcn/ui Conventions

- Add components via CLI: `npx shadcn@latest add [component-name]`.
- Components are source code in `src/components/ui/`. Edit them for your needs.
- Always import from `@/components/ui/button`, not from any npm package.
- When a shadcn component doesn't exist for your need, build a custom one in `components/shared/`.

## Routing Conventions

- Define all routes in App.tsx. Nowhere else.
- Use `<Link>` for navigation, never `<a href>` for internal links.
- Every `<Link to="...">` must target a route that exists.
- Nested routes use `<Outlet />` in the parent layout.

## Theming

- Support light and dark mode via a `data-theme` attribute on `<html>`.
- Define CSS variables in `index.css` under `[data-theme="light"]` and `[data-theme="dark"]` selectors.
- Use a `useTheme()` hook that reads/writes localStorage and toggles the attribute.
- Default: respect system preference via `prefers-color-scheme`, with manual override.

## Mock Data

- All mock data lives in `data/mock.ts`.
- Use realistic values appropriate to the product domain.
- Export named constants, not default exports.
- When the backend API is ready, replace mock imports with `data/api.ts` calls. The component code shouldn't change.

## Testing

- Vitest for unit/integration tests.
- Playwright for end-to-end tests.
- Test files live next to the code they test: `Component.tsx` → `Component.test.tsx`.
- At minimum, test: routes render without crashing, navigation works, critical user flows complete.

## Deployment

- Build: `npm run build` produces a `dist/` folder.
- Deploy options: Vercel (`vercel`), Netlify (`netlify deploy`), or any static host.
- Environment variables via `.env` files. Never commit `.env` — commit `.env.example`.
