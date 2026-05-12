# Forms & Wizards

How to build single-step and multi-step forms users can actually complete. Read before adding any input that the user has to fill out and submit.

## Stack

- **`react-hook-form`** for state, validation, performance.
- **`@hookform/resolvers/zod`** for schema-driven validation.
- **`zod`** for the schema (one source of truth for types and validation).

```bash
npm install react-hook-form @hookform/resolvers zod
```

## Single Form Pattern

```tsx
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'

const schema = z.object({
  name: z.string().min(1, 'Name is required').max(100),
  email: z.string().email(),
  phone: z.string().regex(/^\+\d{10,15}$/, 'Use international format'),
})

type Values = z.infer<typeof schema>

export function ContactForm() {
  const { register, handleSubmit, formState: { errors, isSubmitting }, setError } =
    useForm<Values>({ resolver: zodResolver(schema), mode: 'onBlur' })

  const onSubmit = async (values: Values) => {
    try {
      await api('/contacts', { method: 'POST', body: JSON.stringify(values) })
    } catch (err) {
      if (err instanceof ApiError && err.code === 'EMAIL_TAKEN') {
        setError('email', { message: 'Already used' })
      } else throw err
    }
  }

  return (
    <form onSubmit={handleSubmit(onSubmit)} noValidate>
      <Field label="Name" error={errors.name?.message}>
        <input {...register('name')} aria-invalid={!!errors.name} />
      </Field>
      <Field label="Email" error={errors.email?.message}>
        <input type="email" {...register('email')} aria-invalid={!!errors.email} />
      </Field>
      <Field label="Phone" error={errors.phone?.message}>
        <input type="tel" {...register('phone')} aria-invalid={!!errors.phone} />
      </Field>
      <button disabled={isSubmitting}>Send</button>
    </form>
  )
}
```

### Rules

- **Schema is the source of truth.** Derive types with `z.infer`. Validation lives once.
- **`mode: 'onBlur'`.** Validating on every keystroke is hostile. Show errors after the user moves on.
- **`noValidate` on the `<form>`.** Lets RHF own validation; native browser bubbles get out of the way.
- **Map server errors to `setError`.** Show field-level errors when the server rejects a value.

## Multi-Step Wizard

Split a long flow into focused steps. One concern per screen. Persist progress.

```tsx
const wizardSchema = z.object({
  account: z.object({
    email: z.string().email(),
    password: z.string().min(12),
  }),
  profile: z.object({
    name: z.string().min(1),
    phone: z.string().regex(/^\+\d{10,15}$/),
  }),
  preferences: z.object({
    newsletter: z.boolean(),
    timezone: z.string(),
  }),
})

type Wizard = z.infer<typeof wizardSchema>

type Step = 'account' | 'profile' | 'preferences' | 'review'

const stepSchemas: Record<Exclude<Step, 'review'>, z.ZodTypeAny> = {
  account: wizardSchema.shape.account,
  profile: wizardSchema.shape.profile,
  preferences: wizardSchema.shape.preferences,
}

export function SignupWizard() {
  const [step, setStep] = useState<Step>('account')
  const [draft, setDraft] = usePersistedDraft<Partial<Wizard>>('signup-draft', {})

  const form = useForm<Wizard>({
    resolver: zodResolver(stepSchemas[step] ?? wizardSchema),
    defaultValues: draft,
  })

  const next = async () => {
    const ok = await form.trigger()
    if (!ok) return
    setDraft({ ...draft, ...form.getValues() })
    setStep(advance(step))
  }

  // ...
}
```

### Rules

- **One Zod schema, sliced per step.** Validate only the current step's fields on `Next`.
- **State lives in `react-hook-form`**, persisted to localStorage on step transitions.
- **Progress indicator** — show "Step 2 of 4" so users know how much is left.
- **Back button preserves data.** Don't clear values when navigating back.
- **No skip-forward.** Validate previous steps before allowing a jump ahead.
- **Final submit** runs the full schema once more — defense against partial state.

## Conditional Fields

Show fields only when relevant:

```tsx
const watchedType = watch('type')

{watchedType === 'business' && (
  <>
    <input {...register('companyName')} />
    <input {...register('vatNumber')} />
  </>
)}
```

For schema, use Zod's `discriminatedUnion` or `superRefine`:

```ts
const schema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('personal'), name: z.string() }),
  z.object({ type: z.literal('business'), companyName: z.string(), vatNumber: z.string() }),
])
```

Conditional validation that adapts to the chosen branch — no manual `if` chains in the resolver.

### `useFieldArray`

For dynamic lists (line items, attachments):

```tsx
const { fields, append, remove } = useFieldArray({ control, name: 'lineItems' })

{fields.map((field, i) => (
  <div key={field.id}>
    <input {...register(`lineItems.${i}.name`)} />
    <input type="number" {...register(`lineItems.${i}.qty`, { valueAsNumber: true })} />
    <button onClick={() => remove(i)}>Remove</button>
  </div>
))}
<button onClick={() => append({ name: '', qty: 1 })}>Add item</button>
```

