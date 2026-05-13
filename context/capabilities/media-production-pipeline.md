# Media Production Pipeline

How to build production tools for animation, video, and creative workflows: shot tracking, asset versioning, review with frame-accurate comments, render queues, and role-based collaboration. Read before scoping any studio tool, animation tracker, or video production app.

## Decision Tree

| Need | Pick |
|---|---|
| Small studio (1-10 users), single project at a time | **Custom app**, this guide |
| Mid-size, many concurrent productions | **Custom app** with org/project model |
| Full VFX pipeline (asset management, render farm, plugins) | **ShotGrid (Autodesk Flow)** or **ftrack** — don't rebuild |
| Just review (no shot tracking) | **Frame.io** as the front; custom backend for metadata |
| Render queue | **Background job system** + worker pool — see `background-jobs.md` |

For most projects: **custom app with explicit stages, shot tracking, and frame-comments**.

## Production Stages

```
Concept → Pre-production → Production → Post → Delivered
```

- **Concept** — script, treatment, mood boards.
- **Pre-production** — storyboard, animatic, asset list, schedule.
- **Production** — shots being created (animation, filming, modeling).
- **Post** — comp, color, sound, edit.
- **Delivered** — final cut exported, signed off.

Each stage gates the next. The app should reflect the current stage and lock backwards transitions (admin-only override).

## Data Model

```ts
interface Project {
  id: string
  orgId: string
  title: string
  slug: string
  client?: string
  type: 'film' | 'series' | 'commercial' | 'animation'
  stage: 'concept' | 'preproduction' | 'production' | 'post' | 'delivered'
  startDate: Date
  targetDeliveryDate: Date
  status: 'active' | 'on_hold' | 'completed' | 'cancelled'
  createdAt: Date
}

interface Episode {                       // optional grouping
  id: string
  projectId: string
  number: number                          // S01E03 → 3
  title: string
  durationSeconds: number
}

interface Sequence {                      // optional grouping
  id: string
  projectId: string
  episodeId?: string
  name: string                            // "Chase Scene"
  sortOrder: number
}

interface Shot {
  id: string
  projectId: string
  sequenceId?: string
  code: string                            // "EP03_SQ02_SH010" — naming convention enforced
  description: string
  status: 'pending' | 'in_progress' | 'in_review' | 'revising' | 'approved' | 'final'
  assignedTo?: string                     // userId
  startFrame: number
  endFrame: number
  durationFrames: number                  // endFrame - startFrame
  framerate: number                       // 24 | 25 | 30 | 60
  estimatedHours?: number
  loggedHours?: number
  dueDate?: Date
  thumbnailUrl?: string
  currentVersion: number                  // latest Asset version for this shot
  createdAt: Date
}

interface Asset {                         // shot output: image, video, project file
  id: string
  shotId?: string                         // null if non-shot asset (reference, character)
  projectId: string
  type: 'image' | 'video' | 'audio' | 'project_file' | 'reference'
  category: string                        // "animation_pass", "color_pass", "comp", "character_model"
  filename: string
  fileSize: number
  storageUrl: string                      // S3 / GCS
  thumbnailUrl?: string
  previewUrl?: string                     // for video: low-bitrate transcoded preview
  durationSeconds?: number                // for video/audio
  width?: number
  height?: number
  versionNumber: number
  uploadedBy: string
  uploadedAt: Date
  metadata: Record<string, unknown>       // codec, exif, etc.
}

interface Review {
  id: string
  shotId: string
  assetId: string                         // version under review
  requestedBy: string
  reviewerIds: string[]
  status: 'pending' | 'approved' | 'changes_requested'
  createdAt: Date
  completedAt?: Date
}

interface Comment {
  id: string
  reviewId: string
  authorId: string
  body: string
  frame?: number                          // null = general; number = frame-accurate
  x?: number                              // optional: annotation position (0-1 normalized)
  y?: number
  parentId?: string                       // threaded replies
  attachmentUrl?: string                  // sketch, screenshot
  resolved: boolean
  resolvedBy?: string
  resolvedAt?: Date
  createdAt: Date
}

interface RenderJob {
  id: string
  shotId: string
  assetId: string                         // input project file
  preset: string                          // "preview_720p_h264" | "delivery_4k_prores"
  status: 'queued' | 'running' | 'completed' | 'failed'
  progress: number                        // 0-100
  outputAssetId?: string
  startedAt?: Date
  completedAt?: Date
  workerId?: string
  errorMessage?: string
}
```

Index `shots (project_id, status)`, `assets (shot_id, version_number desc)`, `comments (review_id, frame)`, `render_jobs (status, queued_at)`.

## Naming Conventions

Enforce shot codes at write time:

```ts
const ShotCodeSchema = z.string().regex(/^EP\d{2}_SQ\d{2}_SH\d{3}$/, 'Format: EP01_SQ02_SH003')
```

Consistent codes make filename parsing trivial and search predictable. Don't accept "shot_003" alongside "EP01_SH003" — fix at the form, not in queries.

