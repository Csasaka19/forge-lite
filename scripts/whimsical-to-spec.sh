#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════════
# whimsical-to-spec.sh
#
# Converts a Whimsical mindmap JSON export (schema_version 0.1, source
# "mcp") into the standard product-spec.md + design-brief.md files
# inside ~/projects/<project-name>/docs/.
#
# Whimsical exports describe pages as trees of nodes with these
# prefixes: UI, Logic, System Update, Q, E, Option, Notification.
# Null-prefix nodes starting with "Result:" describe action outcomes.
#
# Usage:
#   ./scripts/whimsical-to-spec.sh <input.json> [project-name]
# ═══════════════════════════════════════════════════════════════════

INPUT="${1:-}"
MANUAL_NAME="${2:-}"
FORGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "$INPUT" ]; then
  cat <<USAGE
Usage: ./scripts/whimsical-to-spec.sh <input.json> [project-name]

  <input.json>    Path to a Whimsical mindmap export (schema_version 0.1).
  [project-name]  Optional. Overrides the name derived from board.slug.

Examples:
  ./scripts/whimsical-to-spec.sh fixtures/payment-flow.json
  ./scripts/whimsical-to-spec.sh ~/Downloads/board.json tenant-hub
USAGE
  exit 1
fi

if [ ! -f "$INPUT" ]; then
  echo "Error: File not found: $INPUT"
  exit 1
fi

if ! command -v python3 &> /dev/null; then
  echo "Error: python3 is required but not installed."
  exit 1
fi

# Validate JSON parses AND looks like a Whimsical export
if ! python3 - "$INPUT" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
assert isinstance(d.get('mindmaps'), list) and d['mindmaps'], 'no mindmaps'
assert d.get('schema_version'), 'no schema_version'
PY
then
  echo ""
  echo "Error: '$INPUT' is not a valid Whimsical export."
  echo ""
  echo "Expected a JSON object with:"
  echo "  - schema_version (e.g. \"0.1\")"
  echo "  - mindmaps[] with title + nodes[]"
  echo ""
  echo "If this is a standard Forge JSON spec, use json-to-spec.sh instead."
  exit 1
fi

# Resolve project name (arg2 > board.slug > board.title sluggified > filename)
RESOLVED_NAME=$(python3 - "$INPUT" "$MANUAL_NAME" <<'PY'
import json, re, sys, os

def clean(s: str) -> str:
    s = s.lower().strip()
    s = re.sub(r"[_\s]+", "-", s)
    s = re.sub(r"[^a-z0-9-]", "", s)
    s = re.sub(r"-+", "-", s).strip("-")
    return s

path = sys.argv[1]
manual = sys.argv[2] if len(sys.argv) > 2 else ""

if manual:
    print(clean(manual))
    sys.exit(0)

d = json.load(open(path))
board = d.get("board") or {}
for key in ("slug", "title"):
    v = (board.get(key) or "").strip()
    if v:
        print(clean(v))
        sys.exit(0)

base = os.path.splitext(os.path.basename(path))[0]
print(clean(base) or "whimsical-project")
PY
)

[ -z "$RESOLVED_NAME" ] && RESOLVED_NAME="whimsical-project"
PROJECT_DIR="$FORGE_DIR/../$RESOLVED_NAME"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Input file:      $INPUT"
echo "  Format:          Whimsical mindmap export"
echo "  Project name:    $RESOLVED_NAME"
echo "  Project folder:  $PROJECT_DIR"
echo "════════════════════════════════════════════════════════════════"
echo ""

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Project folder doesn't exist — scaffolding via new-project.sh..."
  echo ""
  bash "$FORGE_DIR/scripts/new-project.sh" "$RESOLVED_NAME"
  echo ""
else
  echo "Project folder exists — will overwrite docs/product-spec.md and docs/design-brief.md."
  mkdir -p "$PROJECT_DIR/docs"
fi

# ── Generate spec + brief ──
python3 - "$INPUT" "$PROJECT_DIR" <<'PY'
import json, os, re, sys
from collections import defaultdict

input_path, project_dir = sys.argv[1], sys.argv[2]
data = json.load(open(input_path))

board = data.get("board") or {}
mindmaps = data.get("mindmaps") or []

# ─── Tree helpers ─────────────────────────────────────────────────────
def build_index(nodes):
    by_id = {n["id"]: n for n in nodes}
    children = defaultdict(list)
    root = None
    for n in nodes:
        pid = n.get("parent_id")
        if pid is None:
            root = n
        else:
            children[pid].append(n)
    for kids in children.values():
        kids.sort(key=lambda x: x.get("order", 0))
    return root, by_id, children

