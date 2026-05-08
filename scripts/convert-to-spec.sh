#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════════
# forge-convert.sh
#
# Takes any text document describing an app idea and:
#   1. Extracts a project name from the content (or accepts one as arg)
#   2. Creates the project folder via new-project.sh
#   3. Prints a prompt you paste into Claude Chat (claude.ai)
#   4. Claude Chat returns a product-spec.md and design-brief.md
#   5. You paste those into the project's docs/ folder
#
# Usage:
#   ./scripts/forge-convert.sh <input-file> [project-name]
#
# Examples:
#   ./scripts/forge-convert.sh ~/Desktop/water-vending-idea.txt
#   ./scripts/forge-convert.sh ~/Downloads/requirements.pdf smart-parking
#   ./scripts/forge-convert.sh ~/notes/app-concept.md
#
# Supported input formats: .txt, .md, .text, .pdf (requires pdftotext)
# ═══════════════════════════════════════════════════════════════════

INPUT="${1:?
Usage: ./scripts/forge-convert.sh <input-file> [project-name]

  <input-file>    Path to your document (.txt, .md, .pdf)
  [project-name]  Optional. If not given, extracted from the document.

Examples:
  ./scripts/forge-convert.sh ~/Desktop/my-app-idea.txt
  ./scripts/forge-convert.sh ~/Downloads/brief.pdf my-cool-app
}"

MANUAL_NAME="${2:-}"
FORGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ── Check input file exists ──
if [ ! -f "$INPUT" ]; then
  echo "Error: File not found: $INPUT"
  exit 1
fi

# ── Extract text based on file type ──
case "$INPUT" in
  *.pdf)
    if ! command -v pdftotext &> /dev/null; then
      echo ""
      echo "Error: pdftotext is required for PDF files but not installed."
      echo ""
      echo "  Mac:   brew install poppler"
      echo "  Linux: sudo apt install poppler-utils"
      echo ""
      exit 1
    fi
    TEXT=$(pdftotext "$INPUT" - 2>/dev/null)
    if [ -z "$TEXT" ]; then
      echo "Error: Could not extract text from PDF. The file may be scanned/image-based."
      echo "Try: convert it to text first, then run this script on the text file."
      exit 1
    fi
    ;;
  *.txt|*.md|*.text|*.markdown)
    TEXT=$(cat "$INPUT")
    ;;
  *.docx)
    echo ""
    echo "Error: .docx files are not directly supported."
    echo "Please save your document as .txt first:"
    echo "  In Word/Google Docs: File → Download → Plain Text (.txt)"
    echo "Then run this script on the .txt file."
    echo ""
    exit 1
    ;;
  *)
    echo "Supported formats: .txt, .md, .text, .pdf"
    echo "Got: $INPUT"
    exit 1
    ;;
esac

# ── Validate we got content ──
WORD_COUNT=$(echo "$TEXT" | wc -w | tr -d ' ')
if [ "$WORD_COUNT" -lt 10 ]; then
  echo "Error: The file has only $WORD_COUNT words. Need at least 10 to work with."
  echo "Write a bit more about your app idea and try again."
  exit 1
fi

# ── Extract or use project name ──
if [ -n "$MANUAL_NAME" ]; then
  # User provided a name
  PROJECT_NAME="$MANUAL_NAME"
else
  # Extract from content: ask the text for key nouns
  # Strategy: look for common patterns like "X app", "X system", "X platform"
  # Fall back to filename if nothing found
  
  # Try to find "X app/system/platform/tool/dashboard/portal" in the text
  EXTRACTED=$(echo "$TEXT" | \
    grep -oiE '[a-z]+ (app|system|platform|tool|dashboard|portal|manager|tracker|finder|service|marketplace|vending|booking)' | \
    head -1 | \
    tr '[:upper:]' '[:lower:]' | \
    tr ' ' '-' | \
    sed 's/[^a-z0-9-]//g')
  
  if [ -n "$EXTRACTED" ]; then
    PROJECT_NAME="$EXTRACTED"
  else
    # Fall back: use the filename without extension
    BASENAME=$(basename "$INPUT")
    PROJECT_NAME="${BASENAME%.*}"
    PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' _' '-' | sed 's/[^a-z0-9-]//g')
  fi
fi

# Clean up project name
PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' _' '-' | sed 's/[^a-z0-9-]//g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')

if [ -z "$PROJECT_NAME" ]; then
  PROJECT_NAME="new-project"
fi

PROJECT_DIR="$FORGE_DIR/../$PROJECT_NAME"

# ── Show what we detected ──
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Input file:    $INPUT"
echo "  Word count:    $WORD_COUNT words"
echo "  Project name:  $PROJECT_NAME"
echo "  Project folder: $PROJECT_DIR"
echo "════════════════════════════════════════════════════════════════"
echo ""

# ── Ask for confirmation ──
if [ -d "$PROJECT_DIR" ]; then
  echo "⚠️  Project folder already exists: $PROJECT_DIR"
  echo "   The spec files inside docs/ will be overwritten."
  echo ""
  read -p "Continue? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
