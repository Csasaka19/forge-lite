# Rich Text Editing

How to add a WYSIWYG editor that doesn't ruin everything downstream. Read before adding any "edit content" feature beyond a `<textarea>`.

## Library Choice

- **Tiptap** — ProseMirror-based, plug-in friendly, React-first. Default for most apps.
- **Lexical** — Facebook's editor, performant, great composability. Reach for it when Tiptap's plugin model feels heavy.
- **Plate** — Slate-based, headless, modern. Good middle ground.
- **Slate** (raw) — flexible primitives; significant work to ship features.
- **TinyMCE / CKEditor** — mature, drop-in, license cost / corporate UI.

Pick **Tiptap** unless you have a reason. It's the default for new React projects in 2026.

## Don't Use `contentEditable` Directly

It looks easy. It's not. Cross-browser quirks, selection management, paste handling, undo stack — every editor library exists because rolling your own is a 6-month detour.

## Tiptap Setup

```bash
npm install @tiptap/react @tiptap/starter-kit @tiptap/extension-link @tiptap/extension-image @tiptap/extension-placeholder
```

```tsx
import { useEditor, EditorContent } from '@tiptap/react'
import StarterKit from '@tiptap/starter-kit'
import Placeholder from '@tiptap/extension-placeholder'
import Link from '@tiptap/extension-link'

export function Editor({ value, onChange }: { value: string; onChange: (html: string) => void }) {
  const editor = useEditor({
    extensions: [
      StarterKit.configure({ heading: { levels: [1, 2, 3] } }),
      Placeholder.configure({ placeholder: 'Write something...' }),
      Link.configure({ openOnClick: false, autolink: true }),
    ],
    content: value,
    onUpdate: ({ editor }) => onChange(editor.getHTML()),
    editorProps: {
      attributes: { class: 'prose prose-sm focus:outline-none min-h-[200px]' },
    },
  })

  return (
    <div className="border rounded">
      <Toolbar editor={editor} />
      <EditorContent editor={editor} />
    </div>
  )
}
```

### Output Format Choice

Tiptap can emit:

- **HTML** — easiest to render. Sanitize on read and write.
- **JSON** — structured, lossless, easy to diff and process. Renderable back to HTML or to other formats.
- **Markdown** — via extension; some loss for fancy nodes.

Default to **JSON storage**. Render HTML for display. Don't store HTML as your canonical format — it tempts unsanitized rendering.

## Toolbar

```tsx
function Toolbar({ editor }: { editor: Editor | null }) {
  if (!editor) return null
  return (
    <div className="border-b px-2 py-1 flex gap-1">
      <button
        onClick={() => editor.chain().focus().toggleBold().run()}
        className={editor.isActive('bold') ? 'bg-muted' : ''}
        aria-label="Bold"
      >
        <BoldIcon />
      </button>
      <button onClick={() => editor.chain().focus().toggleItalic().run()} aria-label="Italic"><ItalicIcon /></button>
      <button onClick={() => editor.chain().focus().toggleHeading({ level: 2 }).run()} aria-label="Heading"><H2Icon /></button>
      <button onClick={() => editor.chain().focus().toggleBulletList().run()} aria-label="Bullet list"><ListIcon /></button>
      {/* etc */}
    </div>
  )
}
```

`editor.isActive('bold')` highlights the toolbar button when the cursor is in bold text. Always show active state.

## Markdown Mode

For developer-targeted tools or where source-control of content matters:

```bash
npm install tiptap-markdown
```

```ts
import { Markdown } from 'tiptap-markdown'

useEditor({
  extensions: [StarterKit, Markdown.configure({ html: false, tightLists: true })],
})

// On save:
const md = editor.storage.markdown.getMarkdown()
```

Storing markdown is debugger-friendly and grep-friendly. Render with a markdown library (`react-markdown`) instead of HTML for display when the content is also markdown elsewhere (docs, README-style content).

## Image Embedding

```ts
import Image from '@tiptap/extension-image'

useEditor({
  extensions: [StarterKit, Image.configure({ inline: false, allowBase64: false })],
})
```

### Rules

- **Disallow base64 images.** They balloon document size. Force users to upload, then insert by URL.
- **Upload flow**: click "Insert image" → file picker → upload to S3/R2 → insert `<img src>` with the returned URL.
- **Re-encode on upload** with Sharp. Don't trust user-supplied formats.
- **Max size enforced server-side.** Don't trust the client.

```tsx
async function insertImage(editor: Editor, file: File) {
  const { url } = await uploadImage(file)
  editor.chain().focus().setImage({ src: url, alt: file.name }).run()
}
```

## Mentions (@user)

```bash
npm install @tiptap/extension-mention @tiptap/suggestion tippy.js
```

Plugin setup is substantial — see the Tiptap docs for the suggestion render function. The pattern:

1. User types `@`.
2. Suggestion plugin opens a dropdown anchored to the cursor.
3. Filter users as the user types more characters.
4. Insert a `<mention>` node with `data-id="userId"` and the user's name.
5. On render or save, parse mentions to resolve current names (in case of renames).