def walk(node_id, children, predicate=None):
    """Yield every descendant of node_id (depth-first, preorder)."""
    for child in children.get(node_id, []):
        if predicate is None or predicate(child):
            yield child
        yield from walk(child["id"], children, predicate)

def kebab(text):
    s = re.sub(r"[^A-Za-z0-9]+", "-", (text or "").lower()).strip("-")
    return re.sub(r"-+", "-", s)

# ─── Whimsical body parsers ───────────────────────────────────────────
def is_result(node):
    return (node.get("prefix") in (None, "")) and (node.get("body") or "").lower().startswith("result:")

def strip_result(body):
    # "Result: Opens scheduling popup | UI: Popup: ..."
    rest = body.split(":", 1)[1].strip() if ":" in body else body
    return rest.split("|", 1)[0].strip()

ENTITY_RE = re.compile(
    r"^\s*(Update|Create):\s*([A-Za-z][A-Za-z0-9_]*)\s*\|\s*(.+)$",
    re.IGNORECASE,
)
FIELD_RE = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}\s*=\s*([^,]+)")

def guess_type(value):
    v = (value or "").strip().rstrip(",;")
    if v.lower() == "current date/time": return "Date"
    if v.lower() in ("true", "false"): return "boolean"
    if v == "Input Value": return "string"
    if v.lower() in ("null", "none"): return "string | null"
    if re.fullmatch(r"-?\d+", v): return "number"
    if re.fullmatch(r"-?\d*\.\d+", v): return "number"
    if len(v) > 40: v = v[:40] + "…"
    return f"string  // e.g. {v}"

def parse_entity_update(body):
    """Return (entity_name, {field: type}) or None."""
    text = body
    if text.lower().startswith("update:") is False and text.lower().startswith("create:") is False:
        m_anywhere = re.search(r"(Update|Create):\s*([A-Za-z][A-Za-z0-9_]*)\s*\|\s*(.+)", text, re.IGNORECASE)
        if not m_anywhere:
            return None
        action, entity, fields_str = m_anywhere.groups()
    else:
        m = ENTITY_RE.match(text)
        if not m:
            return None
        action, entity, fields_str = m.groups()
    fields = {}
    for fm in FIELD_RE.finditer(fields_str):
        fields[fm.group(1)] = guess_type(fm.group(2))
    return entity, fields

# Some Result bodies bundle a System Update after a "|" — extract it.
SYSTEM_UPDATE_IN_RESULT_RE = re.compile(
    r"System Update:\s*((?:Update|Create):\s*[A-Za-z][A-Za-z0-9_]*\s*\|\s*[^|]+)",
    re.IGNORECASE,
)

# ─── Per-mindmap extraction ───────────────────────────────────────────
PAGES = []          # for the Pages & Routes table
FEATURES = []       # list of dicts: name, description, userFlow, edgeCases
DATA_MODEL = defaultdict(dict)
NOTIFICATIONS = []  # plain strings
USER_TYPES = set()
TOP_DESC = None

