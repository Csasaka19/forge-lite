# Internationalization (i18n)

How to build apps that work across languages, locales, and writing systems. Read before adding any user-facing string.

## Decision Tree: When to Plan for i18n

| Situation | Approach |
|---|---|
| Single-language MVP, no plans to translate | **Still externalize strings** to a single file — refactor later is painful |
| Multi-locale launch | **Full i18n stack from day one** — keys, plurals, formatters |
| English + one or two languages, similar grammar | **react-i18next** with simple JSON files |
| Many languages, RTL, complex plurals | **react-i18next** + ICU MessageFormat |
| Marketing site, SSR / SSG | **next-intl** or framework-native i18n |

Even monolingual apps benefit from externalized strings: copy edits become a content task, not a code task. Plan i18n at scaffold time.

## Stack

### Web

- **react-i18next** + **i18next** — the default. Battle-tested, large ecosystem.
- **next-intl** for Next.js apps — better SSR integration.
- **FormatJS / react-intl** — ICU MessageFormat purist option. Heavier API.

### Mobile (React Native)

- **i18next** + **expo-localization** for the device locale.

```bash
npm install i18next react-i18next i18next-browser-languagedetector
# RN:
npm install i18next react-i18next expo-localization
```

## Setup

```ts
// src/lib/i18n.ts
import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import LanguageDetector from 'i18next-browser-languagedetector'
import en from '../locales/en/common.json'
import sw from '../locales/sw/common.json'

i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources: {
      en: { common: en },
      sw: { common: sw },
    },
    fallbackLng: 'en',
    supportedLngs: ['en', 'sw'],
    defaultNS: 'common',
    interpolation: { escapeValue: false },  // React already escapes
  })

export default i18n
```

Mount at the app root:

```tsx
import './lib/i18n'
import { I18nextProvider } from 'react-i18next'

<I18nextProvider i18n={i18n}>
  <App />
</I18nextProvider>
```

## Translation File Structure

One folder per locale, one file per namespace.

```
src/locales/
├── en/
│   ├── common.json        # site-wide strings
│   ├── auth.json          # login, signup, password reset
│   ├── machines.json      # machine feature
│   └── errors.json        # error messages
├── sw/
│   ├── common.json
│   └── ...
└── fr/
    └── ...
```

Split by feature, not by page. Pages compose; features are stable.

### Key Naming

Use `namespace.section.key`. Stable, searchable, scannable.

```json
// en/machines.json
{
  "list": {
    "title": "Machines near you",
    "empty": "No machines found in this area.",
    "filters": {
      "all": "All",
      "online": "Online",
      "maintenance": "Maintenance"
    }
  },
  "detail": {
    "operatingHours": "Operating hours",
    "lastServiced": "Last serviced {{date}}"
  }
}
```

Rules:

- **Keys are stable identifiers**, not the English text. Wrong: `"Click here to continue"`. Right: `"actions.continue"`.
- **camelCase or kebab-case** in keys. Don't mix.
- **Group by feature, then by section**, then by item — never deeper than 3–4 levels.
- **Never put a sentence in a key.** `"machinesNearYouTitle"` is a smell — the value should hold the sentence.

## Usage in Components

```tsx
import { useTranslation } from 'react-i18next'

function MachineList() {
  const { t } = useTranslation('machines')
  return (
    <section>
      <h1>{t('list.title')}</h1>
      {machines.length === 0 && <p>{t('list.empty')}</p>}
    </section>
  )
}
```

### Interpolation — Never Concatenate

```tsx
// Bad — concatenation, breaks word order in many languages
<p>{t('detail.servicedOn')} {formatDate(machine.lastServiced)}</p>

// Good — interpolation, translator controls position
<p>{t('detail.lastServiced', { date: formatDate(machine.lastServiced) })}</p>
```

JSON:

```json
{ "detail": { "lastServiced": "Last serviced {{date}}" } }
```

In Swahili or Japanese, the date placement might differ — interpolation lets the translator move it. Concatenation hard-codes English word order.

## Pluralization

English has two plural forms (singular, plural). Other languages have up to six (Arabic, Welsh, Russian). Always use ICU plural rules — never `if (count === 1)`.

```json
// en/machines.json
{
  "results": "{{count}} machine found",
  "results_other": "{{count}} machines found"
}
```

```tsx
t('results', { count: machines.length })
// 1 → "1 machine found"
// 5 → "5 machines found"
```

For complex categories (zero, one, few, many, other), define each:

```json
{
  "results_zero": "No machines",
  "results_one": "{{count}} machine",
  "results_other": "{{count}} machines"
}
```

i18next picks the right form based on the locale's CLDR rules.

## Date and Time Formatting

Use the **`Intl` API**, never `moment.js`. `Intl` is built into the runtime, locale-aware, free.

```ts
export function formatDate(d: Date, locale: string) {
  return new Intl.DateTimeFormat(locale, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
  }).format(d)
}

formatDate(new Date(), 'en')   // "Nov 12, 2026"
formatDate(new Date(), 'sw')   // "12 Nov 2026"
formatDate(new Date(), 'ja')   // "2026年11月12日"
```

For relative time ("3 hours ago"):

```ts
const rtf = new Intl.RelativeTimeFormat(locale, { numeric: 'auto' })
rtf.format(-3, 'hour')   // "3 hours ago"
```

### Rules

- **Never store formatted dates.** Store ISO strings or Unix timestamps; format at render time.
- **Always store UTC.** Convert to the user's timezone at the edge.
- **Get locale from i18n**, not from the browser, so user preference wins.

```ts
const { i18n } = useTranslation()
formatDate(date, i18n.language)
```

## Currency Formatting

