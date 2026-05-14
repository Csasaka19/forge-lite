import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { CAPABILITIES } from '@/lib/capabilities'
import type { ScaffoldedFile } from '@/lib/types'

interface StepNextStepsProps {
  projectName: string
  capabilities: Set<string>
  files: ScaffoldedFile[]
  onReset: () => void
}

interface CommandLine {
  prompt: string
  command: string
  hint: string
}

function buildCommands(projectName: string, capabilities: Set<string>): CommandLine[] {
  const lines: CommandLine[] = [
    {
      prompt: '$',
      command: `cd ~/projects/${projectName}`,
      hint: 'Move into the project',
    },
    {
      prompt: '$',
      command: 'claude',
      hint: 'Launch Claude Code',
    },
    {
      prompt: '>',
      command: '/build-feature scaffold the project and build the home page',
      hint: 'Start the React + Vite scaffold',
    },
  ]
  if (capabilities.size > 0) {
    const names = Array.from(capabilities)
      .map((id) => CAPABILITIES.find((c) => c.id === id)?.label)
      .filter(Boolean)
      .join(', ')
    lines.push({
      prompt: '>',
      command: `Read the linked capability guides under context/capabilities/ before wiring ${names}.`,
      hint: 'Prime the model on the linked guides',
    })
  }
  lines.push({
    prompt: '>',
    command: '/review',
    hint: 'After a few features, audit what is built vs the spec',
  })
  return lines
}

export function StepNextSteps({ projectName, capabilities, files, onReset }: StepNextStepsProps) {
  const [copied, setCopied] = useState<number | null>(null)
  const commands = buildCommands(projectName, capabilities)

  function copy(text: string, idx: number) {
    void navigator.clipboard.writeText(text)
    setCopied(idx)
    window.setTimeout(() => setCopied(null), 1400)
  }

  const linkedCaps = Array.from(capabilities)
    .map((id) => CAPABILITIES.find((c) => c.id === id))
    .filter((c): c is NonNullable<typeof c> => Boolean(c))

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>
            <span className="text-primary">✓</span> Project ready
          </CardTitle>
          <CardDescription>
            <code className="font-mono">~/projects/{projectName}</code> is scaffolded and primed.
          </CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-3">
          <div className="rounded-md border border-border bg-card p-3">
            <div className="font-mono text-xs uppercase tracking-wider text-muted-foreground">Files</div>
            <div className="mt-1 text-2xl font-semibold">{files.length}</div>
          </div>
          <div className="rounded-md border border-border bg-card p-3">
            <div className="font-mono text-xs uppercase tracking-wider text-muted-foreground">Capabilities</div>
            <div className="mt-1 text-2xl font-semibold">{capabilities.size}</div>
          </div>
          <div className="rounded-md border border-border bg-card p-3">
            <div className="font-mono text-xs uppercase tracking-wider text-muted-foreground">Stack</div>
            <div className="mt-1 text-sm font-semibold">React + Vite</div>
          </div>
        </CardContent>
      </Card>

      {linkedCaps.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">Linked capability guides</CardTitle>
            <CardDescription>Already copied into the project for the agent to read.</CardDescription>
          </CardHeader>
          <CardContent className="flex flex-wrap gap-2">
            {linkedCaps.map((cap) => (
              <Badge key={cap.id} variant="secondary" className="font-mono text-xs">
                {cap.contextFile.split('/').pop()}
              </Badge>
            ))}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Next, in your terminal</CardTitle>
          <CardDescription>Click any line to copy.</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-2">
            {commands.map((c, i) => (
              <button
                key={i}
                onClick={() => copy(c.command, i)}
                className="group flex w-full items-start gap-3 rounded-md border border-border bg-muted/30 px-3 py-2 text-left font-mono text-sm transition-colors hover:border-primary hover:bg-muted/60"
              >
                <span className="select-none text-primary">{c.prompt}</span>
                <span className="flex-1 break-all">{c.command}</span>
                <span className="hidden text-xs text-muted-foreground sm:block">
                  {copied === i ? 'copied!' : c.hint}
                </span>
              </button>
            ))}
          </div>
        </CardContent>
      </Card>

      <div className="flex justify-end">
        <Button variant="outline" onClick={onReset}>
          Start another project
        </Button>
      </div>
    </div>
  )
}
