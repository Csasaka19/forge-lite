import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { CAPABILITIES } from '@/lib/capabilities'
import type { TargetFiles, TechStack } from '@/lib/types'

interface StepCapabilitiesProps {
  capabilities: Set<string>
  detectedCapabilities: Set<string>
  toggleCapability: (id: string) => void
  targetFiles: TargetFiles
  setTargetFiles: (value: TargetFiles) => void
  techStack: TechStack
  setTechStack: (value: TechStack) => void
  onBack: () => void
  onScaffold: () => void
}

export function StepCapabilities({
  capabilities,
  detectedCapabilities,
  toggleCapability,
  targetFiles,
  setTargetFiles,
  techStack,
  setTechStack,
  onBack,
  onScaffold,
}: StepCapabilitiesProps) {
  const detectedCount = detectedCapabilities.size
  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Detected capabilities</CardTitle>
          <CardDescription>
            {detectedCount > 0
              ? `Found ${detectedCount} capabilit${detectedCount === 1 ? 'y' : 'ies'} in your text. Toggle to include or exclude.`
              : 'No capabilities detected yet — toggle any you plan to use.'}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {CAPABILITIES.map((cap) => {
              const isOn = capabilities.has(cap.id)
              const wasDetected = detectedCapabilities.has(cap.id)
              return (
                <button
                  key={cap.id}
                  onClick={() => toggleCapability(cap.id)}
                  className={[
                    'group flex flex-col items-start gap-1 rounded-md border p-3 text-left transition-all',
                    isOn
                      ? 'border-primary bg-primary/5 shadow-sm'
                      : 'border-border bg-card hover:border-primary/40',
                  ].join(' ')}
                >
                  <div className="flex w-full items-center justify-between gap-2">
                    <span className={['font-medium', isOn ? 'text-foreground' : 'text-muted-foreground'].join(' ')}>
                      {cap.label}
                    </span>
                    <span
                      className={[
                        'flex h-4 w-4 items-center justify-center rounded-sm border text-[10px] font-bold transition-colors',
                        isOn ? 'border-primary bg-primary text-primary-foreground' : 'border-muted-foreground/40 text-transparent',
                      ].join(' ')}
                    >
                      ✓
                    </span>
                  </div>
                  <p className="text-xs text-muted-foreground">{cap.description}</p>
                  <code className="mt-1 font-mono text-[10px] text-muted-foreground">
                    {wasDetected ? 'auto-detected' : 'manual'}
                  </code>
                </button>
              )
            })}
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Generation options</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <div className="space-y-2">
            <Label className="font-mono text-xs uppercase tracking-wider text-muted-foreground">
              Target files
            </Label>
            <Select value={targetFiles} onValueChange={(v) => setTargetFiles(v as TargetFiles)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="both">Both spec + design brief</SelectItem>
                <SelectItem value="spec">Product spec only</SelectItem>
                <SelectItem value="design">Design brief only</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <div className="space-y-2">
            <Label className="font-mono text-xs uppercase tracking-wider text-muted-foreground">
              Tech stack
            </Label>
            <Select value={techStack} onValueChange={(v) => setTechStack(v as TechStack)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="react-vite">React + Vite</SelectItem>
                <SelectItem value="react-native">React Native</SelectItem>
                <SelectItem value="nextjs">Next.js</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </CardContent>
      </Card>

      <div className="flex justify-between">
        <Button variant="ghost" onClick={onBack}>
          ← Back
        </Button>
        <Button onClick={onScaffold} size="lg">
          Scaffold project →
        </Button>
      </div>
    </div>
  )
}
