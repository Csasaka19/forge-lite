# AI & LLM Integration

How to call language models from your app reliably. Read before adding a "Summarize this," "Generate a draft," or RAG-style feature.

## Decision Tree

| Need | Pick |
|---|---|
| General-purpose, agentic, long context | **Anthropic Claude** (Opus / Sonnet / Haiku) |
| Cheapest credible quality | **Claude Haiku** or **GPT-4o-mini** |
| Open weights / self-host | **Llama**, **Mistral** via Ollama / vLLM |
| Embeddings | **OpenAI text-embedding-3-small/large** or **Voyage AI** |
| Vector search at small scale | **pgvector** in your existing Postgres |
| Vector search at large scale | **Pinecone**, **Weaviate**, **Qdrant** |
| Multi-provider fallback | **Vercel AI SDK** or a custom abstraction |

Pick the latest Claude or GPT model when building. **Claude Opus 4.7** is current top-tier; **Sonnet 4.6** is the daily-driver; **Haiku 4.5** for cheap-and-fast.

Don't over-engineer model selection. Start with one provider; abstract only when you have a real reason.

## Anthropic SDK

```bash
npm install @anthropic-ai/sdk
```

```ts
import Anthropic from '@anthropic-ai/sdk'

const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY })

const response = await client.messages.create({
  model: 'claude-sonnet-4-6',
  max_tokens: 1024,
  system: 'You are a concise customer-support assistant.',
  messages: [{ role: 'user', content: 'How do I cancel my order?' }],
})

const text = response.content
  .filter((b) => b.type === 'text')
  .map((b) => b.text)
  .join('\n')
```

### Rules

- **Set `max_tokens` sensibly.** Default-low; raise when you need long output. Capping prevents runaway cost.
- **System prompts are your spec.** Treat them like code — version, review, test.
- **Don't construct prompts from raw user input** without delineation. Use the message structure and clear markers.
- **Always include a request ID** in logs — Anthropic returns one in the response.

## Streaming Responses

For chat-style UI, stream tokens as they generate.

### Server (SSE)

```ts
app.post('/ai/chat', requireAuth, async (req, res) => {
  res.set({
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no',
  })
  res.flushHeaders()

  const stream = await client.messages.stream({
    model: 'claude-sonnet-4-6',
    max_tokens: 2048,
    messages: req.body.messages,
  })

  for await (const chunk of stream) {
    if (chunk.type === 'content_block_delta' && chunk.delta.type === 'text_delta') {
      res.write(`data: ${JSON.stringify({ text: chunk.delta.text })}\n\n`)
    }
  }

  res.write('data: [DONE]\n\n')
  res.end()
})
```

### Client

```ts
const es = new EventSource('/ai/chat-stream?id=' + sessionId)
es.onmessage = (e) => {
  if (e.data === '[DONE]') return es.close()
  const { text } = JSON.parse(e.data)
  appendToken(text)
}
```

For non-GET streaming, use fetch + manual `ReadableStream` reading:

```ts
const res = await fetch('/ai/chat', { method: 'POST', body: JSON.stringify({ messages }) })
const reader = res.body!.getReader()
const decoder = new TextDecoder()
while (true) {
  const { done, value } = await reader.read()
  if (done) break
  const chunk = decoder.decode(value)
  // parse SSE format, dispatch
}
```

## Prompt Management

Prompts are code. Version them, review them, test them.

### File Layout

```
prompts/
├── support-agent.v1.md
├── support-agent.v2.md             # newer; old kept for rollback
├── summarize.v1.md
└── classify-intent.v1.md
```

```md
<!-- prompts/support-agent.v2.md -->
You are a customer-support assistant for a water-vending app.

Rules:
- Reply in 1-3 sentences.
- If the user is angry, acknowledge before answering.
- If you don't know, say so and offer to escalate.

User context:
- Name: {{name}}
- Plan: {{plan}}
```

```ts
import fs from 'node:fs/promises'

async function loadPrompt(name: string, version: number, vars: Record<string, string>) {
  const raw = await fs.readFile(`prompts/${name}.v${version}.md`, 'utf8')
  return raw.replace(/\{\{(\w+)\}\}/g, (_, k) => vars[k] ?? '')
}
```

