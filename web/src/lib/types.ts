export type Step = 1 | 2 | 3 | 4

export type TargetFiles = 'both' | 'spec' | 'design'
export type TechStack = 'react-vite' | 'react-native' | 'nextjs'

export interface WizardState {
  step: Step
  content: string
  sourceFilename: string | null
  projectName: string
  capabilities: Set<string>
  detectedCapabilities: Set<string>
  targetFiles: TargetFiles
  techStack: TechStack
}

export interface ScaffoldedFile {
  path: string
  size: number
  note?: string
}
