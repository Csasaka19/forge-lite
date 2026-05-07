#!/bin/bash
set -e

# Usage: ./scripts/convert-to-spec.sh <input-file> <output-file>
# Supports: .txt, .md, .pdf (pdf requires pdftotext)
#
# This script doesn't call an API — it prepares a prompt you paste into
# Claude Chat (claude.ai) to convert your rough notes into a structured spec.

INPUT="${1:?Usage: ./scripts/convert-to-spec.sh <input-file> [output-file]}"
OUTPUT="${2:-product-spec.md}"
FORGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Extract text based on file type
case "$INPUT" in
  *.pdf)
    if ! command -v pdftotext &> /dev/null; then
      echo "Error: pdftotext not found. Install poppler-utils."
      exit 1
    fi
    TEXT=$(pdftotext "$INPUT" -)
    ;;
  *.txt|*.md|*.text)
    TEXT=$(cat "$INPUT")
    ;;
  *)
    echo "Supported formats: .txt, .md, .pdf"
    exit 1
    ;;
esac

TEMPLATE=$(cat "$FORGE_DIR/templates/project-spec.md")

# Generate the prompt
cat << PROMPT

════════════════════════════════════════════════════════════════
  COPY EVERYTHING BELOW THIS LINE INTO CLAUDE CHAT (claude.ai)
════════════════════════════════════════════════════════════════

I have rough notes about a product I want to build. Convert them into a
structured product specification using the exact template format below.

Rules:
- Fill in every section of the template. If the notes don't mention
  something, make a reasonable assumption and mark it with "[ASSUMED]"
  so I can review it.
- For the Pages & Routes table, infer every page the product needs
  even if the notes don't list them explicitly.
- For edge cases, think about what can go wrong in each flow and list
  at least 3 per feature.
- For the data model, infer the entities and fields from the features.
- Keep the language direct and specific. No marketing fluff.
- Output only the filled-in template. No preamble.

<template>
$TEMPLATE
</template>

<my_notes>
$TEXT
</my_notes>

PROMPT

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Paste the above into Claude Chat. Copy the output to: $OUTPUT"
echo "════════════════════════════════════════════════════════════════"