### Rules

- **One prompt per file** — easier to diff and review.
- **Version explicitly** — `.v2.md`. Never edit a deployed version in place.
- **Variables via `{{name}}`** — predictable, debuggable.
- **Test fixtures**: golden inputs + expected outputs you run on every change.
- **Track which version handled which request** — log prompt name + version with every call.

## Prompt Caching

Anthropic supports prompt caching for repeated context (system prompts, long docs):

```ts
await client.messages.create({
  model: 'claude-sonnet-4-6',
  max_tokens: 1024,
  system: [
    { type: 'text', text: 'You are a support assistant.' },
    { type: 'text', text: longDocumentBody, cache_control: { type: 'ephemeral' } },
  ],
  messages,
})
```

Subsequent calls reuse the cached portion at 10% of the input price (5-minute TTL). Hugely cheaper for chatbots reading from a fixed knowledge base.

## RAG (Retrieval-Augmented Generation)

Pattern for "answer questions using my documents":

1. **Embed** documents into vectors at ingest time.
2. **Embed the query** at request time.
3. **Search** for nearest vectors.
4. **Pass the top matches** as context to the LLM.

### Embeddings

```ts
import OpenAI from 'openai'
const openai = new OpenAI({ apiKey: env.OPENAI_API_KEY })

async function embed(text: string): Promise<number[]> {
  const res = await openai.embeddings.create({
    model: 'text-embedding-3-small',
    input: text,
  })
  return res.data[0].embedding
}
```

Anthropic doesn't offer embeddings directly — Voyage AI is their recommendation; OpenAI's are universal.

### Vector Storage with pgvector

```bash
# In your Postgres
CREATE EXTENSION vector;
```

```prisma
model DocumentChunk {
  id        String                 @id @default(uuid())
  documentId String                @map("document_id")
  content   String
  embedding Unsupported("vector(1536)")
  metadata  Json
}
```

```sql
CREATE INDEX ON document_chunks USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
```

```ts
const queryEmbedding = await embed(query)
const results = await prisma.$queryRaw<DocumentChunk[]>`
  SELECT id, content, metadata, 1 - (embedding <=> ${queryEmbedding}::vector) AS score
  FROM document_chunks
  ORDER BY embedding <=> ${queryEmbedding}::vector
  LIMIT 5
`
```

For small-to-medium use cases (< 10M vectors), pgvector is enough. Past that, look at Pinecone, Weaviate, or Qdrant.

### Chunking

- **Split documents** into 300–800 token chunks with overlap (50–100 tokens).
- **Include metadata** — source URL, section, last-updated. Pass to the LLM so it can cite.
- **Keep chunks self-contained** — don't split mid-sentence; prefer paragraph boundaries.

### Assemble the Prompt

```ts
const context = results
  .map((r) => `[${r.metadata.source}] ${r.content}`)
  .join('\n\n---\n\n')

await client.messages.create({
  model: 'claude-sonnet-4-6',
  max_tokens: 1024,
  system: `Answer using the context. If the context doesn't cover the question, say so. Cite sources by their source tag.`,
  messages: [{ role: 'user', content: `Context:\n${context}\n\nQuestion: ${query}` }],
})
```

## Common AI Features

### Summarization

```ts
async function summarize(text: string) {
  const res = await client.messages.create({
    model: 'claude-haiku-4-5-20251001',
    max_tokens: 200,
    system: 'Summarize the input in 2-3 sentences. Match the input language.',
    messages: [{ role: 'user', content: text }],
  })
  return extractText(res)
}
```

Use Haiku for cheap bulk summarization; Sonnet for nuance.

### Classification

```ts
async function classify(text: string, labels: string[]) {
  const res = await client.messages.create({
    model: 'claude-haiku-4-5-20251001',
    max_tokens: 50,
    system: `Classify the input as one of: ${labels.join(', ')}. Reply with ONLY the label, no explanation.`,
    messages: [{ role: 'user', content: text }],
  })
  const out = extractText(res).trim()
  return labels.includes(out) ? out : labels[0]  // fallback
}
```

Always validate output is in the allowed set — models occasionally improvise.

### Structured Generation

For JSON outputs, use tool-use / function-calling mode rather than prompting "respond with JSON":

```ts
const res = await client.messages.create({
  model: 'claude-sonnet-4-6',
  max_tokens: 1024,
  tools: [{
    name: 'extract_invoice',
    description: 'Extract invoice fields',
    input_schema: {
      type: 'object',
      properties: {
        total: { type: 'number' },
        currency: { type: 'string' },
        items: { type: 'array', items: { type: 'object' } },
      },
      required: ['total', 'currency', 'items'],
    },
  }],
  tool_choice: { type: 'tool', name: 'extract_invoice' },
  messages: [{ role: 'user', content: invoiceText }],
})