else
  read -p "Create project '$PROJECT_NAME'? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "To use a different name, run:"
    echo "  ./scripts/forge-convert.sh $INPUT your-preferred-name"
    exit 0
  fi
  
  # ── Create the project folder ──
  echo "Creating project folder..."
  bash "$FORGE_DIR/scripts/new-project.sh" "$PROJECT_NAME"
fi

# ── Load templates ──
SPEC_TEMPLATE=$(cat "$FORGE_DIR/templates/project-spec.md")
DESIGN_TEMPLATE=$(cat "$FORGE_DIR/context/design-system.md")

# ── Generate the Claude Chat prompt ──
PROMPT_TEXT=$(cat << 'PROMPTEOF'
I have rough notes about a product I want to build. I need you to produce
TWO documents from these notes: a product specification and a design brief.
Both must follow the exact templates I provide below.

═══════════════════════════════════
RULES — follow these carefully:
═══════════════════════════════════

1. Fill in EVERY section of both templates. Do not skip any section.

2. If my notes don't mention something, make a reasonable assumption
   and mark it with [ASSUMED — verify this] so I can review it later.

3. For the Pages & Routes table:
   - Infer every page the product needs, even if my notes only mention
     a few. A typical web app has: landing, login, dashboard, detail
     views, forms, settings, error pages.
   - Every page needs a URL route (e.g., /dashboard, /machine/:id).
   - List who can see each page (public, customer, operator, admin).

4. For Edge Cases:
   - Think about what can go wrong in EACH user flow.
   - List at least 3 edge cases per feature.
   - Include: empty states, error states, permission issues, timing
     issues, data validation failures.

5. For the Data Model:
   - Infer every entity (database table) the app needs.
   - List fields with types.
   - Think about relationships between entities.

6. For the Design Brief:
   - Choose specific colors (hex codes) based on the product domain.
   - Choose real font names (not "sans-serif" — name the actual font).
   - Define both light and dark theme variables.
   - Be specific about layout: sidebar vs top-nav, card styles, etc.

7. Format your response EXACTLY like this:

   === START OF product-spec.md ===
   [the full product specification]
   === END OF product-spec.md ===

   === START OF design-brief.md ===
   [the full design brief]
   === END OF design-brief.md ===

   This makes it easy for me to copy each file separately.

═══════════════════════════════════
TEMPLATE 1: Product Specification
═══════════════════════════════════
PROMPTEOF
)

# ── Print the final prompt ──
echo ""
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  COPY EVERYTHING BELOW THIS LINE INTO CLAUDE CHAT (claude.ai)"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "$PROMPT_TEXT"
echo ""
echo "$SPEC_TEMPLATE"
echo ""
cat << 'TEMPLATE2'

═══════════════════════════════════
TEMPLATE 2: Design Brief
═══════════════════════════════════

# [Product Name] — Design Brief

## Aesthetic
[Describe the overall look and feel in 2-3 sentences. Reference
the product domain — e.g., a water utility app should feel clean
and trustworthy, a gaming dashboard should feel energetic.]

## Color Palette (as CSS custom properties)

### Light Theme
- --background: [hex]
- --foreground: [hex]
- --primary: [hex]
- --primary-foreground: [hex]
- --secondary: [hex]
- --muted: [hex]
- --accent: [hex]
- --destructive: [hex]
- --border: [hex]
- --card: [hex]

### Dark Theme
- --background: [hex]
- --foreground: [hex]
- --primary: [hex]
- --secondary: [hex]
- --muted: [hex]
- --accent: [hex]
- --destructive: [hex]
- --border: [hex]
- --card: [hex]

## Typography
- Headings: [actual font name] — [why this font fits the product]
- Body: [actual font name]
- Monospace (for data/numbers): [actual font name]
- Install command: `npm install @fontsource/[font1] @fontsource/[font2]`

## Layout
- [Describe: sidebar nav or top nav? Max content width? Card style?
  Mobile layout strategy?]

## Components
- [Describe specific component patterns: how status indicators look,
  how cards are styled, button hierarchy, form style]

## Mobile Priority
- [Which user type is primarily mobile? Which pages MUST work
  perfectly on 375px?]

## Map / Special Libraries (if applicable)
- [Does the app need a map? Charts? Calendar? List the library
  and install command.]
TEMPLATE2

echo ""
echo "═══════════════════════════════════"
echo "MY NOTES ABOUT THE APP:"
echo "═══════════════════════════════════"
echo ""
echo "$TEXT"
echo ""
echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  STOP COPYING HERE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo ""
echo "NEXT STEPS:"
echo ""
echo "  1. Copy everything above into Claude Chat (claude.ai)"
echo ""
echo "  2. Wait for the response. It will have two sections:"
echo "     === START OF product-spec.md ==="
echo "     === START OF design-brief.md ==="
echo ""
echo "  3. Copy the product spec into:"
echo "     $PROJECT_DIR/docs/product-spec.md"
echo ""
echo "  4. Copy the design brief into:"
echo "     $PROJECT_DIR/docs/design-brief.md"
echo ""
echo "  5. Then start building:"
echo "     cd $PROJECT_DIR"
echo "     claude"
echo "     > /build-feature Scaffold the project and build the landing page"
echo ""
echo "════════════════════════════════════════════════════════════════"