for mm in mindmaps:
    mm_title = (mm.get("title") or "").strip()
    page_name = mm_title
    if page_name.lower().startswith("page:"):
        page_name = page_name.split(":", 1)[1].strip()
    nodes = mm.get("nodes") or []
    if not nodes:
        continue
    root, by_id, children = build_index(nodes)
    if root is None:
        continue

    # Pages table row
    PAGES.append({
        "name": page_name or "[TODO]",
        "route": "/" + (kebab(page_name) or "page"),
        "who": "[TODO — derive from auth/role]",
        "shows": "[see Features below]",
    })

    # Welcome / intro UI:Text directly under root
    for c in children.get(root["id"], []):
        if c.get("prefix") == "UI" and c["body"].startswith("Text:"):
            if TOP_DESC is None:
                TOP_DESC = c["body"].split(":", 1)[1].strip()
            break

    # Find Tabs containers (one tab = one feature). If no Tabs, treat root
    # children as a single feature.
    tabs_containers = [c for c in children.get(root["id"], [])
                       if c.get("prefix") == "UI" and c["body"].startswith("Tabs:")]
    if tabs_containers:
        feature_roots = []
        for tc in tabs_containers:
            feature_roots.extend(children.get(tc["id"], []))
    else:
        feature_roots = [root]

    for froot in feature_roots:
        feature_subtree = list(walk(froot["id"], children))
        feature_subtree.append(froot)

        name = froot.get("body", "").rstrip(":").strip()
        if not name or name.lower() in ("tabs", ""):
            name = page_name

        # Collect UI elements (excluding nested children of Q/E for the description)
        ui_elements = [n for n in feature_subtree if n.get("prefix") == "UI"]
        ui_summary = []
        for ui in ui_elements:
            body = ui.get("body", "")
            # First component is description-worthy; keep short
            if body.startswith("Text:") or body.startswith("Repeating Group:") or body.startswith("Button:") or body.startswith("Popup:"):
                ui_summary.append(body.split("|")[0].strip())

        description = ui_summary[0] if ui_summary else f"{name} tab"
        if len(description) > 200:
            description = description[:200] + "…"

        # ─── User flows: Q → E → Option → Button → Result chains ───
        flows = []
        for q in [n for n in feature_subtree if n.get("prefix") == "Q"]:
            q_body = q.get("body", "")
            steps = [f"User is asked: \"{q_body}\""]
            # E child
            e_children = [c for c in children.get(q["id"], []) if c.get("prefix") == "E"]
            if e_children:
                e = e_children[0]
                steps.append(f"Input type: {e.get('body','')}")
                opts = [c for c in children.get(e["id"], []) if c.get("prefix") == "Option"]
                if opts:
                    opt_labels = [o.get("body", "") for o in opts]
                    steps.append("Options: " + "; ".join(opt_labels))
                    # First option's Button → Result gives a representative outcome
                    for opt in opts:
                        btns = [c for c in children.get(opt["id"], [])
                                if c.get("prefix") == "UI" and c.get("body", "").startswith("Button:")]
                        if btns:
                            result_children = [c for c in children.get(btns[0]["id"], []) if is_result(c)]
                            if result_children:
                                steps.append(f"On confirm → {strip_result(result_children[0]['body'])}")
                                break
            # Standalone UI:Button siblings under the Q (e.g. "Confirm")
            sibling_buttons = [c for c in children.get(q["id"], [])
                               if c.get("prefix") == "UI" and c.get("body", "").startswith("Button:")]
            for btn in sibling_buttons:
                result_children = [c for c in children.get(btn["id"], []) if is_result(c)]
                if result_children:
                    steps.append(f"On {btn['body'].split('|')[0].strip()} → {strip_result(result_children[0]['body'])}")
            flows.append(steps)

        # If no Q-flows found, synthesize one from the first button → result pair
        if not flows:
            for btn in [n for n in feature_subtree if n.get("prefix") == "UI" and n.get("body", "").startswith("Button:")][:1]:
                rc = [c for c in children.get(btn["id"], []) if is_result(c)]
                if rc:
                    flows.append([
                        f"User opens {name}",
                        f"User clicks {btn['body'].split('|')[0].strip()}",
                        f"Result: {strip_result(rc[0]['body'])}",
                    ])

        # ─── Edge cases from Logic nodes ───
        edges = []
        for logic in [n for n in feature_subtree if n.get("prefix") == "Logic"]:
            body = logic.get("body", "")
            # Recognize "no X exist | ...: COUNT = 0" → empty state
            if re.search(r"COUNT\s*=\s*0", body) or "no " in body.lower():
                edges.append(f"Empty state — {body.split('|')[0].strip()}")
            else:
                edges.append(f"Conditional — {body.split('|')[0].strip()}")

        FEATURES.append({
            "name": name,
            "description": description,
            "userFlow": flows,
            "edgeCases": edges,
        })

        # ─── Data model from System Update nodes ───
        for su in [n for n in feature_subtree if n.get("prefix") == "System Update"]:
            parsed = parse_entity_update(su.get("body", ""))
            if not parsed:
                continue
            entity, fields = parsed
            for k, v in fields.items():
                DATA_MODEL[entity].setdefault(k, v)

        # ─── Notifications ───
        for nf in [n for n in feature_subtree if n.get("prefix") == "Notification"]:
            NOTIFICATIONS.append(nf.get("body", "").strip())

    # Result-embedded System Updates (e.g. inside "Result: X | System Update: ...")
    for n in nodes:
        if not is_result(n): continue
        m = SYSTEM_UPDATE_IN_RESULT_RE.search(n.get("body", ""))
        if not m: continue
        parsed = parse_entity_update(m.group(1))
        if not parsed: continue
        entity, fields = parsed
        for k, v in fields.items():
            DATA_MODEL[entity].setdefault(k, v)

# Derive user types from common entity hints
if "User" in DATA_MODEL or any("user{" in p.get("shows", "") for p in PAGES):
    USER_TYPES.add("Authenticated user")
for n_body in NOTIFICATIONS:
    m = re.match(r"\s*([A-Z][A-Za-z ]+?)\s*-\s*", n_body)
    if m:
        USER_TYPES.add(m.group(1).strip())

# ─── Render product-spec.md ───────────────────────────────────────────
title = board.get("title") or (mindmaps[0].get("title") if mindmaps else "Untitled")
TODO = "[TODO]"

