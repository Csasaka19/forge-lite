export interface Capability {
  id: string
  label: string
  description: string
  keywords: RegExp
  contextFile: string
}

export const CAPABILITIES: Capability[] = [
  {
    id: 'auth',
    label: 'Authentication',
    description: 'Login, sessions, user accounts',
    keywords: /\b(login|log[ -]?in|auth|authentication|user|account|password|signup|sign[ -]?in|sign[ -]?up|sso)\b/i,
    contextFile: 'context/capabilities/authentication-sessions.md',
  },
  {
    id: 'maps',
    label: 'Maps / Geolocation',
    description: 'Map views, location, nearby search',
    keywords: /\b(map|maps|location|geo|nearby|gps|coordinates|lat(itude)?|lng|long(itude)?)\b/i,
    contextFile: 'context/capabilities/maps-geolocation.md',
  },
  {
    id: 'payments',
    label: 'Payments',
    description: 'Stripe, M-Pesa, checkout, pricing',
    keywords: /\b(pay|paid|payment|m[-]?pesa|stripe|card|checkout|invoice|price|pricing|billing|charge|refund)\b/i,
    contextFile: 'context/capabilities/payments.md',
  },
  {
    id: 'realtime',
    label: 'Real-time',
    description: 'Live updates, WebSockets, alerts',
    keywords: /\b(realtime|real[ -]?time|live|websocket|sse|push|alert|alerts|stream|streaming|dashboard|notification|notifications)\b/i,
    contextFile: 'context/capabilities/realtime-features.md',
  },
  {
    id: 'search',
    label: 'Search / Filtering',
    description: 'Catalog browsing, filters, full-text search',
    keywords: /\b(search|find|filter|filters|filtering|browse|catalog|catalogue|sort|query)\b/i,
    contextFile: 'context/capabilities/search-filtering.md',
  },
  {
    id: 'charts',
    label: 'Charts / Analytics',
    description: 'Dashboards, reports, trends',
    keywords: /\b(chart|charts|analytics|stats|statistics|report|reports|trend|trends|metric|metrics|kpi|graph|visualization|insights)\b/i,
    contextFile: 'context/capabilities/charts-analytics.md',
  },
  {
    id: 'upload',
    label: 'File Upload',
    description: 'Images, media, document upload',
    keywords: /\b(upload|uploads|file|files|image|images|photo|photos|media|attachment|attachments|s3|cdn|storage)\b/i,
    contextFile: 'context/capabilities/file-upload-storage.md',
  },
  {
    id: 'ecommerce',
    label: 'E-commerce',
    description: 'Products, cart, orders, inventory',
    keywords: /\b(product|products|cart|shop|shopping|order|orders|inventory|store|storefront|sku|merch|merchant)\b/i,
    contextFile: 'context/capabilities/ecommerce-storefront.md',
  },
  {
    id: 'ai',
    label: 'AI / Content',
    description: 'LLM prompts, AI generation, content tooling',
    keywords: /\b(ai|llm|gpt|claude|prompt|prompts|generate|generation|generative|openai|anthropic|chatbot|copilot|embedding|content engine)\b/i,
    contextFile: 'context/capabilities/ai-content-generation.md',
  },
  {
    id: 'forms',
    label: 'Forms / Wizards',
    description: 'Multi-step forms, surveys, validation',
    keywords: /\b(form|forms|wizard|wizards|multi[ -]?step|survey|surveys|questionnaire|onboarding|validation|input fields?)\b/i,
    contextFile: 'context/capabilities/forms-validation.md',
  },
]

export function detectCapabilities(text: string): Set<string> {
  const hits = new Set<string>()
  for (const cap of CAPABILITIES) {
    if (cap.keywords.test(text)) hits.add(cap.id)
  }
  return hits
}

export function inferProjectName(text: string, filename?: string): string {
  const trimmed = text.trim()
  if (!trimmed) return filename ? cleanName(stripExt(filename)) : ''

  if (trimmed.startsWith('{')) {
    try {
      const parsed = JSON.parse(trimmed) as { name?: string; description?: string }
      if (parsed.name) return cleanName(parsed.name)
      if (parsed.description) {
        const m = parsed.description.match(/([A-Za-z][A-Za-z0-9]+)\s+(app|system|platform|tool|dashboard|portal|tracker|service|marketplace|engine)/i)
        if (m) return cleanName(m[1])
      }
    } catch {
      // not valid JSON yet — continue
    }
  }

  const headingMatch = trimmed.match(/^#\s+(.+?)$/m)
  if (headingMatch) {
    const headingName = headingMatch[1].split(/[—\-:]/)[0].trim()
    if (headingName) return cleanName(headingName)
  }

  const sample = trimmed.slice(0, 2000)
  const m = sample.match(/([A-Za-z][A-Za-z0-9]+)\s+(app|system|platform|tool|dashboard|portal|tracker|service|marketplace|engine)/i)
  if (m) return cleanName(m[1])

  if (filename) return cleanName(stripExt(filename))
  return ''
}

function stripExt(name: string): string {
  return name.replace(/\.[^.]+$/, '')
}

function cleanName(raw: string): string {
  return raw
    .toLowerCase()
    .replace(/[_\s]+/g, '-')
    .replace(/[^a-z0-9-]/g, '')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
}
