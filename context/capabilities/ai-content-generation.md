# AI Content Generation

How to build AI-powered content engines: brand-consistent multi-format output, image generation, calendars, and review workflows. Read before wiring an LLM into a "create content" feature.

## Decision Tree

| Need | Pick |
|---|---|
| Text generation (post, thread, blog) | **`@anthropic-ai/sdk`** with `claude-opus-4-7` (long, complex) or `claude-sonnet-4-6` (default) or `claude-haiku-4-5` (cheap, fast) |
| Image generation | **OpenAI `gpt-image-1`** or **Stability AI `stable-image-core`** via REST |
| On-brand voice across channels | Versioned brand prompt + cache control; pin a tone reference |
| Long-running batch | **Background job** (see `background-jobs.md`) + status polling |
| User-iterative editing | Streaming + diff-aware regenerate |

See `ai-llm-integration.md` for SDK setup, streaming, prompt caching, and RAG. This file is about the **product layer** on top.

## Pipeline

```
Brand Context → Strategy → Plan → Pieces → Review → Publish
```

- **Brand Context** — persistent: voice, audience, brand pillars, examples of good + bad copy.
- **Strategy** — user goal: "Drive signups for new feature." Constraints: channels, deadline, tone shift.
- **Plan** — calendar of pieces. Each piece has channel, format, hook, due date.
- **Pieces** — actual content per format. Generated, reviewed, edited.
- **Review** — human approves, requests revisions, or edits inline.
- **Publish** — exported or scheduled (out of scope here; see `event-driven-architecture.md` for scheduling).

Each stage is its own record with a status field. Don't collapse them — users want to edit plans without regenerating pieces, and tweak pieces without redoing strategy.

## Data Model

```ts
interface Brand {
  id: string
  orgId: string
  name: string
  voice: string                  // 200-500 word description of tone
  audience: string               // who they speak to
  pillars: string[]              // ["education", "sustainability"]
  doExamples: string[]           // copy that nails the voice
  dontExamples: string[]         // off-brand copy
  visualGuidelines?: string      // for image prompts
  updatedAt: Date
}

interface Strategy {
  id: string
  brandId: string
  goal: string                   // free text
  channels: ('twitter' | 'instagram' | 'linkedin' | 'blog' | 'tiktok')[]
  startDate: Date
  endDate: Date
  status: 'draft' | 'active' | 'archived'
}

interface ContentPlan {
  id: string
  strategyId: string
  generatedAt: Date
  promptVersion: string          // which prompt template generated this
  notes?: string
}

interface PlannedPiece {
  id: string
  planId: string
  channel: 'twitter' | 'instagram' | 'linkedin' | 'blog' | 'tiktok'
  format: 'thread' | 'single_post' | 'carousel' | 'reel_script' | 'blog_post'
  hook: string                   // one-line attention-grabber
  topic: string
  scheduledFor: Date
  status: 'planned' | 'generated' | 'in_review' | 'approved' | 'rejected'
  pieceId?: string               // link to generated content
}

interface Piece {
  id: string
  plannedId: string
  channel: string
  format: string
  body: string                   // text content
  imagePrompts?: string[]        // text-to-image prompts
  imageUrls?: string[]           // generated/uploaded images
  metadata: Record<string, unknown>   // format-specific (carousel slides, thread tweets)
  versionNumber: number
  generatedByModel: string
  generatedAt: Date
}

interface Template {
  id: string
  brandId?: string               // null = global
  name: string
  channel: string
  format: string
  promptTemplate: string         // Handlebars-style {{brandVoice}}, {{topic}}
  variables: string[]
  version: number
}
```

## Prompt Engineering for Voice Consistency

Construct prompts with **layered context**: brand → strategy → format → task. Cache the stable layers.

```ts
import Anthropic from '@anthropic-ai/sdk'

const client = new Anthropic()

async function generateThread(brand: Brand, strategy: Strategy, topic: string) {
  const response = await client.messages.create({
    model: 'claude-sonnet-4-6',
    max_tokens: 2048,
    system: [
      {
        type: 'text',
        text: buildBrandPrompt(brand),
        cache_control: { type: 'ephemeral' },        // cached: changes rarely
      },
      {
        type: 'text',
        text: buildStrategyPrompt(strategy),
        cache_control: { type: 'ephemeral' },        // cached: stable for the strategy
      },
      {
        type: 'text',
        text: buildFormatPrompt('twitter_thread'),   // cached: per format
        cache_control: { type: 'ephemeral' },
      },
    ],
    messages: [
      { role: 'user', content: `Topic: ${topic}\n\nWrite a 5-7 tweet thread.` },
    ],
  })
  return extractText(response)
}
```

