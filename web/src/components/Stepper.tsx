import type { Step } from '@/lib/types'

const STEPS: { n: Step; label: string }[] = [
  { n: 1, label: 'Input' },
  { n: 2, label: 'Capabilities' },
  { n: 3, label: 'Scaffolding' },
  { n: 4, label: 'Next steps' },
]

interface StepperProps {
  current: Step
}

export function Stepper({ current }: StepperProps) {
  return (
    <ol className="flex items-center gap-3 text-sm">
      {STEPS.map((s, idx) => {
        const isActive = s.n === current
        const isDone = s.n < current
        return (
          <li key={s.n} className="flex items-center gap-3">
            <div className="flex items-center gap-2">
              <span
                className={[
                  'flex h-7 w-7 items-center justify-center rounded-full font-mono text-xs transition-colors',
                  isActive && 'bg-primary text-primary-foreground',
                  isDone && 'bg-primary/20 text-primary',
                  !isActive && !isDone && 'bg-muted text-muted-foreground',
                ]
                  .filter(Boolean)
                  .join(' ')}
              >
                {isDone ? '✓' : s.n}
              </span>
              <span
                className={[
                  'hidden font-medium sm:inline',
                  isActive ? 'text-foreground' : 'text-muted-foreground',
                ].join(' ')}
              >
                {s.label}
              </span>
            </div>
            {idx < STEPS.length - 1 && (
              <span className={`h-px w-6 sm:w-10 ${isDone ? 'bg-primary/40' : 'bg-border'}`} />
            )}
          </li>
        )
      })}
    </ol>
  )
}
