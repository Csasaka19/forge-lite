#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════════
# json-to-spec.sh
#
# Converts a structured JSON application description into:
#   docs/product-spec.md
#   docs/design-brief.md
# inside ~/projects/<project-name>/, scaffolding the project if needed.
#
# Usage:
#   ./scripts/json-to-spec.sh <input.json> [project-name]
#
# Examples:
#   ./scripts/json-to-spec.sh fixtures/sample-water-vending.json
#   ./scripts/json-to-spec.sh ~/Desktop/spec.json my-app
# ═══════════════════════════════════════════════════════════════════

INPUT="${1:-}"
MANUAL_NAME="${2:-}"
FORGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "$INPUT" ]; then
  cat <<USAGE
Usage: ./scripts/json-to-spec.sh <input.json> [project-name]

  <input.json>    Path to a JSON file describing the application.
  [project-name]  Optional. Overrides the name extracted from JSON.

Examples:
  ./scripts/json-to-spec.sh fixtures/sample-water-vending.json
  ./scripts/json-to-spec.sh ~/Desktop/spec.json my-app
USAGE
  exit 1
fi

if [ ! -f "$INPUT" ]; then
  echo "Error: File not found: $INPUT"
  exit 1
fi

if ! command -v python3 &> /dev/null; then
  echo "Error: python3 is required but not installed."
  echo "  Mac:   brew install python"
  echo "  Linux: sudo apt install python3"
  exit 1
fi

# ── Validate JSON parses ──
if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$INPUT" 2>/dev/null; then
  echo ""
  echo "Error: '$INPUT' is not valid JSON."
  echo ""
  echo "Suggestion: paste your file into https://jsonlint.com to find"
  echo "the syntax error (trailing commas, unquoted keys, smart quotes,"
  echo "or missing brackets are the usual suspects)."
  echo ""
  exit 1
fi

# ── Resolve project name ──
# Precedence: arg2 > JSON .name > regex over JSON .description > filename
RESOLVED_NAME=$(python3 - "$INPUT" "$MANUAL_NAME" <<'PY'
import json, re, sys, os

path = sys.argv[1]
manual = sys.argv[2] if len(sys.argv) > 2 else ""

def clean(s: str) -> str:
    s = s.lower().strip()
    s = re.sub(r"[_\s]+", "-", s)
    s = re.sub(r"[^a-z0-9-]", "", s)
    s = re.sub(r"-+", "-", s).strip("-")
    return s

if manual:
    print(clean(manual))
    sys.exit(0)

with open(path) as f:
    data = json.load(f)

name = (data.get("name") or "").strip()
if name:
    print(clean(name))
    sys.exit(0)

desc = (data.get("description") or "").strip()
if desc:
    m = re.search(r"([A-Za-z][A-Za-z0-9]+)\s+(?:app|system|platform|tool|dashboard|portal|tracker|service|marketplace)", desc, re.IGNORECASE)
    if m:
        print(clean(m.group(1)))
        sys.exit(0)

base = os.path.basename(path)
base = os.path.splitext(base)[0]
print(clean(base) or "new-project")
PY
)

if [ -z "$RESOLVED_NAME" ]; then
  RESOLVED_NAME="new-project"
fi

PROJECT_DIR="$FORGE_DIR/../$RESOLVED_NAME"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Input file:      $INPUT"
echo "  Project name:    $RESOLVED_NAME"
echo "  Project folder:  $PROJECT_DIR"
echo "════════════════════════════════════════════════════════════════"
echo ""

# ── Scaffold project if missing ──
if [ ! -d "$PROJECT_DIR" ]; then
  echo "Project folder doesn't exist — scaffolding via new-project.sh..."
  echo ""
  bash "$FORGE_DIR/scripts/new-project.sh" "$RESOLVED_NAME"
  echo ""
else
  echo "Project folder exists — will overwrite docs/product-spec.md and docs/design-brief.md."
  mkdir -p "$PROJECT_DIR/docs"
fi

# ── Generate the two markdown files ──
python3 - "$INPUT" "$PROJECT_DIR" <<'PY'
import json, sys, os

input_path = sys.argv[1]
project_dir = sys.argv[2]

with open(input_path) as f:
    data = json.load(f)

TODO = "[TODO]"

def g(key, default=TODO):
    v = data.get(key)
    if v is None or v == "" or v == [] or v == {}:
        return default
    return v