### Brand Prompt Template

```
You write for {{brand.name}}.

VOICE:
{{brand.voice}}

AUDIENCE:
{{brand.audience}}

PILLARS (always grounded in one of these): {{brand.pillars.join(', ')}}

DO write like this:
{{#each brand.doExamples}}- "{{this}}"
{{/each}}

DON'T write like this:
{{#each brand.dontExamples}}- "{{this}}"
{{/each}}

RULES:
- Never use words: synergy, leverage, paradigm, revolutionary, game-changer
- No emoji unless the brand uses them in examples
- Active voice
- Concrete > abstract: name things, not "things"
```

Tone is **shown, not described.** Examples carry more weight than adjectives. "Casual, friendly, smart" tells the model nothing. Three real Tweets tells it everything.

### Versioning Prompts

Store prompt templates as files in the repo: `prompts/thread/v3.md`. Reference `promptVersion` on every generated piece so you can re-run experiments and roll back regressions.

## Multi-Format Output

Each channel has format-specific constraints. Encode them in the prompt and validate the output.

### Twitter Thread

- 5-15 tweets, 280 chars each.
- First tweet is the **hook** — provocative, complete on its own.
- Last tweet is the **CTA**.

```ts
const ThreadSchema = z.object({
  tweets: z.array(z.string().max(280)).min(5).max(15),
})

async function generateThread(...): Promise<z.infer<typeof ThreadSchema>> {
  const raw = await callLLM(...)
  return ThreadSchema.parse(JSON.parse(raw))
}
```

Use tool-use / structured output for reliable parsing — see `ai-llm-integration.md`.

### Instagram Carousel (1080×1080)

- 5-10 slides.
- Each slide: short headline + 1-2 sentence body.
- Slide 1: hook. Last slide: CTA.

```ts
interface CarouselSlide {
  index: number
  headline: string             // <50 chars
  body: string                 // <150 chars
  imagePrompt: string          // for text-to-image
}
```

Render the slide via a server-side image generator (see `image-media-processing.md`) — Sharp + text overlay, or use Bannerbear/Cloudinary for templates.

### Reel / TikTok Script

- 30-60 second target.
- Hook in first 3 seconds.
- Beats: hook → tension → payoff → CTA.

```ts
interface ReelScript {
  hook: string                 // 0-3s
  beats: { timestamp: string; action: string; voiceover: string }[]
  cta: string
  hashtags: string[]
}
```

### Blog Post

- Title (≤60 chars for SEO; see `seo-metadata.md`).
- Meta description (≤160 chars).
- H2/H3 outline.
- Body in Markdown.

## Image Generation

```ts
async function generateImage(prompt: string, size: '1024x1024' | '1024x1536' = '1024x1024') {
  const res = await openai.images.generate({
    model: 'gpt-image-1',
    prompt,
    size,
    n: 1,
  })
  return res.data[0].b64_json     // upload to S3 (see file-upload-storage.md)
}
```

### Prompt Construction for On-Brand Images

```
{{brand.visualGuidelines}}

Subject: {{slide.headline}}
Composition: centered, room for text overlay at bottom third
Style: {{brand.visualStyle}}
Color palette: {{brand.colors.join(', ')}}
Avoid: text in image, watermarks, faces (unless explicitly required)
```

Text-in-image is unreliable from current models. **Generate the image, overlay text yourself.**

## Content Calendar

Calendar view shows planned pieces by date and channel. Drag-and-drop reschedules; see `drag-drop-sortable.md`.

```tsx
function ContentCalendar({ pieces }: { pieces: PlannedPiece[] }) {
  const byDate = groupBy(pieces, (p) => format(p.scheduledFor, 'yyyy-MM-dd'))
  return (
    <div className="grid grid-cols-7 gap-1">
      {weekDates.map((d) => (
        <DayCell key={d.toISOString()} date={d} pieces={byDate[format(d, 'yyyy-MM-dd')] ?? []} />
      ))}
    </div>
  )
}
```

Each piece chip color-coded by channel; click to open generated content.

## Batch Generation