For lightweight mentions, a simple regex on save (`@username` → look up + link) is enough. Tiptap's mention extension is overkill for that.

## Content Sanitization

**Always sanitize HTML you didn't fully control.** Even your own editor's output gets paste-mangled with foreign markup.

```bash
npm install isomorphic-dompurify
```

```ts
import DOMPurify from 'isomorphic-dompurify'

const safe = DOMPurify.sanitize(html, {
  ALLOWED_TAGS: ['p', 'br', 'h1', 'h2', 'h3', 'strong', 'em', 'ul', 'ol', 'li', 'a', 'blockquote', 'code', 'pre', 'img'],
  ALLOWED_ATTR: ['href', 'src', 'alt', 'title'],
  ALLOWED_URI_REGEXP: /^(?:(?:https?|mailto):|[^a-z]|[a-z0-9+.-]+(?:[^a-z+.\-:]|$))/i,
})
```

### Rules

- **Sanitize on the way in** (server-side, before storing).
- **Also on the way out** (rendering layer) — defense in depth.
- **Never `dangerouslySetInnerHTML` raw user content.** Always purify first.
- **Explicit allowlist of tags and attributes.** Default-deny.
- **`a[href]` must restrict protocols** — `javascript:` URLs are XSS.
- **`img[src]` should be HTTPS only** in production; prefer your own image CDN.

DOMPurify is the standard. Roll-your-own escapers miss edge cases (mutation XSS, MathML, SVG).

## Rendering

For display, render the sanitized HTML:

```tsx
<div
  className="prose"
  dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(post.contentHtml, config) }}
/>
```

If storing JSON, render Tiptap's JSON back through a renderer:

```tsx
import { generateHTML } from '@tiptap/html'
const html = generateHTML(json, [StarterKit, Link, Image])
```

Server-side render works the same with `@tiptap/html` Node-compatible build.

## Collaborative Editing (Basics)

For real-time multi-user editing:

- **Tiptap Collaboration** + **Y.js** — CRDT-based, conflict-free. The standard.
- **Liveblocks** — hosted, batteries included.
- **Hocuspocus** — Tiptap's self-hosted backend.

```bash
npm install @tiptap/extension-collaboration @tiptap/extension-collaboration-cursor yjs y-websocket
```

```ts
import Collaboration from '@tiptap/extension-collaboration'
import CollaborationCursor from '@tiptap/extension-collaboration-cursor'
import * as Y from 'yjs'
import { WebsocketProvider } from 'y-websocket'

const ydoc = new Y.Doc()
const provider = new WebsocketProvider(env.WS_URL, `doc-${docId}`, ydoc)

useEditor({
  extensions: [
    StarterKit.configure({ history: false }),
    Collaboration.configure({ document: ydoc }),
    CollaborationCursor.configure({ provider, user: { name: user.name, color: user.color } }),
  ],
})
```

CRDT means: every replica can edit offline, sync later, no conflicts. Magic for collab, infrastructure cost for what you ship.

For Phase 1, single-user editing with autosave is enough. Add collab when product demands it.

## Autosave

```tsx
const editor = useEditor({
  onUpdate: debounce(({ editor }) => {
    save(editor.getJSON())
  }, 1000),
})
```

Indicators: "Saved" / "Saving..." / "Failed to save - retry". Users need to know their work is safe.

For longer documents, save every 30s **and** on blur **and** on visibility change.

## Common Mistakes

- **Rolling your own with `contentEditable`.** Six-month detour. Use a library.
- **Storing HTML and rendering it raw with `dangerouslySetInnerHTML`.** XSS waiting to happen. Always sanitize.
- **Sanitizing once, on save only.** Defense in depth — sanitize on read too.
- **Allowing all attributes by default in DOMPurify.** `style` and `onerror` are XSS vectors. Explicit allowlist.
- **Base64 images in the document.** A few inline images ballons stored size 5×. Upload and reference by URL.
- **No image size cap.** User uploads 50 MB; document edit becomes slow.
- **No autosave indicator.** Users wonder if their work is safe. Add status text.
- **Pasting from Word brings the Word styles.** Tiptap handles most of this; verify by pasting from Word + Google Docs.
- **Storing markdown when the editor produces HTML-only constructs.** Tables and fancy nodes get lost. Stick with one or use JSON.
- **Toolbar without active state.** Users can't see whether the cursor is in bold text.
- **No keyboard shortcuts.** Power users expect Cmd+B, Cmd+I, Cmd+K. Tiptap includes these — don't break them with custom keymaps.
- **Mentions resolved by stored name, not user ID.** User renames; old mentions break.
- **Collaboration without auth on the WS endpoint.** Anyone connecting to your doc URL can edit. Authenticate the WebSocket upgrade.
- **No max document size.** A 50,000-paragraph doc dies in the browser. Cap with friendly warnings.
- **Editor inside a form `<form>`.** Enter triggers form submit. Either prevent or use `<div>` with explicit submit handling.