`field.id` (RHF-generated) is the React key. Index works but breaks on reorder.

## Draft Saving

```ts
function usePersistedDraft<T>(key: string, initial: T) {
  const [v, setV] = useState<T>(() => {
    try { return JSON.parse(localStorage.getItem(key) ?? '') as T } catch { return initial }
  })
  useEffect(() => { localStorage.setItem(key, JSON.stringify(v)) }, [key, v])
  return [v, setV] as const
}
```

### Rules

- **Save on step transitions, not every keystroke.** Reduces writes; less risk of partial state.
- **Clear on successful submit.** Don't leave a stale draft for the next session.
- **Version the draft.** If the schema changes between sessions, old drafts may be invalid. `{ version: 2, data: ... }` lets you migrate or discard.
- **Never persist secrets.** Passwords, payment data, OTPs — wipe at session boundary, never write to localStorage.

For longer flows (job applications, mortgage forms), persist server-side per user — localStorage doesn't survive a device switch.

## Address Autocomplete

```bash
npm install use-debounce       # or use built-in deferred value
```

Use a geocoding API. Don't roll your own.

- **Google Places Autocomplete** — most complete, expensive.
- **Mapbox Geocoding** — free tier reasonable, attribution required.
- **MapTiler / LocationIQ** — cheaper alternatives.
- **Nominatim (OSM)** — free but slow, low rate limit, manual format.

```tsx
function AddressInput({ onSelect }: Props) {
  const [input, setInput] = useState('')
  const deferred = useDeferredValue(input)
  const [results, setResults] = useState<AddressSuggestion[]>([])

  useEffect(() => {
    if (deferred.length < 3) return setResults([])
    const ctrl = new AbortController()
    fetch(`/api/geocode?q=${encodeURIComponent(deferred)}`, { signal: ctrl.signal })
      .then((r) => r.json()).then(setResults).catch(() => {})
    return () => ctrl.abort()
  }, [deferred])

  return (
    <Combobox onSelect={onSelect}>
      <Combobox.Input value={input} onChange={(e) => setInput(e.target.value)} />
      <Combobox.List>
        {results.map((r) => <Combobox.Option key={r.id} value={r}>{r.label}</Combobox.Option>)}
      </Combobox.List>
    </Combobox>
  )
}
```

Proxy through your server — never expose your geocoding API key to the client.

## Form Analytics

Track where users drop off.

### Events to Capture

- `form_started` — user typed into the first field.
- `step_completed` — for wizards.
- `field_error` — by field name and error type (helps spot bad copy or validation that's too strict).
- `form_submitted` — successful submit.
- `form_abandoned` — left the page mid-flow.

```ts
const onError = (errors: FieldErrors) => {
  Object.entries(errors).forEach(([field, err]) => {
    track('field_error', { field, type: err?.type })
  })
}
handleSubmit(onSubmit, onError)
```

### Privacy

Never log field **values** — just metadata (field name, error type, time spent). Form analytics that capture content cross PII lines fast.

## Accessibility

- **Every input has a `<label htmlFor>`.** Always. See `context/system/accessibility-deep.md`.
- **Errors are announced.** `role="alert"` on error messages; `aria-invalid` on the input; `aria-describedby` pointing to the error.
- **Disabled submit button while submitting**, but don't disable until errors are surfaced — disabled submit + invisible errors confuses users.
- **Focus management** — on step change in a wizard, move focus to the new step's heading (`tabIndex={-1}` on the heading + `.focus()`).

## Common Mistakes

- **Validating on every keystroke.** Aggressive, frustrating. Use `onBlur`.
- **Custom validation in the resolver instead of Zod.** Logic drifts from types. Schema first.
- **Different schema for client and server.** Maintenance trap. Share or generate from one source.
- **Single 30-field form.** Use a wizard or a sectioned layout.
- **No draft saving on long forms.** User refreshes; loses everything.
- **Saving secrets to localStorage.** Passwords, tokens. Never.
- **No analytics on drop-off.** Can't improve what you can't measure.
- **Inline server errors without field mapping.** "Email already used" appears at the top of the form; user doesn't know which field. Map to `setError(field, ...)`.
- **`reset()` without preserving touched values.** RHF resets validation state; users see their inputs cleared. Use sparingly.
- **`useFieldArray` keyed by index.** Reordering swaps values. Use the generated `field.id`.
- **No back button in wizards.** Users can't fix earlier mistakes.
- **Validating only on submit.** User fills 5 minutes of fields, submit fails, no idea where. Validate on blur per field.
- **Hard-coded address fields.** Internationally varied. Use a geocoding service for autocomplete.
- **Forgetting numeric coercion.** `<input type="number">` still returns strings. Use `valueAsNumber: true`.
- **Async validation without debounce.** "Check if email is taken" fires on every keystroke. Debounce, cancel stale.
