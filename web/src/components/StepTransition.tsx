import { useEffect, useState, type ReactNode } from 'react'

interface StepTransitionProps {
  step: number
  children: ReactNode
}

export function StepTransition({ step, children }: StepTransitionProps) {
  const [render, setRender] = useState({ step, children })
  const [phase, setPhase] = useState<'in' | 'out'>('in')

  useEffect(() => {
    if (step === render.step) {
      setRender({ step, children })
      return
    }
    setPhase('out')
    const t = window.setTimeout(() => {
      setRender({ step, children })
      setPhase('in')
    }, 180)
    return () => window.clearTimeout(t)
  }, [step, children, render.step])

  return (
    <div
      key={render.step}
      className={[
        'transition-all duration-200 ease-out',
        phase === 'in' ? 'translate-y-0 opacity-100' : 'pointer-events-none -translate-y-2 opacity-0',
      ].join(' ')}
    >
      {render.children}
    </div>
  )
}
