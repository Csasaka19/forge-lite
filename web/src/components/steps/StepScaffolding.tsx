import { useEffect, useMemo, useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Progress } from '@/components/ui/progress'
import { CAPABILITIES } from '@/lib/capabilities'
import type { ScaffoldedFile, TargetFiles, TechStack } from '@/lib/types'

interface StepScaffoldingProps {
  projectName: string
  capabilities: Set<string>
  targetFiles: TargetFiles
  techStack: TechStack
  onDone: (files: ScaffoldedFile[]) => void
}

function planFiles(
  projectName: string,
  capabilities: Set<string>,
  targetFiles: TargetFiles,
  techStack: TechStack,
): ScaffoldedFile[] {
  const stackNote =
    techStack === 'react-vite'
      ? 'React + Vite + Tailwind + shadcn/ui'
      : techStack === 'react-native'
        ? 'Expo + React Native'
        : 'Next.js App Router'

  const files: ScaffoldedFile[] = [
    { path: `~/projects/${projectName}/`, size: 0, note: 'mkdir' },
    { path: `~/projects/${projectName}/CLAUDE.md`, size: 1240, note: 'project context' },
    { path: `~/projects/${projectName}/.gitignore`, size: 84 },
    { path: `~/projects/${projectName}/.claude/rules/react-conventions.md`, size: 412 },
    { path: `~/projects/${projectName}/.claude/commands/build-feature.md`, size: 680 },
    { path: `~/projects/${projectName}/.claude/commands/review.md`, size: 420 },
  ]

  if (targetFiles === 'both' || targetFiles === 'spec') {
    files.push({ path: `~/projects/${projectName}/docs/product-spec.md`, size: 3200, note: 'from input' })
  }
  if (targetFiles === 'both' || targetFiles === 'design') {
    files.push({ path: `~/projects/${projectName}/docs/design-brief.md`, size: 1500, note: 'from input' })
  }

  files.push(
    { path: `~/projects/${projectName}/docs/react-stack.md`, size: 5400, note: stackNote },
    { path: `~/projects/${projectName}/docs/design-system.md`, size: 2800 },
  )

  for (const id of capabilities) {
    const cap = CAPABILITIES.find((c) => c.id === id)
    if (!cap) continue
    files.push({
      path: `~/projects/${projectName}/${cap.contextFile}`,
      size: 4200 + Math.floor(Math.random() * 2000),
      note: `linked: ${cap.label}`,
    })
  }

  files.push({ path: `~/projects/${projectName}/.git/`, size: 0, note: 'git init' })

  return files
}

export function StepScaffolding({
  projectName,
  capabilities,
  targetFiles,
  techStack,
  onDone,
}: StepScaffoldingProps) {
  const plan = useMemo(
    () => planFiles(projectName, capabilities, targetFiles, techStack),
    [projectName, capabilities, targetFiles, techStack],
  )
  const [completed, setCompleted] = useState(0)

  useEffect(() => {
    if (completed >= plan.length) {
      const t = window.setTimeout(() => onDone(plan), 400)
      return () => window.clearTimeout(t)
    }
    const delay = 90 + Math.floor(Math.random() * 110)
    const t = window.setTimeout(() => setCompleted((c) => c + 1), delay)
    return () => window.clearTimeout(t)
  }, [completed, plan, onDone])

  const pct = plan.length === 0 ? 100 : Math.round((completed / plan.length) * 100)

  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>
            Scaffolding{' '}
            <code className="font-mono text-base text-primary">~/projects/{projectName}</code>
          </CardTitle>
          <CardDescription>
            {completed < plan.length
              ? 'Writing template files, linking context, initializing git…'
              : 'Done. Linked capability docs are below.'}
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          <div className="flex items-center gap-3">
            <Progress value={pct} className="flex-1" />
            <span className="w-12 text-right font-mono text-xs text-muted-foreground">{pct}%</span>
          </div>
          <div className="font-mono text-xs leading-relaxed text-muted-foreground">
            <span className="text-foreground">{completed}</span> / {plan.length} files
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Activity log</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="max-h-72 space-y-1 overflow-y-auto rounded-md bg-muted/40 p-3 font-mono text-xs">
            {plan.slice(0, completed).map((f, i) => (
              <div key={i} className="flex items-start gap-2 leading-relaxed">
                <span className="text-primary">+</span>
                <span className="flex-1 break-all">{f.path}</span>
                {f.note && <span className="text-muted-foreground">{f.note}</span>}
              </div>
            ))}
            {completed < plan.length && (
              <div className="flex items-start gap-2 leading-relaxed text-muted-foreground">
                <span className="animate-pulse">▍</span>
                <span>{plan[completed]?.path}</span>
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
