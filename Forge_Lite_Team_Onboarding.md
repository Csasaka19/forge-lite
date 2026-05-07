# Forge Lite — Team Onboarding Guide

> **Who this is for.** You have a document, a text file, a PDF, or just notes about an app you want to build. You want to turn that into a working web application. This guide walks you through every step, assuming you've never done this before.

---

## What is this system?

Forge Lite is a set of files and scripts that help you go from "I have an idea written down" to "I have a working app I can open in my browser" using a tool called Claude Code. Claude Code is an AI that writes code for you in your terminal.

Here's the entire process in plain language:

```
You have a document          The system reads it         Claude Code builds
describing your app    →     and creates two files   →   the actual application
(any format)                 that describe what          from those files
                             to build and how
                             it should look
```

The two files it creates are:
- **`product-spec.md`** — describes what the app does, every page, every feature, every edge case
- **`design-brief.md`** — describes what it should look like: colors, fonts, layout

Once those two files exist in the right place, Claude Code reads them and builds the app.

---

## What you need before starting

### 1. A computer with Node.js installed

Check by opening your terminal and typing:
```bash
node --version
```
If you see `v20.x.x` or higher, you're good. If not, install it:
```bash
# Mac
brew install node

# Linux
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
nvm install 20
```

### 2. Claude Code installed

```bash
npm install -g @anthropic-ai/claude-code
```

Verify it works:
```bash
claude --version
```

### 3. The forge-lite repo on your machine

Ask your team lead for the repo URL, then:
```bash
cd ~/projects
git clone <repo-url> forge-lite
```

Or if someone sent you a zip file:
```bash
unzip forge-lite.zip -d ~/projects/forge-lite
```

### 4. The global Claude Code skill installed

This is a one-time setup. It teaches Claude Code how to build React apps the way your team does it.

```bash
# Create the skill folder
mkdir -p ~/.claude/skills/react-vite-builder

# Copy the skill file from forge-lite
cp ~/projects/forge-lite/skills/react-vite-builder/SKILL.md \
   ~/.claude/skills/react-vite-builder/SKILL.md

# Copy the global CLAUDE.md (then edit it with your name)
cp ~/projects/forge-lite/templates/global-claude-md.md ~/.claude/CLAUDE.md
nano ~/.claude/CLAUDE.md
# Change [YOUR NAME] and [COMPANY] to your actual info, then save.
```

That's the setup. You only do this once.

---

## The Full Process: From Document to Working App

### Step 1: Prepare your document

You need some kind of written description of the app you want to build. This can be:

| Format | Examples |
|--------|----------|
| A text file | `water-vending-idea.txt` |
| A PDF | `client-requirements.pdf` |
| A Markdown file | `app-concept.md` |
| A Word document | `project-brief.docx` (save as .txt first) |
| Notes you typed up | Anything in plain text |
| A voice recording | Transcribe it first using your phone's transcription or a tool like Otter.ai, save as .txt |

**What should be in the document?** Anything that describes the app:
- What does it do?
- Who uses it?
- What pages does it have?
- What features does it need?
- How should it look?

It doesn't need to be perfectly structured. It can be rough notes, bullet points, even a stream-of-consciousness paragraph. The system will structure it for you.

**Example — a rough text file might look like this:**

```
Water vending machine app. Customers find nearby machines on a map,
see if they have water, and buy some. Pay with M-Pesa or card.
Operators need a dashboard to see which machines are running low
or offline. Admin panel to manage everything. Blue and white design,
clean and simple. Mobile first because most users have phones.
Machines have water level sensors and the app shows current level.
Prices should be shown per liter. 5L, 10L, and 20L options.
```

That's enough. The system can work with this.

### Step 2: Run the conversion

Open your terminal and navigate to the forge-lite folder:

```bash
cd ~/projects/forge-lite
```

Run the conversion script with your document:

```bash
./scripts/forge-convert.sh ~/Desktop/water-vending-idea.txt
```

**What happens next:**