## UI Patterns

### Project Dashboard

- **Summary**: shot counts by status (Pending / In Progress / Review / Approved / Final).
- **Burndown chart**: shots remaining vs. days remaining.
- **Recent activity feed**.
- **Reviews awaiting your input** (assigned reviewer).
- **Shots assigned to you** (artist view).

### Shot Tracker (kanban or table)

- **Kanban**: columns by status; drag shots between (see `drag-drop-sortable.md`).
- **Table** (default for >50 shots): TanStack Table per `tables-data-grids.md`. Filter by status, assignee, due date. Sort by code, due date, last update.
- **Bulk actions**: assign, set status, set due.

```tsx
function ShotTable({ shots }: { shots: Shot[] }) {
  return (
    <DataGrid
      rows={shots}
      columns={[
        { key: 'code', header: 'Code' },
        { key: 'description', header: 'Description', cell: (s) => <span className="line-clamp-1">{s.description}</span> },
        { key: 'status', header: 'Status', cell: (s) => <StatusPill status={s.status} /> },
        { key: 'assignedTo', header: 'Artist', cell: (s) => <UserChip userId={s.assignedTo} /> },
        { key: 'dueDate', header: 'Due', cell: (s) => formatDate(s.dueDate) },
        { key: 'currentVersion', header: 'v' },
      ]}
    />
  )
}
```

### Shot Detail

Two-column layout:

- **Left**: video/image player for current version.
- **Right**: version history, comments, metadata, render history.

Versions listed newest-first; click to swap player to that version.

### Video Player with Frame-Accurate Comments

```tsx
function ShotPlayer({ asset, framerate, onComment }: Props) {
  const ref = useRef<HTMLVideoElement>(null)
  const [frame, setFrame] = useState(0)

  function currentFrame(): number {
    const t = ref.current?.currentTime ?? 0
    return Math.round(t * framerate)
  }

  function seekFrame(f: number) {
    if (ref.current) ref.current.currentTime = f / framerate
  }

  return (
    <div>
      <video ref={ref} src={asset.previewUrl} onTimeUpdate={() => setFrame(currentFrame())} />
      <div className="flex items-center gap-2 mt-2">
        <Button onClick={() => seekFrame(frame - 1)}>◀ Frame</Button>
        <span>{frame} / {asset.durationFrames}</span>
        <Button onClick={() => seekFrame(frame + 1)}>Frame ▶</Button>
        <Button onClick={() => onComment(frame)}>Comment at frame {frame}</Button>
      </div>
    </div>
  )
}
```

### Comments Sidebar

- Comments grouped by frame, ordered by frame ascending.
- General (no-frame) comments at top.
- Click a comment → seek to that frame.
- Threaded replies.
- Resolve checkbox per comment.

```tsx
function CommentItem({ c, onSeek, onResolve }: Props) {
  return (
    <div className={`p-3 border-l-2 ${c.resolved ? 'border-green-500 opacity-60' : 'border-amber-500'}`}>
      <div className="flex justify-between text-xs text-muted-foreground">
        <button onClick={() => onSeek(c.frame!)}>{c.frame != null ? `Frame ${c.frame}` : 'General'}</button>
        <span>{formatRelative(c.createdAt)}</span>
      </div>
      <div className="mt-1">{c.body}</div>
      <button onClick={() => onResolve(c.id)} className="text-sm mt-2">
        {c.resolved ? 'Resolved' : 'Mark resolved'}
      </button>
    </div>
  )
}
```

### Annotations (Drawing on the Frame)

Pause video, draw on a canvas overlaid on the frame. Save the strokes as SVG + the frame number.

```tsx
interface Annotation {
  frame: number
  strokes: { points: { x: number; y: number }[]; color: string }[]
}
```

Render the annotation back at that frame when reviewers seek to it.

## Asset Versioning

Every upload increments `versionNumber` for that shot+category:

```ts
async function uploadAsset(input: UploadInput) {
  const last = await prisma.asset.findFirst({
    where: { shotId: input.shotId, category: input.category },
    orderBy: { versionNumber: 'desc' },
  })
  const version = (last?.versionNumber ?? 0) + 1
  const asset = await prisma.asset.create({
    data: { ...input, versionNumber: version },
  })
  await prisma.shot.update({
    where: { id: input.shotId },
    data: { currentVersion: version, thumbnailUrl: asset.thumbnailUrl },
  })
  return asset
}
```

**Don't overwrite versions.** Old versions stay queryable; only the pointer moves.

## Large Media Upload

Multi-GB video files break standard form-POST upload. Use **multipart upload to S3 with presigned URLs** — see `file-upload-storage.md`.

```ts
async function startUpload(filename: string, fileSize: number) {
  const key = `assets/${projectId}/${randomUUID()}/${filename}`
  const upload = await s3.createMultipartUpload({ Bucket, Key: key, ContentType: detectMime(filename) })
  return { uploadId: upload.UploadId, key, partSize: 10 * 1024 * 1024 }    // 10MB parts
}
```

