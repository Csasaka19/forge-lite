import { useCallback, useEffect, useState } from 'react'
import { Logo } from '@/components/Logo'
import { Stepper } from '@/components/Stepper'
import { StepTransition } from '@/components/StepTransition'
import { StepInput } from '@/components/steps/StepInput'
import { StepCapabilities } from '@/components/steps/StepCapabilities'
import { StepScaffolding } from '@/components/steps/StepScaffolding'
import { StepNextSteps } from '@/components/steps/StepNextSteps'
import { Button } from '@/components/ui/button'
import type { ScaffoldedFile, Step, TargetFiles, TechStack } from '@/lib/types'

function App() {
  const [step, setStep] = useState<Step>(1)
  const [content, setContent] = useState('')
  const [sourceFilename, setSourceFilename] = useState<string | null>(null)
  const [projectName, setProjectName] = useState('')
  const [capabilities, setCapabilities] = useState<Set<string>>(new Set())
  const [detectedCapabilities, setDetectedCapabilities] = useState<Set<string>>(new Set())
  const [targetFiles, setTargetFiles] = useState<TargetFiles>('both')
  const [techStack, setTechStack] = useState<TechStack>('react-vite')
  const [scaffoldedFiles, setScaffoldedFiles] = useState<ScaffoldedFile[]>([])
  const [dark, setDark] = useState(false)

  useEffect(() => {
    document.documentElement.classList.toggle('dark', dark)
  }, [dark])

  const handleAutoDetect = useCallback((detected: Set<string>) => {
    setDetectedCapabilities(detected)
    setCapabilities((prev) => {
      if (prev.size === 0) return new Set(detected)
      const next = new Set(prev)
      for (const id of detected) next.add(id)
      return next
    })
  }, [])

  function toggleCapability(id: string) {
    setCapabilities((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function reset() {
    setStep(1)
    setContent('')
    setSourceFilename(null)
    setProjectName('')
    setCapabilities(new Set())
    setDetectedCapabilities(new Set())
    setTargetFiles('both')
    setTechStack('react-vite')
    setScaffoldedFiles([])
  }

  const handleScaffoldDone = useCallback((files: ScaffoldedFile[]) => {
    setScaffoldedFiles(files)
    setStep(4)
  }, [])

  return (
    <div className="min-h-screen bg-background text-foreground">
      <header className="sticky top-0 z-10 border-b border-border bg-background/80 backdrop-blur">
        <div className="mx-auto flex max-w-4xl items-center justify-between px-4 py-4">
          <div className="flex items-center gap-3">
            <Logo size={32} />
            <div>
              <div className="font-semibold leading-none">Forge Lite</div>
              <div className="mt-1 font-mono text-[11px] uppercase tracking-wider text-muted-foreground">
                Project scaffolder
              </div>
            </div>
          </div>
          <div className="flex items-center gap-4">
            <Stepper current={step} />
            <Button variant="ghost" size="sm" onClick={() => setDark((d) => !d)}>
              {dark ? '☀' : '☾'}
            </Button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-4xl px-4 py-10">
        <div className="mb-8 flex items-baseline justify-between">
          <h1 className="text-2xl font-semibold">
            <span className="font-mono text-sm text-muted-foreground">step {step}/4 ·</span>{' '}
            {step === 1 && 'Describe your project'}
            {step === 2 && 'Pick capabilities'}
            {step === 3 && 'Scaffolding'}
            {step === 4 && 'Ready to build'}
          </h1>
        </div>

        <StepTransition step={step}>
          {step === 1 && (
            <StepInput
              content={content}
              setContent={setContent}
              projectName={projectName}
              setProjectName={setProjectName}
              sourceFilename={sourceFilename}
              setSourceFilename={setSourceFilename}
              onAutoDetect={handleAutoDetect}
              onNext={() => setStep(2)}
            />
          )}
          {step === 2 && (
            <StepCapabilities
              capabilities={capabilities}
              detectedCapabilities={detectedCapabilities}
              toggleCapability={toggleCapability}
              targetFiles={targetFiles}
              setTargetFiles={setTargetFiles}
              techStack={techStack}
              setTechStack={setTechStack}
              onBack={() => setStep(1)}
              onScaffold={() => setStep(3)}
            />
          )}
          {step === 3 && (
            <StepScaffolding
              projectName={projectName}
              capabilities={capabilities}
              targetFiles={targetFiles}
              techStack={techStack}
              onDone={handleScaffoldDone}
            />
          )}
          {step === 4 && (
            <StepNextSteps
              projectName={projectName}
              capabilities={capabilities}
              files={scaffoldedFiles}
              onReset={reset}
            />
          )}
        </StepTransition>
      </main>

      <footer className="border-t border-border">
        <div className="mx-auto flex max-w-4xl items-center justify-between px-4 py-4 text-xs text-muted-foreground">
          <div className="font-mono">forge-lite/web · client-side demo</div>
          <div>
            <a
              href="https://github.com/Csasaka19/forge-lite"
              target="_blank"
              rel="noreferrer"
              className="hover:text-foreground"
            >
              github
            </a>
          </div>
        </div>
      </footer>
    </div>
  )
}

export default App
