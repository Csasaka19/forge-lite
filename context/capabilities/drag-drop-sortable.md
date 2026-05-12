# Drag, Drop, Sortable

How to build sortable lists, kanban boards, and drop zones. Read before adding any reorder, drag-to-arrange, or drag-to-upload feature.

## Library Choice

- **dnd-kit** — modern, accessible, touch-friendly. Default for new projects.
- **react-dropzone** — file drop only. Pair with dnd-kit for everything else.
- **react-beautiful-dnd** — popular, **unmaintained**. Don't start new projects with it.
- **HTML5 drag-and-drop API** — built in, painful, no touch. Avoid unless one-off.

## dnd-kit Setup

```bash
npm install @dnd-kit/core @dnd-kit/sortable @dnd-kit/utilities
```

dnd-kit is modular:

- **`@dnd-kit/core`** — context, sensors, drag overlay primitives.
- **`@dnd-kit/sortable`** — sortable lists (one-axis reordering).
- **`@dnd-kit/utilities`** — `CSS.Translate` helpers.

## Sortable List

```tsx
import { DndContext, closestCenter, KeyboardSensor, PointerSensor, useSensor, useSensors } from '@dnd-kit/core'
import { arrayMove, SortableContext, sortableKeyboardCoordinates, useSortable, verticalListSortingStrategy } from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'

function SortableItem({ id, children }: { id: string; children: React.ReactNode }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id })
  return (
    <li
      ref={setNodeRef}
      style={{ transform: CSS.Translate.toString(transform), transition, opacity: isDragging ? 0.4 : 1 }}
      {...attributes}
      {...listeners}
      className="bg-card border rounded p-3 cursor-grab active:cursor-grabbing"
    >
      {children}
    </li>
  )
}

export function SortableList() {
  const [items, setItems] = useState(['Item 1', 'Item 2', 'Item 3'])
  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 8 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  )

  return (
    <DndContext
      sensors={sensors}
      collisionDetection={closestCenter}
      onDragEnd={({ active, over }) => {
        if (over && active.id !== over.id) {
          setItems((items) => arrayMove(items, items.indexOf(active.id as string), items.indexOf(over.id as string)))
        }
      }}
    >
      <SortableContext items={items} strategy={verticalListSortingStrategy}>
        <ul className="space-y-2">
          {items.map((id) => <SortableItem key={id} id={id}>{id}</SortableItem>)}
        </ul>
      </SortableContext>
    </DndContext>
  )
}
```

### Rules

- **`activationConstraint`** prevents click-then-drag confusion. `distance: 8` means "start dragging only after moving 8px." Without it, clicks are interpreted as drag starts.
- **`useSortable` requires a stable `id`.** Use entity IDs, not array indices — indices change as items move.
- **Visual feedback while dragging** — opacity, shadow, scale. The dragged item should feel different.

## Drag Handles

For long items where the whole row shouldn't be draggable:

```tsx
<li ref={setNodeRef} style={style} {...attributes}>
  <button {...listeners} aria-label="Drag to reorder" className="cursor-grab">
    <DragIcon />
  </button>
  {/* Rest of row is clickable normally */}
  <span>{children}</span>
</li>
```

The handle gets `listeners`; the rest of the row doesn't. Users can click action buttons inside the row without triggering a drag.

## Kanban Board

Multi-column drag — items move between columns and within columns.

```tsx
import { DndContext, DragOverlay, useDroppable } from '@dnd-kit/core'

const columns = ['todo', 'in-progress', 'done'] as const
type Column = typeof columns[number]
type Task = { id: string; title: string; column: Column }

function Column({ id, tasks }: { id: Column; tasks: Task[] }) {
  const { setNodeRef, isOver } = useDroppable({ id })
  return (
    <div
      ref={setNodeRef}
      className={`p-3 rounded min-h-[300px] ${isOver ? 'bg-primary/10' : 'bg-muted'}`}
    >
      <h3 className="font-bold mb-2">{id}</h3>
      <SortableContext items={tasks.map((t) => t.id)} strategy={verticalListSortingStrategy}>
        {tasks.map((t) => <SortableItem key={t.id} id={t.id}>{t.title}</SortableItem>)}
      </SortableContext>
    </div>
  )
}

function Board() {
  const [tasks, setTasks] = useState<Task[]>(initialTasks)
  const [activeId, setActiveId] = useState<string | null>(null)

  return (
    <DndContext
      onDragStart={({ active }) => setActiveId(active.id as string)}
      onDragEnd={({ active, over }) => {
        setActiveId(null)
        if (!over) return
        const targetCol = columns.includes(over.id as Column)
          ? over.id as Column
          : tasks.find((t) => t.id === over.id)?.column
        if (!targetCol) return
        setTasks((tasks) => tasks.map((t) => t.id === active.id ? { ...t, column: targetCol } : t))
      }}
    >
      <div className="grid grid-cols-3 gap-4">
        {columns.map((c) => (
          <Column key={c} id={c} tasks={tasks.filter((t) => t.column === c)} />
        ))}
      </div>

      <DragOverlay>
        {activeId ? <TaskCard task={tasks.find((t) => t.id === activeId)!} /> : null}
      </DragOverlay>
    </DndContext>
  )
}
```

