#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════════
# text-to-json.sh
#
# Converts unstructured notes (.txt / .md) into the structured JSON
# format that json-to-spec.sh consumes. It prints a Claude Chat prompt;
# you paste it into claude.ai, get JSON back, save the JSON, then run
# json-to-spec.sh on it.
#
# Usage:
#   ./scripts/text-to-json.sh <input.txt|input.md>
#
# Examples:
#   ./scripts/text-to-json.sh fixtures/efficiency-tracker-notes.txt
#   ./scripts/text-to-json.sh ~/Desktop/app-idea.md
# ═══════════════════════════════════════════════════════════════════

INPUT="${1:-}"

if [ -z "$INPUT" ]; then
  cat <<USAGE
Usage: ./scripts/text-to-json.sh <input.txt|input.md>

  <input>  Path to a plain-text or markdown file of rough notes.

Examples:
  ./scripts/text-to-json.sh fixtures/efficiency-tracker-notes.txt
  ./scripts/text-to-json.sh ~/Desktop/app-idea.md
USAGE
  exit 1
fi

if [ ! -f "$INPUT" ]; then
  echo "Error: File not found: $INPUT"
  exit 1
fi

case "$INPUT" in
  *.txt|*.md|*.text|*.markdown) ;;
  *)
    echo "Error: Supported formats are .txt, .md, .text, .markdown"
    echo "Got: $INPUT"
    exit 1
    ;;
esac

TEXT=$(cat "$INPUT")
WORD_COUNT=$(echo "$TEXT" | wc -w | tr -d ' ')

if [ "$WORD_COUNT" -lt 10 ]; then
  echo "Error: The file has only $WORD_COUNT words. Need at least 10."
  echo "Add more detail about the app and try again."
  exit 1
fi

OUT_NAME="$(basename "${INPUT%.*}").json"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Input:        $INPUT"
echo "  Word count:   $WORD_COUNT words"
echo "  Suggested:    save Claude's reply as  $OUT_NAME"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  COPY EVERYTHING BELOW THIS LINE INTO CLAUDE CHAT (claude.ai)"
echo "════════════════════════════════════════════════════════════════"
echo ""

cat <<'PROMPT'
I have rough, informal notes about a web app I want to build. Read the
notes carefully and convert them into a single JSON document that
matches the schema below exactly.

═══════════════════════════════════
RULES — follow these strictly:
═══════════════════════════════════

1. OUTPUT ONLY VALID JSON. No prose before or after. No markdown code
   fences (no ```json). No commentary. Just the JSON object, starting
   with `{` and ending with `}`.

2. Fill in EVERY field of the schema. If the notes don't say something,
   make a reasonable assumption based on the product domain and prefix
   the value with the literal string "[ASSUMED] " so I can review it
   later. Example: "[ASSUMED] Solo founders tracking their own time."

3. For "pages": infer every page a typical app of this type needs, even
   if the notes only mention a few. A typical web app has: a landing
   page, login, dashboard, detail views, forms, settings, and a
   not-found page. Aim for 6-12 pages.

4. For "features": each feature needs a userFlow array (3-7 steps) and
   an edgeCases array (3-5 cases). Think about empty states, errors,
   permission issues, timing, and validation failures.

5. For "dataModel": infer every entity the app needs. Each entity is an
   object whose keys are field names and values are TypeScript-ish
   type strings (e.g. "string", "number", "Date", "'draft' | 'live'").

6. For "design": pick concrete hex colors that fit the product domain.
   Pick real font names (e.g. "Inter", "JetBrains Mono"), not the
   generic "sans-serif".

7. Use double quotes for all strings. No trailing commas. No comments.

═══════════════════════════════════
SCHEMA — produce JSON matching this exactly:
═══════════════════════════════════

{
  "name": "string (kebab-case, e.g. efficiency-tracker)",
  "description": "string (one sentence)",
  "problemStatement": "string (1-3 sentences)",
  "users": [
    { "type": "string (role name)", "goal": "string (what they want)" }
  ],
  "features": [
    {
      "name": "string",
      "description": "string",
      "userFlow": ["step 1", "step 2", "step 3"],
      "edgeCases": ["case 1", "case 2", "case 3"]
    }
  ],
  "pages": [
    {
      "name": "string",
      "route": "string (e.g. /, /dashboard, /task/:id)",
      "who": "string (public, customer, manager, admin, etc.)",
      "shows": "string (what's on this page)"
    }
  ],
  "dataModel": {
    "EntityName": {
      "fieldName": "fieldType"
    }
  },
  "design": {
    "aesthetic": "string (overall look & feel)",
    "primaryColor": "#hex",
    "accentColor": "#hex",
    "fontHeading": "string (real font name)",
    "fontBody": "string (real font name)",
    "layout": "string (sidebar vs top-nav, widths, etc.)",
    "mobilePriority": "string (which user types/pages are mobile-critical)"
  },
  "outOfScope": ["item 1", "item 2"],
  "openQuestions": ["question 1", "question 2"]
}

═══════════════════════════════════
MY ROUGH NOTES:
═══════════════════════════════════

PROMPT

echo "$TEXT"
echo ""
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  STOP COPYING HERE"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "NEXT STEPS:"
echo ""
echo "  1. Paste everything above into Claude Chat (claude.ai)."
echo "  2. Claude will reply with a single JSON object."
echo "  3. Save that reply as a file, e.g.:"
echo "       $OUT_NAME"
echo "  4. Then run:"
echo "       ./scripts/json-to-spec.sh $OUT_NAME"
echo ""
echo "  Review any \"[ASSUMED] ...\" values before building."
echo ""