name = g("name", "Untitled Product")
description = g("description")
problem = g("problemStatement")
users = data.get("users") or []
features = data.get("features") or []
pages = data.get("pages") or []
data_model = data.get("dataModel") or {}
design = data.get("design") or {}
out_of_scope = data.get("outOfScope") or []
open_questions = data.get("openQuestions") or []

# ─── product-spec.md ───
spec = []
spec.append(f"# {name} — Product Specification")
spec.append("")
spec.append(f"> {description}")
spec.append("")

spec.append("## Problem Statement")
spec.append("")
spec.append(problem if problem != TODO else TODO)
spec.append("")

spec.append("## Target Users")
spec.append("")
if users:
    for u in users:
        utype = (u.get("type") or TODO).strip()
        goal = (u.get("goal") or TODO).strip()
        spec.append(f"- **{utype}:** {goal}")
else:
    spec.append(TODO)
spec.append("")

spec.append("## Core Features")
spec.append("")
if features:
    for feat in features:
        fname = (feat.get("name") or TODO).strip()
        fdesc = (feat.get("description") or TODO).strip()
        flow = feat.get("userFlow") or []
        edges = feat.get("edgeCases") or []
        spec.append(f"### {fname}")
        spec.append("")
        spec.append(f"- **What it does:** {fdesc}")
        spec.append("- **User flow:**")
        if flow:
            for i, step in enumerate(flow, 1):
                spec.append(f"  {i}. {step}")
        else:
            spec.append(f"  1. {TODO}")
        spec.append("- **Edge cases:**")
        if edges:
            for case in edges:
                spec.append(f"  - {case}")
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
if pages:
    for p in pages:
        row = [
            (p.get("name") or TODO).strip(),
            (p.get("route") or TODO).strip(),
            (p.get("who") or TODO).strip(),
            (p.get("shows") or TODO).strip(),
        ]
        row = [c.replace("|", "\\|") for c in row]
        spec.append(f"| {row[0]} | {row[1]} | {row[2]} | {row[3]} |")
else:
    spec.append(f"| {TODO} | {TODO} | {TODO} | {TODO} |")
spec.append("")

spec.append("## Data Model")
spec.append("")
if data_model:
    for entity, fields in data_model.items():
        spec.append(f"### {entity}")
        spec.append("")
        if isinstance(fields, dict) and fields:
            for fname, ftype in fields.items():
                spec.append(f"- {fname}: {ftype}")
        else:
            spec.append(f"- {TODO}")
        spec.append("")
else:
    spec.append(TODO)
    spec.append("")

spec.append("## Out of Scope")
spec.append("")
if out_of_scope:
    for item in out_of_scope:
        spec.append(f"- {item}")
else:
    spec.append(TODO)
spec.append("")

spec.append("## Open Questions")
spec.append("")
if open_questions:
    for q in open_questions:
        spec.append(f"- {q}")
else:
    spec.append(TODO)
spec.append("")

spec_path = os.path.join(project_dir, "docs", "product-spec.md")
with open(spec_path, "w") as f:
    f.write("\n".join(spec))

# ─── design-brief.md ───
def dg(key):
    v = design.get(key)
    if v is None or v == "":
        return TODO
    return v

brief = []
brief.append(f"# {name} — Design Brief")
brief.append("")
brief.append("## Aesthetic")
brief.append("")
brief.append(dg("aesthetic"))
brief.append("")

brief.append("## Color Palette")
brief.append("")
brief.append("CSS custom properties for the theme:")
brief.append("")
brief.append("```css")
brief.append(f"--primary: {dg('primaryColor')};")
brief.append(f"--accent: {dg('accentColor')};")
brief.append("```")
brief.append("")

brief.append("## Typography")
brief.append("")
brief.append(f"- **Headings:** {dg('fontHeading')}")
brief.append(f"- **Body:** {dg('fontBody')}")
brief.append("")

brief.append("## Layout")
brief.append("")
brief.append(dg("layout"))
brief.append("")

brief.append("## Mobile Priority")
brief.append("")
brief.append(dg("mobilePriority"))
brief.append("")

brief_path = os.path.join(project_dir, "docs", "design-brief.md")
with open(brief_path, "w") as f:
    f.write("\n".join(brief))

print(f"  Wrote: {spec_path}")
print(f"  Wrote: {brief_path}")
PY

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  ✅ Done"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. cd $PROJECT_DIR"
echo "  2. Review docs/product-spec.md and docs/design-brief.md"
echo "     (fill in any [TODO] markers)"
echo "  3. claude"
echo "  4. > /build-feature Scaffold the project and build the landing page"
echo ""