Client uploads parts in parallel; on completion, server triggers transcoding job:

```ts
await queue.add('transcode', { assetId, sourceKey: key })
```

### Transcoding

For preview playback in browser:

- **Source** — ProRes, EXR sequence, large H.264 — too heavy for review.
- **Preview** — H.264 720p @ 2-5 Mbps. Plays in `<video>` everywhere.
- **Thumbnail** — JPEG at 1/3 mark of the video.

Use **ffmpeg** in a worker, or **AWS MediaConvert** / **Mux** for managed transcoding. See `background-jobs.md`.

## Render Queue

Long renders go to a worker pool. UI shows queue status.

```ts
async function submitRender(shotId: string, preset: string) {
  const shot = await prisma.shot.findUniqueOrThrow({ where: { id: shotId } })
  const job = await prisma.renderJob.create({
    data: { shotId, assetId: shot.currentAssetId, preset, status: 'queued', progress: 0 },
  })
  await queue.add('render', { renderJobId: job.id }, { jobId: job.id })   // idempotent
  return job
}
```

Workers push progress via SSE/WebSocket (`realtime-features.md`). Throttle to ~1 update/sec — don't flood.

```ts
// Worker
async function processRender({ renderJobId }: { renderJobId: string }) {
  await prisma.renderJob.update({ where: { id: renderJobId }, data: { status: 'running', startedAt: new Date() } })
  await runFfmpeg({
    onProgress: throttle(async (pct) => {
      await prisma.renderJob.update({ where: { id: renderJobId }, data: { progress: pct } })
      await redis.publish(`render:${renderJobId}`, JSON.stringify({ progress: pct }))
    }, 1000),
  })
  // upload result, link as Asset, mark complete
}
```

## Review Workflow

```
created → in_review → (approved | changes_requested)
                        ↓
                     (artist uploads new version) → in_review again
```

Reviewer marks the review as approved or requests changes (with comments to address). When changes are requested, the shot goes back to `revising`. New version reopens the review.

UI:

- Reviewer sees the current version + all unresolved comments.
- Approve button: requires all comments resolved.
- Request Changes button: requires at least one open comment.

## Role-Based Permissions

Roles per project:

- **Director / Producer** — full access; can approve, change stages.
- **Supervisor** — assign shots, approve, request changes.
- **Artist** — work assigned shots, upload versions, respond to comments. Cannot approve.
- **Reviewer (client)** — view + comment + approve their own reviews. Cannot upload.
- **Viewer** — read-only.

Implement with RBAC per `api-security.md`. Scope all queries by project membership.

## Timeline / Schedule View

Gantt-like display:

- X-axis: dates.
- Y-axis: shots or artists.
- Bars: shot duration (start → due).
- Color: status.
- Click bar → shot detail.

For animator-load view, group by `assignedTo` instead of by shot.

## Common Mistakes

- **Versioning by overwriting filenames.** Old work lost. Increment `versionNumber`; keep all.
- **Frame comments stored as timestamp (seconds).** Drift between players. Store the frame number; framerate is per-shot.
- **Comments not threaded.** Long discussions become unreadable. Allow `parentId`.
- **No "resolved" state on comments.** Reviewer asks for 20 changes; artist can't tell what's addressed. Resolve checkbox.
- **Approve button enabled with unresolved comments.** Sign-off without addressing notes. Require resolution.
- **Reviewer can upload new versions.** Confusion about source of truth. Restrict by role.
- **Direct upload to backend, no S3 multipart.** 2GB upload fails at the proxy. Presigned multipart.
- **No preview transcoding.** Reviewer streams 800Mbps ProRes from S3. Transcode to H.264 720p preview.
- **Render progress published per-frame.** SSE flooded; browser stutters. Throttle to 1/sec.
- **Render queue without idempotency key.** Retries double-render — wasted compute. `jobId: renderJobId`.
- **Stage transitions allowed any direction.** "Delivered" set then "Production" — confusion. State machine.
- **Asset deletion is hard delete.** Accidental click loses GB. Soft delete + 30-day recovery.
- **Shot codes accepted in any format.** Searches break. Validate at the form.
- **No assignee on shots.** Nobody owns them; they sit. Required field.
- **Comments don't link to a specific asset version.** Comment "fix the eyes" — but on which version? Bind to assetId.
- **No notification on new comment / version.** Artists check the app for updates. Push via email + in-app (`email-notifications.md`).
- **Project files (Blender, Premiere) treated like videos and transcoded.** Wasted compute. Detect type, skip transcode.
- **Render output not linked back as a new Asset version.** Orphaned files; can't find the deliverable. Auto-create Asset on render complete.
- **No EXIF/metadata stripping on client uploads.** Camera GPS leaks. Strip on transcode (`image-media-processing.md`).
- **Burndown chart computed live on every dashboard load.** Slow. Materialize daily.