1. The script reads your file.
2. It figures out the project name from the content (or you can specify one).
3. It prints a long prompt in your terminal.
4. You copy that entire prompt and paste it into **Claude Chat** (open [claude.ai](https://claude.ai) in your browser).
5. Claude Chat reads your notes and produces two structured files:
   - A **product specification** (every page, every feature, every edge case)
   - A **design brief** (colors, fonts, layout rules)
6. Claude Chat gives you these in clearly labeled sections. You copy each one.

**Here's exactly what you'll see in the terminal:**

```
════════════════════════════════════════════════════════════
  Detected project name: water-vending
  Project folder will be: ~/projects/water-vending
════════════════════════════════════════════════════════════

Creating project folder...
✅ Project scaffolded at ~/projects/water-vending

Now paste the prompt below into Claude Chat (claude.ai):
════════════════════════════════════════════════════════════
  COPY EVERYTHING BELOW THIS LINE
════════════════════════════════════════════════════════════

[a very long prompt appears here]
```

### Step 3: Paste into Claude Chat and get the two files

1. Open [claude.ai](https://claude.ai) in your browser.
2. Start a new conversation.
3. Paste the entire prompt that the script printed.
4. Wait for Claude to respond. It will produce two clearly labeled documents.

The response will look something like this:

```
## product-spec.md

# Water Vending System — Product Specification

> A web application for managing water vending machines...

[full specification follows]

---

## design-brief.md

# Water Vending System — Design Brief

## Aesthetic
Clean, trustworthy, utilitarian...

[full design brief follows]
```

### Step 4: Save the files into your project

Copy each section from Claude Chat's response and save them:

```bash
cd ~/projects/water-vending

# Open the product spec file and paste the first document
nano docs/product-spec.md
# Paste the product-spec content, save (Ctrl+O, Enter, Ctrl+X)

# Open the design brief and paste the second document
nano docs/design-brief.md
# Paste the design-brief content, save
```

**Alternatively**, if you're not comfortable with `nano`, you can:
- Open the files in any text editor (VS Code, Sublime, TextEdit)
- The files are at: `~/projects/water-vending/docs/product-spec.md` and `~/projects/water-vending/docs/design-brief.md`

### Step 5: Open Claude Code and start building

```bash
cd ~/projects/water-vending
claude
```

Claude Code opens. You'll see a prompt like `>`. Type:

```
/build-feature Scaffold the project from scratch and build the landing page
```

**What happens:** Claude Code reads your `CLAUDE.md`, your `product-spec.md`, and your `design-brief.md`. It then:
1. Creates the entire project structure (React, Vite, Tailwind, shadcn/ui)
2. Installs all dependencies
3. Builds the landing page based on your spec
4. Verifies it works

This takes 5-15 minutes. You'll see it working in real time — creating files, running commands, fixing errors.

### Step 6: See your app

When Claude Code finishes, it will have started (or told you to start) the development server:

```bash
npm run dev
```

Open your browser and go to: **http://localhost:5173**

You should see your landing page. It's real, working, and based on your spec.

### Step 7: Build more pages

Go back to Claude Code and ask for the next feature:

```
/build-feature Build the machine map page with the location finder
```

Then:
```
/build-feature Build the purchase flow — volume selection, payment, confirmation
```

Then:
```
/build-feature Build the operator dashboard with machine status cards
```

Each time, Claude Code reads the spec, knows what to build, and does it.

### Step 8: Review what's been built

At any point, you can ask Claude Code to check its own work:

```
/review
```

This compares what's been built against the product spec and tells you:
- ✅ What's done
- 🟡 What's partially done
- ❌ What hasn't been started
- Any broken links or missing states

---

## Quick Reference: The Commands You'll Use

| What you want to do | Command |
|---|---|
| Convert your document to a spec | `./scripts/forge-convert.sh your-file.txt` |
| Start building a new feature | `/build-feature [describe what to build]` |
| Check what's done vs what's left | `/review` |
| Clear Claude's memory (when it gets slow) | `/clear` |
| Get help | `/help` |
| Exit Claude Code | `Ctrl+C` or type `exit` |

---

## Common Situations

### "I want to change a color or font"

Edit `docs/design-brief.md` in your text editor. Change the value. Then in Claude Code:
```
I updated the design brief. Read docs/design-brief.md and update
the theme colors across the app to match.
```

### "I want to add a new feature not in the original spec"

Edit `docs/product-spec.md` and add the feature description. Then:
```
/build-feature Build the new [feature name] that I just added to the spec
```

### "The app looks broken on my phone"

In Claude Code:
```
The app has layout issues on mobile. Check every page at 375px
viewport width and fix any overflow, overlapping, or illegible text.
```

### "I want to start over on one page"

```
Delete src/pages/DashboardPage.tsx and rebuild it from scratch based
on the operator dashboard section of the product spec.
```

### "Claude Code seems slow or confused"

Type `/clear` to reset its memory, then re-state what you're working on:
```
/clear
I'm building the water-vending project. Read CLAUDE.md and
docs/product-spec.md to catch up, then continue with [what you need].
```

### "I want someone else to continue where I left off"

Everything is saved in the project folder. Another team member can:
```bash
cd ~/projects/water-vending
claude
> /review
```
Claude Code reads the project files and knows exactly where things stand.

---

## How the Project Folder is Organized

After running the conversion script and building a few features, your project folder looks like this:

```
water-vending/
├── CLAUDE.md                  ← Claude Code reads this every session
├── .claude/
│   ├── rules/                 ← Auto-loaded rules for .tsx files
│   └── commands/              ← /build-feature and /review live here
├── docs/
│   ├── product-spec.md        ← YOUR SPEC — the source of truth
│   ├── design-brief.md        ← YOUR DESIGN — colors, fonts, layout
│   ├── react-stack.md         ← Tech conventions (don't edit)
│   └── design-system.md       ← Base design rules (don't edit)
├── src/                       ← THE APP — Claude Code builds this
│   ├── main.tsx
│   ├── App.tsx                ← All routes defined here
│   ├── pages/                 ← One file per page
│   ├── components/            ← Reusable pieces
│   ├── data/                  ← Mock data and types
│   └── ...
├── package.json
└── ...
```

**The two files you control:** `docs/product-spec.md` and `docs/design-brief.md`. Everything else is either template (don't edit) or generated by Claude Code.

---

## Starting Another Project

The process is exactly the same. Say you want to build a "smart-parking" app:

1. Write your idea in a text file: `smart-parking-notes.txt`
2. Run: `./scripts/forge-convert.sh smart-parking-notes.txt`
3. Paste prompt into Claude Chat, get the two files
4. Save them into the new project folder
5. Open Claude Code and start building

Each project gets its own folder under `~/projects/`. They're completely independent.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `command not found: claude` | Run `npm install -g @anthropic-ai/claude-code` |
| `command not found: node` | Install Node.js 20+ (see "What you need" section) |
| `permission denied: ./scripts/forge-convert.sh` | Run `chmod +x ~/projects/forge-lite/scripts/*.sh` |
| Claude Code says "I don't see a product spec" | Make sure `docs/product-spec.md` exists and isn't empty |
| The app won't start (`npm run dev` fails) | Ask Claude Code: `npm run dev fails with this error: [paste error]. Fix it.` |
| The app looks nothing like what I described | Check `docs/design-brief.md` — is the design direction actually described there? If it's vague, Claude Code will make generic choices |
| Claude Code is building something wrong | Be more specific. Instead of "build the dashboard", say "build the operator dashboard showing 4 stat cards at the top (total machines, alerts, today's revenue, water dispensed) and a scrollable list of machines below" |
| I don't have Claude Chat access | Ask your team lead — you need a Claude account (free tier works) to convert documents |

---

## Glossary

| Term | What it means |
|---|---|
| **Claude Code** | An AI tool that runs in your terminal and writes code for you |
| **Claude Chat** | The AI chat at claude.ai — you use it to convert documents into specs |
| **forge-lite** | The shared folder with templates and scripts your team uses |
| **product-spec.md** | A structured document describing every feature and page of your app |
| **design-brief.md** | A document describing the visual design: colors, fonts, layout |
| **CLAUDE.md** | A config file that Claude Code reads at the start of every session |
| **Skill** | A set of instructions that Claude Code auto-loads when it's relevant |
| **shadcn/ui** | A library of pre-built UI components (buttons, cards, inputs, etc.) |
| **Tailwind CSS** | A way to style web pages using short class names instead of CSS files |
| **Vite** | The tool that runs and builds your React app |
| **React** | The framework your app is built with |