spec = []
spec.append(f"# {title} — Product Specification")
spec.append("")
spec.append(f"> {TOP_DESC or '[TODO — one-sentence product description; see Features below for what was extracted.]'}")
spec.append("")
spec.append(f"> Source: Whimsical board `{board.get('slug', '')}` — extracted {board.get('extracted_at', '[TODO]')}")
spec.append("")

spec.append("## Problem Statement")
spec.append("")
spec.append(TODO)
spec.append("")

spec.append("## Target Users")
spec.append("")
if USER_TYPES:
    for u in sorted(USER_TYPES):
        spec.append(f"- **{u}:** {TODO}")
else:
    spec.append(TODO)
spec.append("")

spec.append("## Core Features")
spec.append("")
if FEATURES:
    for feat in FEATURES:
        spec.append(f"### {feat['name']}")
        spec.append("")
        spec.append(f"- **What it does:** {feat['description']}")
        if feat["userFlow"]:
            spec.append("- **User flow:**")
            # Each flow is its own numbered list — show them as sub-bullets
            for fi, flow in enumerate(feat["userFlow"], 1):
                if len(feat["userFlow"]) > 1:
                    spec.append(f"  - Flow {fi}:")
                    for j, step in enumerate(flow, 1):
                        spec.append(f"    {j}. {step}")
                else:
                    for j, step in enumerate(flow, 1):
                        spec.append(f"  {j}. {step}")
        else:
            spec.append("- **User flow:**")
            spec.append(f"  1. {TODO}")
        spec.append("- **Edge cases:**")
        if feat["edgeCases"]:
            for ec in feat["edgeCases"]:
                spec.append(f"  - {ec}")
        else:
            spec.append(f"  - {TODO}")
        spec.append("")
else:
    spec.append(TODO)
    spec.append("")

spec.append("## Pages & Routes")
spec.append("")
spec.append("| Page | Route | Who | What it shows |")
spec.append("|------|-------|-----|---------------|")
for p in PAGES:
    cells = [p["name"], p["route"], p["who"], p["shows"]]
    cells = [c.replace("|", "\\|") for c in cells]
    spec.append(f"| {cells[0]} | {cells[1]} | {cells[2]} | {cells[3]} |")
spec.append("")

spec.append("## Data Model")
spec.append("")
if DATA_MODEL:
    for entity, fields in DATA_MODEL.items():
        spec.append(f"### {entity}")
        spec.append("")
        for fname, ftype in fields.items():
            spec.append(f"- {fname}: {ftype}")
        spec.append("")
else:
    spec.append(TODO)
    spec.append("")

if NOTIFICATIONS:
    spec.append("## Notifications")
    spec.append("")
    for n in NOTIFICATIONS:
        spec.append(f"- {n}")
    spec.append("")

spec.append("## Out of Scope")
spec.append("")
spec.append(TODO)
spec.append("")

spec.append("## Open Questions")
spec.append("")
spec.append(TODO)
spec.append("")

spec_path = os.path.join(project_dir, "docs", "product-spec.md")
with open(spec_path, "w") as f:
    f.write("\n".join(spec))

# ─── Render design-brief.md (Whimsical export has no design info) ─────
brief = []
brief.append(f"# {title} — Design Brief")
brief.append("")
brief.append("> The Whimsical export does not contain design tokens. Fill these in by hand.")
brief.append("")
brief.append("## Aesthetic")
brief.append("")
brief.append(TODO)
brief.append("")
brief.append("## Color Palette")
brief.append("")
brief.append("```css")
brief.append(f"--primary: {TODO};")
brief.append(f"--accent: {TODO};")
brief.append("```")
brief.append("")
brief.append("## Typography")
brief.append("")
brief.append(f"- **Headings:** {TODO}")
brief.append(f"- **Body:** {TODO}")
brief.append("")
brief.append("## Layout")
brief.append("")
brief.append(TODO)
brief.append("")
brief.append("## Mobile Priority")
brief.append("")
brief.append(TODO)
brief.append("")

brief_path = os.path.join(project_dir, "docs", "design-brief.md")
with open(brief_path, "w") as f:
    f.write("\n".join(brief))

print(f"  Wrote: {spec_path}")
print(f"  Wrote: {brief_path}")
print()
print(f"  Features extracted:   {len(FEATURES)}")
print(f"  Pages:                {len(PAGES)}")
print(f"  Entities:             {len(DATA_MODEL)}")
print(f"  Notifications:        {len(NOTIFICATIONS)}")
PY

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ Done"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. cd $PROJECT_DIR"
echo "  2. Review docs/product-spec.md and docs/design-brief.md"
echo "     (Whimsical doesn't carry design — design-brief.md is all TODO)"
echo "  3. claude"
echo "  4. > /build-feature Scaffold the project and build the first page"
echo ""