```ts
new Intl.NumberFormat('en-KE', { style: 'currency', currency: 'KES' }).format(2500)
// "KSh 2,500.00"

new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(2500)
// "$2,500.00"

new Intl.NumberFormat('ja-JP', { style: 'currency', currency: 'JPY' }).format(2500)
// "￥2,500"
```

Currency is a **separate** decision from locale. A Kenyan user might browse in English but pay in KES. Always pass the currency code explicitly — never infer from locale.

### Rules

- **Store amounts as integer minor units** (cents, sente). Format on display.
- **Currency code lives with the amount** in the data model. `{ amount: 2500, currency: 'KES' }`.
- **Never hard-code symbols** (`$`, `€`, `KSh`). `Intl.NumberFormat` knows them all.

## Number Formatting

```ts
new Intl.NumberFormat('en').format(1234567.89)   // "1,234,567.89"
new Intl.NumberFormat('de').format(1234567.89)   // "1.234.567,89"
new Intl.NumberFormat('fr').format(1234567.89)   // "1 234 567,89"
```

Decimal separator, thousands separator, digit grouping all vary. Never format with `.toFixed()` for display.

## RTL Support

Arabic, Hebrew, Persian, Urdu read right-to-left. Layouts mirror.

### Set the Direction

```tsx
useEffect(() => {
  document.documentElement.dir = ['ar', 'he', 'fa', 'ur'].includes(i18n.language) ? 'rtl' : 'ltr'
  document.documentElement.lang = i18n.language
}, [i18n.language])
```

### Use Logical Properties, Not Physical

```css
/* Bad — locks layout to LTR */
.card { margin-left: 16px; padding-right: 24px; text-align: left; }

/* Good — flips with `dir` */
.card { margin-inline-start: 16px; padding-inline-end: 24px; text-align: start; }
```

Tailwind has RTL-friendly utilities: `ms-4` (margin-inline-start), `me-4` (margin-inline-end), `ps-4`, `pe-4`, plus `start-0` / `end-0` for positioning. Use them.

### Icons That Indicate Direction

Arrow icons, chevrons, "back" buttons must flip in RTL. Use CSS:

```css
[dir="rtl"] .icon-back { transform: scaleX(-1); }
```

Symmetric icons (search, heart, settings) don't flip.

## Content Extraction Workflow

### From Code to Translation File

Two approaches:

1. **Write keys, hand-author translations.** Simpler for small projects.
2. **Mark strings in code, extract automatically.** Better for large projects.

For extraction, `i18next-parser`:

```bash
npx i18next-parser 'src/**/*.{ts,tsx}' --config i18next-parser.config.js
```

Configures output paths, key separators, default values. Run as a pre-commit hook so new keys land in translation files automatically.

### Sending to Translators

- **Hand them JSON.** Translators are fluent in it.
- **Provide context** — a comment file or screenshots showing where each string appears.
- **Never ship machine translation to production** without human review. Auto-translation is for previews and internal staging.
- **Use a translation management system** (Lokalise, Crowdin, Phrase) once you have > 200 strings or > 3 languages.

## Fallback Chains

```ts
i18n.init({
  fallbackLng: {
    'fr-CA': ['fr', 'en'],
    'fr-FR': ['fr', 'en'],
    'default': ['en'],
  },
})
```

- Specific locale falls back to the language family, then to a global default.
- Missing keys log a warning in dev. Add a custom `missingKeyHandler` to report production misses to your logger.

```ts
i18n.init({
  saveMissing: env.NODE_ENV !== 'production',
  missingKeyHandler: (lngs, ns, key) => {
    logger.warn({ lngs, ns, key }, 'Missing translation')
  },
})
```

## Mobile (Expo) Specifics

```ts
import * as Localization from 'expo-localization'

const deviceLocale = Localization.getLocales()[0]
const currency = deviceLocale.currencyCode    // 'KES', 'USD'
const region = deviceLocale.regionCode        // 'KE', 'US'
```

- **Initialize i18n with the device locale** at app start.
- **Persist user override** in MMKV — user choice wins over device.
- **Don't trust device locale for currency.** Users may have an iPhone in English-US but live in Nairobi — let them pick.

## Common Mistakes

- **Concatenating translated strings.** Locks word order to English. Always interpolate.
- **`if (count === 1)` for pluralization.** Breaks in Russian, Arabic, Welsh. Use ICU plural keys.
- **`moment.js` for formatting.** Heavy, unmaintained, locale-fragile. Use `Intl`.
- **Hard-coded currency symbols.** Doesn't survive a market expansion.
- **Storing formatted dates in the database.** Format at render. Store ISO + timezone or UTC.
- **English keys** like `"Click here"`. Refactor when the wording changes. Use stable identifiers.
- **One enormous `translation.json`.** Hard to review. Split by feature.
- **Translator gets just the JSON, no context.** Mistranslations follow. Provide screenshots and notes.
- **No fallback chain.** `fr-CA` missing a key shows the raw key. Configure fallbacks.
- **Forgetting RTL.** Arabic launch reveals every left/right margin in the codebase. Use logical properties from the start.
- **`text-align: left` everywhere.** Doesn't flip. Use `text-align: start`.
- **Icons that don't flip in RTL.** Back arrows pointing the wrong way. Audit at launch.
- **Loading every locale at boot.** Bundle bloat. Code-split locales and load on demand.
- **Translating dynamic data.** Don't translate names, content the user wrote, or third-party data. UI chrome only.
- **Treating `lang` and `locale` as the same.** `en-US` and `en-GB` differ in date format. Be explicit.
- **No way to override device locale.** Users with a multilingual life can't pick their preferred app language.