For "generate 30 pieces from this plan" requests, **never block the UI**:

```ts
// API
async function startBatchGeneration(planId: string, userId: string) {
  const batchId = await prisma.batchJob.create({
    data: { planId, status: 'queued', totalPieces, completedPieces: 0 },
  })
  await queue.add('generate-batch', { batchId: batchId.id, userId })
  return batchId
}

// Worker (see background-jobs.md)
async function processBatch({ batchId }: { batchId: string }) {
  const planned = await prisma.plannedPiece.findMany({ where: { batchId, status: 'planned' } })
  for (const p of planned) {
    try {
      const piece = await generateForChannel(p)
      await prisma.piece.create({ data: piece })
      await prisma.plannedPiece.update({ where: { id: p.id }, data: { status: 'generated', pieceId: piece.id } })
      await prisma.batchJob.update({ where: { id: batchId }, data: { completedPieces: { increment: 1 } } })
    } catch (err) {
      logger.error({ plannedId: p.id, err }, 'piece generation failed')
    }
  }
}
```

Client polls or subscribes via SSE; see `realtime-features.md`.

## Review Workflow

```
generated → in_review → (approve | request_changes | edit)
                        ↓                    ↓          ↓
                     approved             revised   approved (after edit)
```

UI patterns:

- **Side-by-side**: original prompt on left, generated content on right, editable.
- **Inline edit** — Tiptap (see `rich-text-editing.md`) for blog/long form.
- **Regenerate this section** — partial regeneration; preserve user edits elsewhere.
- **Diff view** — when AI regenerates, show before/after.

```tsx
function PieceReview({ piece }: { piece: Piece }) {
  const [body, setBody] = useState(piece.body)
  return (
    <div>
      <Editor value={body} onChange={setBody} />
      <div className="flex gap-2">
        <Button onClick={() => approve(piece.id, body)}>Approve</Button>
        <Button variant="ghost" onClick={() => regenerate(piece.id)}>Regenerate</Button>
        <Button variant="ghost" onClick={() => regenerateSection(piece.id, selection)}>Regenerate selection</Button>
      </div>
    </div>
  )
}
```

## Template System

Templates are reusable prompt patterns with variables. Users pick a template + fill variables → generate.

```ts
interface Template {
  name: 'Customer Story' | 'Product Launch' | 'Weekly Recap' | ...
  variables: ['customerName', 'painPoint', 'solution']
  prompt: `Write a LinkedIn post about how {{customerName}} solved {{painPoint}} with our help. End with: ${'how we did it: {{solution}}'}`
}
```

Render in UI: variable fields auto-detected from `{{...}}`. Save filled templates as drafts.

## Common Mistakes

- **Voice described in adjectives only.** Model defaults to generic. Provide 5+ real examples.
- **Same prompt for every channel.** Twitter ≠ LinkedIn ≠ Blog. Format-specific prompts.
- **No `cache_control` on the brand prompt.** Every request pays for the full system message. Cache.
- **`max_tokens` defaulted to too low.** Blog posts cut off mid-sentence. Set per format.
- **Free-text output for structured needs (threads, carousels).** Parsing nightmare. Use tool-use / structured output.
- **Generate-then-edit lost on regenerate.** User edits, then hits regenerate, loses work. Confirm before overwriting.
- **Image text generated by the model.** Unreliable; misspells, distorts. Render text in HTML/Canvas overlay.
- **Batch generation runs inline.** Browser times out on a 30-piece plan. Always queue.
- **No version tracking on prompts.** Voice drifts; can't reproduce. Pin `promptVersion` on every piece.
- **AI output published unreviewed.** Hallucinations, off-brand. Always human-in-the-loop until you've measured quality.
- **One global "brand voice" for multi-brand orgs.** Bleed-over. Scope brand to `orgId`.
- **`do_examples` and `dont_examples` rotated randomly.** Voice drifts. Pin to stable set; refresh deliberately.
- **No rate limiting on generation endpoint.** $100 OpenAI bill from one user spamming. See `rate-limiting-throttling.md`.
- **Storing generated images inline as base64.** DB bloats. Upload to S3; store URL.
- **Brand prompt edited live without versioning.** All in-flight generations use new voice mid-batch. Snapshot brand into the strategy.
- **Streaming response stored only when complete.** Crash mid-stream loses everything. Persist partial output to DB or KV.