const tool = res.content.find((b) => b.type === 'tool_use')
const parsed = tool?.input    // already JSON-validated
```

Schema-enforced output beats prompt-engineered JSON.

## Token Cost Tracking

Every response includes usage data. Log it.

```ts
logger.info({
  model: res.model,
  inputTokens: res.usage.input_tokens,
  outputTokens: res.usage.output_tokens,
  cacheRead: res.usage.cache_read_input_tokens,
  cacheWrite: res.usage.cache_creation_input_tokens,
  userId,
  endpoint: 'chat',
  costUsd: estimateCost(res.model, res.usage),
}, 'ai.call')
```

### Rules

- **Track per user / per tenant.** Lets you bill, throttle, or alert on outliers.
- **Per-endpoint budgets.** Cap monthly spend. Alert at 80%.
- **Reject when budget exceeded** — degrade gracefully ("AI features unavailable for your plan this month").

## Provider Fallback

Don't hard-couple to one provider. When Anthropic returns a 529 (overloaded), fall back to a different model or queue and retry.

```ts
async function callLlm(messages: Message[]) {
  try {
    return await client.messages.create({ model: 'claude-sonnet-4-6', max_tokens: 1024, messages })
  } catch (err) {
    if (err.status === 529 || err.status === 503) {
      return await client.messages.create({ model: 'claude-haiku-4-5-20251001', max_tokens: 1024, messages })
    }
    throw err
  }
}
```

For full multi-provider abstraction (Anthropic + OpenAI + others), the **Vercel AI SDK** provides a uniform interface. Use it when you need real provider portability; otherwise the SDK abstraction is overhead.

## Safety

- **Don't echo user input verbatim** in system prompts — escape, separate via message roles.
- **Output validation** — for classifications, restrict to known labels; for code, parse and check; for SQL, **never** execute generated SQL without manual review or a sandboxed runtime.
- **Rate-limit per user.** AI endpoints are expensive — abuse is real.
- **Log inputs and outputs** for auditing — but redact PII per your privacy policy.
- **Test against prompt injection.** "Ignore prior instructions" attacks. System-level controls (don't expose tools that delete data; require confirmation for destructive actions) matter more than prompt-level defenses.

## Common Mistakes

- **No `max_tokens` cap.** Runaway cost on the first request that loops.
- **Sync `messages.create` in a request handler with large `max_tokens`.** 20-second response. Stream instead.
- **One file with 50 prompts.** Unreviewable. One file per prompt, versioned.
- **Editing prompts in production without versioning.** Can't roll back, can't compare.
- **Prompt-engineering JSON output.** Models drift. Use tool/function-calling for structured output.
- **No usage logging.** Bill explodes; you can't tell which feature drove it.
- **Hardcoded API key.** Use env vars. Validate at boot.
- **Trusting LLM output for SQL or shell commands.** Catastrophe class. Validate or sandbox.
- **No fallback when the provider is down.** Feature breaks completely. Have a degradation path.
- **Embedding model mismatch.** Mixing embeddings from different models — distances are meaningless. Lock to one model; re-embed on switch.
- **Vector index missing or wrong metric.** `<=>` is cosine distance in pgvector; pair with `vector_cosine_ops` index, not L2.
- **Returning RAG context without citations.** Users can't verify. Always cite.
- **Prompt injection via user-controlled context.** Treat retrieved docs as untrusted text; structure prompts so the model knows what's content and what's instruction.
