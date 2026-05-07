# forge-lite

A reusable Claude Code build system for shipping React apps from a written spec. One repo holds the shared context, skills, and templates; each new project clones the structure and gets a project-specific spec; Claude Code does the building.

No custom infrastructure. No API keys. No deployment scripts. Just markdown, shell scripts, and Claude Code.

---

## Table of contents

1. [Why this exists](#why-this-exists)
2. [How it works](#how-it-works)
3. [Repo layout](#repo-layout)
4. [Installation (one-time per machine)](#installation-one-time-per-machine)
5. [Creating a new project](#creating-a-new-project)
6. [The Claude Code workflow](#the-claude-code-workflow)
7. [Converting rough notes into a spec](#converting-rough-notes-into-a-spec)
8. [Sharing with a team](#sharing-with-a-team)
9. [What you get out of the box](#what-you-get-out-of-the-box)
10. [Known gotchas](#known-gotchas)
11. [Customizing](#customizing)

---

## Why this exists

Pipelines like Forge — orchestrators that take a spec and produce a working app — work, but they cost real engineering effort to maintain: APIs, queues, secrets, deployment. Most of what they do is already inside Claude Code: read context, plan, edit files, run commands, verify.

`forge-lite` collapses the pipeline into a library of markdown files. The orchestration *is* Claude Code; this repo just supplies the prompts, conventions, and scaffolds it needs to act consistently across projects.

The trade you make: you keep one human in the loop (you, or a teammate, running `claude`). What you get: zero infrastructure, full transparency, and the same workflow scales from a weekend prototype to a real product.

---

## How it works

```
~/.claude/                         <- Per-machine Claude Code config (global)
├── CLAUDE.md                      Global preferences (loaded into every session)
└── skills/
    └── react-vite-builder/
        └── SKILL.md               Reusable build procedure (Vite + Tailwind + shadcn)

~/projects/
├── forge-lite/                    <- This repo (a library, not a runtime)
│   ├── context/                   Reference docs copied into projects
│   ├── templates/                 Blank spec + starter CLAUDE.md
│   └── scripts/                   new-project.sh, convert-to-spec.sh
│
├── water-vending/                 <- A real project, scaffolded from forge-lite
│   ├── CLAUDE.md                  Project-specific Claude Code config
│   ├── .claude/
│   │   ├── rules/                 Lazy-loaded rules (e.g. when editing .tsx)
│   │   └── commands/              Slash commands like /build-feature, /review
│   ├── docs/
│   │   ├── product-spec.md        What we're building
│   │   └── design-brief.md        Visual direction
│   └── src/                       The actual app (Claude Code builds this)
│
└── another-project/               Same structure, different spec
```

Key idea: `forge-lite` is a *library*. The `new-project.sh` script copies its contents into a fresh project folder. From there the project is self-contained — Claude Code reads from the project's own `.claude/` and `docs/`, not from this repo.

---

## Repo layout

```
forge-lite/
├── README.md                      You are here
├── context/
│   ├── react-stack.md             React + Vite + TS + Tailwind + shadcn conventions
│   └── design-system.md           Default visual conventions (override per-project)
├── templates/
│   ├── project-spec.md            Blank product-spec template
│   └── CLAUDE.md.template         Starter project CLAUDE.md
└── scripts/
    ├── new-project.sh             Scaffold a new project folder from templates
    └── convert-to-spec.sh         Turn rough notes (.txt/.md/.pdf) into a spec
```

---

## Installation (one-time per machine)

Prerequisites:

- Node.js 20+ and npm
- Git
- Claude Code: `npm install -g @anthropic-ai/claude-code`
- Optional: `poppler-utils` for the PDF-to-spec conversion (`sudo apt install poppler-utils` on Linux, `brew install poppler` on macOS)

Clone forge-lite:

```bash
mkdir -p ~/projects
git clone <your-fork-url> ~/projects/forge-lite
chmod +x ~/projects/forge-lite/scripts/*.sh
```

Set up the global Claude Code files (these are NOT in this repo — they live in your home directory and are personalized per user):

```bash
mkdir -p ~/.claude/skills/react-vite-builder
```

Then create two files. The contents for both are pinned below — they're short enough that copy-pasting them is faster than packaging them.

**`~/.claude/CLAUDE.md`** (global preferences, loaded into every Claude Code session):

```markdown
# Global Preferences

## Identity
- My name is YOUR_NAME. I work at YOUR_COMPANY.
- I build web applications using React, Vite, TypeScript, Tailwind CSS, and shadcn/ui.
- My projects are in ~/projects/. Each has its own CLAUDE.md with project-specific context.

## Code Style
- TypeScript strict mode. No `any` types.
- Functional components only. No class components.
- Named exports for components. Default exports for pages.
- Use Tailwind utility classes. No custom CSS files unless absolutely necessary.

## Workflow
- Before building any feature, read `docs/product-spec.md` if it exists.
- Before writing UI code, read `docs/design-brief.md` if it exists.
- After completing a feature, run the build and fix any errors before reporting done.
- Commit each logical change separately with a descriptive message.
```

**`~/.claude/skills/react-vite-builder/SKILL.md`** (the build skill — Claude Code triggers it on prompts like "scaffold the project", "build this", etc.):

```markdown
---
name: react-vite-builder
description: |
  Use this skill when the user asks to create a new React application,
  scaffold a project, build a feature from a spec, or set up a Vite +
  React + TypeScript + Tailwind + shadcn/ui project.
---

# React + Vite + shadcn/ui Project Builder

## When creating a new project from scratch
1. `npm create vite@latest . -- --template react-ts`
2. `npm install -D tailwindcss @tailwindcss/vite`
3. Add `tailwindcss()` to the `plugins` array in `vite.config.ts`.
4. Replace `src/index.css` with `@import "tailwindcss";`.
5. `npx shadcn@latest init -y -d` (accept defaults; CSS variables: yes).
6. `npm install react-router-dom`
7. `npx shadcn@latest add button card input label textarea select checkbox badge separator tabs dialog sonner`
8. Verify `npm run dev` starts cleanly.

## When building features from a spec
1. Read `docs/product-spec.md` first.
2. Read `docs/design-brief.md` for visual direction.
3. Plan the route structure. List every route and what it shows.
4. Build shared components first (layout, nav, theme).
5. Build pages one at a time, in user-encounter order.
6. Use realistic mock data — names, prices, descriptions that fit the domain.
7. After each page, run `npm run dev` and verify it renders.
8. Handle loading, empty, and error states for every page.
9. Mobile-first. Design for 375px, then 768px, then 1280px.

## Gotchas
- shadcn/ui components are source code in `src/components/ui/`. Edit freely.
- Wrap the app in `<BrowserRouter>` in `main.tsx`.
- Tailwind v4 uses `@import "tailwindcss"`, not `@tailwind base/components/utilities`.
- Every `<Link to="...">` must target a route that exists in `App.tsx`.
- If Vite shows import errors after shadcn init, check `tsconfig.json` paths match `components.json`.
```

That's it. You'll only edit these again if you want to retune Claude Code's defaults.

---

## Creating a new project

```bash
cd ~/projects/forge-lite
./scripts/new-project.sh my-app
```

This creates `~/projects/my-app/` containing:

- `CLAUDE.md` — project config (placeholder name auto-filled).
- `docs/product-spec.md` — blank spec template, ready to fill.
- `docs/design-brief.md` — *not auto-created; write this yourself.*
- `docs/react-stack.md` and `docs/design-system.md` — copies of the central reference docs (so the project is self-contained even if `forge-lite/` moves).
- `.claude/rules/react-conventions.md` — auto-loaded when Claude Code touches `.tsx` files.
- `.claude/commands/build-feature.md` and `review.md` — slash commands available inside Claude Code.
- `.gitignore` and an initialized git repo.

Then:

```bash
cd ~/projects/my-app
$EDITOR docs/product-spec.md       # describe what to build
$EDITOR docs/design-brief.md       # describe how it should look (create this file)
claude                              # open Claude Code
```

---

## The Claude Code workflow

Inside Claude Code, the project's slash commands are loaded automatically. The typical sequence:

**1. Scaffold.**

```
> /build-feature Scaffold the project from scratch. Set up Vite, React,
  TypeScript, Tailwind, shadcn/ui, and React Router per the skill. Build
  the layout (Header, Footer, theme toggle), the route table in App.tsx,
  and any shared components. Don't build any pages yet.
```

**2. Build pages, one at a time.**

```
> /build-feature Build the [page name]. Include [key features].
  Handle: [edge cases listed in the spec].
```

**3. Review every two or three pages.**

```
> /review
```

`/review` reads the spec, compares it to what's built, marks each feature done / partial / not started, runs `npm run build`, and reports any issues.

**4. Iterate on what's wrong.**

```
> The purchase flow needs a step indicator. Also the volume selector
  should show the price updating live. Fix these.
```

**5. Final check.**

```
> Run npm run build. Fix any errors. Then check every route loads on
  mobile viewport. List any issues.
```

---

## Converting rough notes into a spec

If you have notes — a `.txt`, a `.md`, a meeting transcript, or a PDF of requirements — `convert-to-spec.sh` extracts the text, embeds it in a prompt with the spec template, and prints a single block to paste into [claude.ai](https://claude.ai). Claude returns a fully-structured spec; copy that to your project's `docs/product-spec.md`.

```bash
cd ~/projects/forge-lite
./scripts/convert-to-spec.sh ~/Downloads/my-app-idea.txt
# Prints a prompt. Paste it into Claude Chat. Save the output to docs/product-spec.md.
```

PDFs need `pdftotext` (from `poppler-utils`).

For a voice note: transcribe with Otter.ai / MacWhisper / Apple Voice Memos, save as `.txt`, then run the script.

---

## Sharing with a team

```bash
# Push this repo to your git host:
cd ~/projects/forge-lite
git remote add origin git@github.com:yourorg/forge-lite.git
git push -u origin main
```

Each teammate, once:

```bash
git clone git@github.com:yourorg/forge-lite.git ~/projects/forge-lite
chmod +x ~/projects/forge-lite/scripts/*.sh
mkdir -p ~/.claude/skills/react-vite-builder
# Then create ~/.claude/CLAUDE.md and ~/.claude/skills/react-vite-builder/SKILL.md
# from the snippets in the Installation section above.
npm install -g @anthropic-ai/claude-code
```

That's it — they can now run `./scripts/new-project.sh` and the workflow is identical to yours.

---

## What you get out of the box

The default stack the skill targets:

- **React 19** + TypeScript (strict)
- **Vite** for dev/build
- **Tailwind CSS v4** (CSS-first config, `@import "tailwindcss"`)
- **shadcn/ui** (current version: components copy into `src/components/ui/`)
- **React Router** for routing
- A **mobile-first** design system with light + dark themes

The `context/react-stack.md` file documents the conventions in detail (project structure, TS rules, mock data layout, theming pattern, testing). Each new project gets a copy in its own `docs/` so it stays in sync for that project even if the central repo evolves.

---

## Known gotchas

These are real friction points encountered while bootstrapping projects with this system. Worth knowing before you hit them.

- **The `.gitignore` produced by `new-project.sh` uses literal `\n` characters** because the script's `echo` doesn't interpret backslash escapes on Linux. After running the script, open `.gitignore` and replace the contents with one entry per line. (Filed as a known issue; if you fix it in the script, send a PR.)
- **shadcn/ui has changed since the original system was written.** Recent versions install components against `@base-ui/react` (not Radix), and the `<Button asChild>` prop is gone. To put button styling on a `<Link>`, import `buttonVariants` and apply it as `className`:
  ```tsx
  <Link to="/x" className={buttonVariants({ size: 'lg' })}>Go</Link>
  ```
- **TypeScript 6 deprecates `compilerOptions.baseUrl`.** If you keep it, builds emit `TS5101`. Just remove `baseUrl` from `tsconfig.json` and `tsconfig.app.json` — `paths` works without it (paths are resolved relative to the tsconfig file).
- **The current ESLint preset is strict.**
  - `react-hooks/set-state-in-effect` flags synchronous `setState` calls in effect bodies. Move that state into a lazy `useState(() => ...)` initializer or push it into an async callback.
  - `react-refresh/only-export-components` flags any file that exports both a component and a non-component value. The shadcn-generated UI files trip this. Add an override in `eslint.config.js`:
    ```js
    {
      files: ['src/components/ui/**/*.{ts,tsx}'],
      rules: { 'react-refresh/only-export-components': 'off' },
    }
    ```
- **`npm run lint` in the starter `CLAUDE.md.template` is described as "typecheck", but Vite's default is `eslint .`** Either rename it or add a separate `typecheck` script. The build script already runs `tsc -b`, so type errors block `npm run build` regardless.
- **Vite scaffolding into a non-empty directory prompts interactively.** `new-project.sh` creates the project folder *before* you'd run `npm create vite`. The clean workaround is to scaffold Vite into a temp directory (`/tmp/scaffold`) and copy non-conflicting files into the project folder.

---

## Customizing

Things you'll want to fork to your own taste:

- **`context/design-system.md`** — your default visual conventions. The water-vending project, for example, overrides this with a blue/white palette in its own `docs/design-brief.md`.
- **`context/react-stack.md`** — your stack conventions. If you prefer a different state library, ORM, or test runner, change it here.
- **`templates/project-spec.md`** — the spec template. If your products are mostly mobile apps or APIs, the section headings should reflect that.
- **`scripts/new-project.sh`** — the scaffolder. Add commands you always want (e.g., `playwright install`, `husky install`, env-file setup).
- **`scripts/convert-to-spec.sh`** — the spec converter. Currently prints a prompt for you to paste into Claude Chat; if you'd rather hit the API directly, swap the bottom of the script for a `curl` call.

---

## License

MIT, unless you decide otherwise. The shell scripts and markdown templates are short enough that "do what you want with them" is the spirit.
