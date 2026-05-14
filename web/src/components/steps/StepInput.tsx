import { useEffect, useRef, useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { detectCapabilities, inferProjectName } from '@/lib/capabilities'

interface Fixture {
  label: string
  description: string
  filename: string
}

const FIXTURES: Fixture[] = [
  {
    label: 'Water vending finder',
    description: 'Structured JSON spec — 3 user types, 9 pages, full data model.',
    filename: 'sample-water-vending.json',
  },
  {
    label: 'Efficiency tracker notes',
    description: 'Raw markdown notes — estimated vs actual hours, manager rollups.',
    filename: 'efficiency-tracker-notes.txt',
  },
]

interface StepInputProps {
  content: string
  setContent: (value: string) => void
  projectName: string
  setProjectName: (value: string) => void
  sourceFilename: string | null
  setSourceFilename: (value: string | null) => void
  onAutoDetect: (detected: Set<string>) => void
  onNext: () => void
}

export function StepInput({
  content,
  setContent,
  projectName,
  setProjectName,
  sourceFilename,
  setSourceFilename,
  onAutoDetect,
  onNext,
}: StepInputProps) {
  const fileInput = useRef<HTMLInputElement>(null)
  const [nameTouched, setNameTouched] = useState(false)
  const [activeFixture, setActiveFixture] = useState<string | null>(null)
  const [dragging, setDragging] = useState(false)

  useEffect(() => {
    if (!nameTouched) {
      const inferred = inferProjectName(content, sourceFilename ?? undefined)
      setProjectName(inferred)
    }
    onAutoDetect(detectCapabilities(content))
  }, [content, nameTouched, sourceFilename, setProjectName, onAutoDetect])

  async function loadFixture(fix: Fixture) {
    const res = await fetch(`/${fix.filename}`)
    const text = await res.text()
    setContent(text)
    setSourceFilename(fix.filename)
    setActiveFixture(fix.filename)
    setNameTouched(false)
  }

  async function readFile(file: File) {
    const ok = /\.(txt|md|json|markdown|text)$/i.test(file.name)
    if (!ok) {
      alert('Supported formats: .txt, .md, .json')
      return
    }
    const text = await file.text()
    setContent(text)
    setSourceFilename(file.name)
    setActiveFixture(null)
    setNameTouched(false)
  }

  const canContinue = content.trim().length >= 20 && projectName.length > 0

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Paste a description</CardTitle>
          <CardDescription>
            Notes, a JSON spec, or a markdown brief. Anything that describes what you want to build.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <Textarea
            value={content}
            onChange={(e) => {
              setContent(e.target.value)
              setActiveFixture(null)
              if (!nameTouched) setSourceFilename(null)
            }}
            placeholder="A water vending machine finder app for Nairobi residents. Users locate the nearest machine, check availability, and pay with M-Pesa..."
            className="min-h-[160px] font-mono text-sm"
          />
          <div
            className={[
              'flex flex-col items-center justify-center gap-2 rounded-md border border-dashed px-4 py-6 text-center text-sm transition-colors',
              dragging ? 'border-primary bg-primary/5' : 'border-border bg-muted/30',
            ].join(' ')}
            onDragOver={(e) => {
              e.preventDefault()
              setDragging(true)
            }}
            onDragLeave={() => setDragging(false)}
            onDrop={(e) => {
              e.preventDefault()
              setDragging(false)
              const file = e.dataTransfer.files[0]
              if (file) void readFile(file)
            }}
          >
            <span className="text-muted-foreground">
              Drop a <span className="font-mono text-foreground">.txt</span>,{' '}
              <span className="font-mono text-foreground">.md</span>, or{' '}
              <span className="font-mono text-foreground">.json</span> file here
            </span>
            <Button variant="outline" size="sm" onClick={() => fileInput.current?.click()}>
              Or choose a file
            </Button>
            <input
              ref={fileInput}
              type="file"
              accept=".txt,.md,.markdown,.json,.text"
              className="hidden"
              onChange={(e) => {
                const f = e.target.files?.[0]
                if (f) void readFile(f)
                e.target.value = ''
              }}
            />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Try a sample</CardTitle>
          <CardDescription>Pre-baked fixtures from the forge-lite repo.</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-3 sm:grid-cols-2">
            {FIXTURES.map((fix) => (
              <button
                key={fix.filename}
                onClick={() => void loadFixture(fix)}
                className={[
                  'group rounded-md border bg-card p-4 text-left transition-all hover:border-primary hover:shadow-sm',
                  activeFixture === fix.filename ? 'border-primary ring-2 ring-primary/20' : 'border-border',
                ].join(' ')}
              >
                <div className="mb-1 font-medium">{fix.label}</div>
                <p className="text-sm text-muted-foreground">{fix.description}</p>
                <code className="mt-2 inline-block font-mono text-[11px] text-muted-foreground">
                  fixtures/{fix.filename}
                </code>
              </button>
            ))}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Project name</CardTitle>
          <CardDescription>Auto-detected from your input. Editable.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-2">
          <Label htmlFor="project-name" className="font-mono text-xs uppercase tracking-wider text-muted-foreground">
            ~/projects/
          </Label>
          <Input
            id="project-name"
            value={projectName}
            onChange={(e) => {
              setNameTouched(true)
              setProjectName(
                e.target.value
                  .toLowerCase()
                  .replace(/[_\s]+/g, '-')
                  .replace(/[^a-z0-9-]/g, ''),
              )
            }}
            placeholder="my-app"
            className="font-mono"
          />
        </CardContent>
      </Card>

      <div className="flex justify-end">
        <Button onClick={onNext} disabled={!canContinue} size="lg">
          Next: Capabilities →
        </Button>
      </div>
    </div>
  )
}