### Rules

- **`DragOverlay`** renders the dragged item at the cursor. Without it, the item only moves when dropped, which feels broken.
- **Distinguish "drop on column" from "drop on item"** — items have IDs, columns also have IDs. Check which one `over.id` refers to.
- **Persist after drop** — save the new order to the server. Optimistically update the UI; rollback on failure.

## Persisting Order

Don't store `position: 1, 2, 3, ...` on every row. Reorder requires updating many rows.

Use **fractional indexing** (`fractional-indexing` library) or **LexoRank**:

```ts
import { generateKeyBetween } from 'fractional-indexing'

const newKey = generateKeyBetween(prev.sortKey, next.sortKey)
await api(`/tasks/${id}`, { method: 'PATCH', body: JSON.stringify({ sortKey: newKey }) })
```

Insert between any two items in O(1). Occasionally rebalance keys (months apart in practice) to avoid keys growing too long.

## File Drop Zones

Use **react-dropzone** for file uploads. dnd-kit handles intra-app drags; react-dropzone handles OS-level file drops.

```bash
npm install react-dropzone
```

```tsx
import { useDropzone } from 'react-dropzone'

const { getRootProps, getInputProps, isDragActive } = useDropzone({
  accept: { 'image/*': ['.jpg', '.png', '.webp'] },
  maxSize: 10 * 1024 * 1024,
  onDrop: (files) => handleFiles(files),
})

<div {...getRootProps()} className={`border-2 border-dashed p-8 ${isDragActive ? 'border-primary' : 'border-border'}`}>
  <input {...getInputProps()} />
  <p>{isDragActive ? 'Drop here' : 'Drop files or click to choose'}</p>
</div>
```

See `context/capabilities/file-upload-storage.md` for the full upload pipeline.

## Touch Support

dnd-kit's `PointerSensor` handles touch by default. Caveats:

- **Touch holds vs scrolling** — without `activationConstraint`, every touch starts a drag, breaking scroll.
- **Use `TouchSensor` explicitly** for fine-tuned mobile UX:

```ts
import { TouchSensor } from '@dnd-kit/core'

const sensors = useSensors(
  useSensor(MouseSensor, { activationConstraint: { distance: 8 } }),
  useSensor(TouchSensor, { activationConstraint: { delay: 250, tolerance: 5 } }),
  useSensor(KeyboardSensor),
)
```

`delay: 250` means hold for 250ms to start a drag — distinguishes drag from tap and from scroll.

## Accessibility for Drag Operations

Most drag-and-drop UIs are unusable with a screen reader or keyboard. dnd-kit makes it possible.

### Keyboard Support

`KeyboardSensor` enables Space/Enter to lift, arrow keys to move, Space/Enter to drop, Escape to cancel.

```ts
import { sortableKeyboardCoordinates } from '@dnd-kit/sortable'

useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates })
```

### Announcements

dnd-kit's `screenReaderInstructions` and `announcements` props let you customize what's said:

```tsx
<DndContext
  accessibility={{
    announcements: {
      onDragStart: ({ active }) => `Picked up ${active.id}.`,
      onDragOver: ({ active, over }) => over ? `${active.id} over ${over.id}.` : '',
      onDragEnd: ({ active, over }) => over ? `${active.id} dropped on ${over.id}.` : `${active.id} dropped.`,
      onDragCancel: ({ active }) => `Cancelled ${active.id}.`,
    },
  }}
>
```

### Alternative UI

Always provide a non-drag way to reorder — keyboard shortcuts, up/down buttons, or a "Move to..." menu. Some users physically can't drag.

## Common Mistakes

- **`react-beautiful-dnd` on a new project.** Unmaintained. Use dnd-kit.
- **No `activationConstraint`.** Clicks register as drags. Misery.
- **Array index as the sortable ID.** Indices change when items move. Use stable entity IDs.
- **Saving every reordered row.** N database updates for one drag. Use fractional indexing or LexoRank.
- **No optimistic update.** UI freezes waiting for the API. Reorder optimistically, rollback on error.
- **Drop without `DragOverlay`.** Item snaps in place at drop time, which feels jarring. The overlay glides.
- **Whole row is a drag handle.** Users can't click action buttons. Add an explicit handle.
- **No touch sensor configuration.** Mobile users can't scroll past a sortable list.
- **No keyboard support.** Drag-and-drop UIs are inaccessible by default. Add `KeyboardSensor`.
- **Visual indicator missing on drop targets.** Users don't know where they can drop.
- **Persisting order via "position" integers.** Every reorder updates many rows. Doesn't scale.
- **No rollback on persistence failure.** Server rejects the move; UI shows new order anyway. Inconsistency.
- **Drop zones nested in scrolling containers without `autoScroll` config.** Can't drag past the visible area.
- **Multiple `DndContext`s in the same tree.** State conflicts. One context per drag interaction.
- **`onDragEnd` doing heavy work synchronously.** Drag feels sticky. Defer non-critical work.
