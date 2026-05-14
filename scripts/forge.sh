#!/bin/bash

# ═══════════════════════════════════════════════════════════════════
# forge.sh — Forge Lite command-line tool
#
# Single entry point for creating, listing, inspecting, and opening
# projects scaffolded by Forge Lite.
#
# Subcommands:
#   new      Create a project from a .json / .txt / .md / .pdf file
#   list     List projects under the projects parent directory
#   status   Show which pages from the spec are built
#   open     cd into a project and launch Claude Code
#
# Run `./scripts/forge.sh --help` for full usage.
# ═══════════════════════════════════════════════════════════════════

FORGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECTS_DIR="$(cd "$FORGE_DIR/.." && pwd)"

# ── Colors (auto-disable when not a TTY) ──
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m'
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  RESET=$'\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' BOLD='' DIM='' RESET=''
fi

err()  { echo "${RED}Error:${RESET} $*" >&2; }
warn() { echo "${YELLOW}Warning:${RESET} $*" >&2; }
ok()   { echo "${GREEN}$*${RESET}"; }
head_() { echo "${BOLD}$*${RESET}"; }

# ═══════════════════════════════════════════════════════════════════
# Help
# ═══════════════════════════════════════════════════════════════════
print_help() {
  cat <<HELP
${BOLD}forge.sh${RESET} — Forge Lite command-line tool

${BOLD}USAGE${RESET}
  ./scripts/forge.sh <command> [args]

${BOLD}COMMANDS${RESET}
  ${GREEN}new${RESET} <file>              Create a project, auto-detecting the input
  ${GREEN}new${RESET} <file> --name NAME  ... with a specific project name
  ${GREEN}new${RESET} --name NAME         Create an empty project (template files)
  ${GREEN}list${RESET}                    List all projects under $PROJECTS_DIR
  ${GREEN}status${RESET} <project>        Show build status of a project
  ${GREEN}open${RESET} <project>          cd into project and launch Claude Code
  ${GREEN}--help${RESET}, -h, help        Show this help

${BOLD}INPUT TYPES FOR 'new'${RESET}
  .json (Forge)     → runs json-to-spec.sh directly (no Claude Chat needed)
  .json (Whimsical) → runs whimsical-to-spec.sh (auto-detected by schema_version)
  .txt / .md        → runs text-to-json.sh (prints a Claude Chat prompt)
  .pdf              → extracts text via pdftotext, then treats as .txt
  (no file)         → creates an empty project from the template

${BOLD}EXAMPLES${RESET}
  ./scripts/forge.sh new fixtures/sample-water-vending.json
  ./scripts/forge.sh new fixtures/efficiency-tracker-notes.txt
  ./scripts/forge.sh new ~/Desktop/brief.pdf --name client-portal
  ./scripts/forge.sh new --name blank-experiment
  ./scripts/forge.sh list
  ./scripts/forge.sh status water-vending-finder
  ./scripts/forge.sh open water-vending-finder

${BOLD}ENVIRONMENT${RESET}
  NO_COLOR=1   Disable ANSI color codes (also auto-disabled when piped).
HELP
}

# ═══════════════════════════════════════════════════════════════════
# new — create a project from any input type
# ═══════════════════════════════════════════════════════════════════
cmd_new() {
  local input="" name=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --name)      name="${2:?--name requires a value}"; shift 2 ;;
      --name=*)    name="${1#--name=}"; shift ;;
      -h|--help)   print_help; return 0 ;;
      -*)          err "Unknown flag: $1"; return 1 ;;
      *)
        if [ -z "$input" ]; then
          input="$1"
        else
          err "Unexpected argument: $1"
          return 1
        fi
        shift ;;
    esac
  done

  # No file → empty scaffold (requires --name)
  if [ -z "$input" ]; then
    if [ -z "$name" ]; then
      err "Either provide a file or use --name to create an empty project."
      echo "Examples:"
      echo "  ./scripts/forge.sh new spec.json"
      echo "  ./scripts/forge.sh new notes.txt"
      echo "  ./scripts/forge.sh new --name my-app"
      return 1
    fi
    head_ "Creating empty project: $name"
    echo ""
    bash "$FORGE_DIR/scripts/new-project.sh" "$name"
    return $?
  fi

  if [ ! -f "$input" ]; then
    err "File not found: $input"
    return 1
  fi

  # Dispatch by extension
  case "$input" in
    *.json)
      # Peek inside the JSON to distinguish Whimsical exports
      # (have "mindmaps" + "schema_version") from standard Forge specs.
      local is_whimsical=0
      if python3 - "$input" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if (isinstance(d.get("mindmaps"), list) and d.get("schema_version")) else 1)
PY
      then
        is_whimsical=1
      fi

      if [ "$is_whimsical" -eq 1 ]; then
        head_ "Detected Whimsical mindmap export — running whimsical-to-spec.sh"
        echo ""
        if [ -n "$name" ]; then
          bash "$FORGE_DIR/scripts/whimsical-to-spec.sh" "$input" "$name"
        else
          bash "$FORGE_DIR/scripts/whimsical-to-spec.sh" "$input"
        fi
      else
        head_ "Detected JSON spec — running json-to-spec.sh"
        echo ""
        if [ -n "$name" ]; then
          bash "$FORGE_DIR/scripts/json-to-spec.sh" "$input" "$name"
        else
          bash "$FORGE_DIR/scripts/json-to-spec.sh" "$input"
        fi
      fi
      ;;

    *.txt|*.md|*.text|*.markdown)
      head_ "Detected text notes — running text-to-json.sh"
      echo ""
      bash "$FORGE_DIR/scripts/text-to-json.sh" "$input"
      if [ -n "$name" ]; then
        echo ""
        warn "The --name flag is not used for text input."
        echo "When you save Claude Chat's JSON reply, pass --name to json-to-spec.sh:"
        echo "  ./scripts/json-to-spec.sh your-reply.json $name"
      fi
      ;;

    *.pdf)
      if ! command -v pdftotext &> /dev/null; then
        err "pdftotext is required for PDF input but is not installed."
        echo "  Mac:   brew install poppler"
        echo "  Linux: sudo apt install poppler-utils"
        return 1
      fi
      head_ "Detected PDF — extracting text with pdftotext"
      local tmp
      tmp="$(mktemp -t forge-pdf-XXXXXX.txt)"
      if ! pdftotext "$input" "$tmp" 2>/dev/null; then
        err "Failed to extract text from PDF."
        rm -f "$tmp"
        return 1
      fi
      if [ ! -s "$tmp" ]; then
        err "PDF produced no text (it may be a scanned image)."
        echo "Try OCR first, save as .txt, then re-run forge new on the .txt."
        rm -f "$tmp"
        return 1
      fi
      echo "${DIM}Extracted to: $tmp${RESET}"
      echo ""
      bash "$FORGE_DIR/scripts/text-to-json.sh" "$tmp"
      if [ -n "$name" ]; then
        echo ""
        warn "The --name flag is not used for text/PDF input."
        echo "When you save Claude Chat's JSON reply, pass --name to json-to-spec.sh:"
        echo "  ./scripts/json-to-spec.sh your-reply.json $name"
      fi
      ;;

    *)
      err "Unsupported file type: $input"
      echo "Supported: .json, .txt, .md, .pdf"
      return 1
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════
# list — scan PROJECTS_DIR for projects with a CLAUDE.md
# ═══════════════════════════════════════════════════════════════════
cmd_list() {
  if [ ! -d "$PROJECTS_DIR" ]; then
    err "Projects directory not found: $PROJECTS_DIR"
    return 1
  fi

  head_ "Projects under $PROJECTS_DIR"
  echo ""

  # Fixed-width columns. We compute padding BEFORE applying colors so
  # the non-printing escape codes don't break alignment.
  local name_w=28 spec_w=12 built_w=10
  printf "${BOLD}%-${name_w}s %-${spec_w}s %-${built_w}s${RESET}\n" "NAME" "SPEC" "BUILT"
  printf "%-${name_w}s %-${spec_w}s %-${built_w}s\n" \
    "$(printf -- '-%.0s' $(seq 1 $name_w))" \
    "$(printf -- '-%.0s' $(seq 1 $spec_w))" \
    "$(printf -- '-%.0s' $(seq 1 $built_w))"

  local found=0
  for dir in "$PROJECTS_DIR"/*/; do
    [ -d "$dir" ] || continue
    [ -f "$dir/CLAUDE.md" ] || continue
    found=$((found+1))

    local name
    name="$(basename "$dir")"

    # Spec: missing, template-only, or filled?
    local spec_text spec_color
    if [ -f "$dir/docs/product-spec.md" ]; then
      if head -1 "$dir/docs/product-spec.md" | grep -q '\[Product Name\]'; then
        spec_text="template"; spec_color="$YELLOW"
      else
        spec_text="filled"; spec_color="$GREEN"
      fi
    else
      spec_text="missing"; spec_color="$RED"
    fi

    # Built: src/ implies Claude Code has started building
    local built_text built_color
    if [ -d "$dir/src" ]; then
      built_text="yes"; built_color="$GREEN"
    else
      built_text="no"; built_color="$DIM"
    fi

    local name_pad spec_pad built_pad
    name_pad=$(printf "%-${name_w}s" "$name")
    spec_pad=$(printf "%-${spec_w}s" "$spec_text")
    built_pad=$(printf "%-${built_w}s" "$built_text")

    echo "${name_pad} ${spec_color}${spec_pad}${RESET} ${built_color}${built_pad}${RESET}"
  done

  if [ "$found" -eq 0 ]; then
    echo "${DIM}(no projects with CLAUDE.md found)${RESET}"
  else
    echo ""
    echo "${DIM}$found project(s)${RESET}"
  fi
}

# ═══════════════════════════════════════════════════════════════════
# status — check which pages from the spec exist in src/
# ═══════════════════════════════════════════════════════════════════
cmd_status() {
  local project="${1:-}"
  if [ -z "$project" ]; then
    err "Usage: forge status <project>"
    return 1
  fi

  local dir="$PROJECTS_DIR/$project"
  if [ ! -d "$dir" ]; then
    err "Project not found: $dir"
    return 1
  fi

  head_ "Status: $project"
  echo "${DIM}$dir${RESET}"
  echo ""

  local spec="$dir/docs/product-spec.md"
  if [ ! -f "$spec" ]; then
    err "docs/product-spec.md not found — nothing to compare against."
    return 1
  fi

  head_ "Pages"
  python3 - "$spec" "$dir" <<'PY'
import sys, re, os

spec_path, project_dir = sys.argv[1], sys.argv[2]

with open(spec_path) as f:
    text = f.read()

m = re.search(r"##\s+Pages\s*&\s*Routes\s*\n(.+?)(?=\n##\s+|\Z)",
              text, re.DOTALL)
if not m:
    print("  (no Pages & Routes section found in product-spec.md)")
    sys.exit(0)

rows = []
for line in m.group(1).splitlines():
    line = line.strip()
    if not line.startswith("|"):
        continue
    if re.match(r"^\|[\s|:-]+\|?$", line):
        continue
    cells = [c.strip() for c in line.strip("|").split("|")]
    if len(cells) < 2:
        continue
    if cells[0].lower() == "page":
        continue
    rows.append(cells)

def variations(page_name: str, route: str):
    cleaned = re.sub(r"[^\w\s/-]", " ", page_name)
    words = [w for w in re.split(r"[\s/\-_]+", cleaned) if w]
    pascal = "".join(w.capitalize() for w in words) if words else ""
    kebab = "-".join(w.lower() for w in words) if words else ""
    flat = "".join(w.lower() for w in words) if words else ""

    cands = [c for c in (pascal, kebab, flat) if c]

    if route:
        if route == "/":
            cands += ["Home", "Index", "home", "index"]
        else:
            segs = [s for s in route.strip("/").split("/")
                    if s and not s.startswith(":")]
            if segs:
                last = segs[-1]
                cands += [last.capitalize(), last.lower()]
    return list(dict.fromkeys(cands))

search_dirs = [
    os.path.join(project_dir, "src", "pages"),
    os.path.join(project_dir, "src", "routes"),
    os.path.join(project_dir, "src", "views"),
    os.path.join(project_dir, "app"),
    os.path.join(project_dir, "pages"),
]
exts = [".tsx", ".ts", ".jsx", ".js"]

def locate(name: str, route: str):
    for cand in variations(name, route):
        for base in search_dirs:
            if not os.path.isdir(base):
                continue
            for ext in exts:
                p = os.path.join(base, cand + ext)
                if os.path.exists(p):
                    return p
                p = os.path.join(base, cand, "index" + ext)
                if os.path.exists(p):
                    return p
    return None

GREEN = "\033[0;32m"
RED   = "\033[0;31m"
DIM   = "\033[2m"
RESET = "\033[0m"
if not sys.stdout.isatty() or os.environ.get("NO_COLOR"):
    GREEN = RED = DIM = RESET = ""

built = 0
for cells in rows:
    page_name = cells[0]
    route = cells[1] if len(cells) > 1 else ""
    found = locate(page_name, route)
    if found:
        built += 1
        rel = os.path.relpath(found, project_dir)
        print(f"  {GREEN}✅{RESET} {page_name:<22s} {DIM}{route:<22s}{RESET}  → {rel}")
    else:
        print(f"  {RED}❌{RESET} {page_name:<22s} {DIM}{route:<22s}{RESET}")

print()
total = len(rows)
if total == 0:
    print("  (Pages & Routes table is empty)")
else:
    pct = (built * 100) // total
    print(f"  {built}/{total} pages built ({pct}%)")
PY

  # ── Build checks ──
  echo ""
  head_ "Build"

  if [ ! -f "$dir/package.json" ]; then
    echo "  ${YELLOW}!${RESET} package.json not found — project hasn't been scaffolded with npm yet."
    return 0
  fi

  if grep -q '"dev"[[:space:]]*:' "$dir/package.json"; then
    echo "  ${GREEN}✓${RESET} npm run dev script is defined"
  else
    echo "  ${RED}✗${RESET} npm run dev is NOT defined in package.json"
  fi

  if grep -q '"build"[[:space:]]*:' "$dir/package.json"; then
    local log="/tmp/forge-build-$$-$(date +%s).log"
    echo "  ${DIM}Running 'npm run build' (this may take a minute)...${RESET}"
    if ( cd "$dir" && npm run build ) > "$log" 2>&1; then
      echo "  ${GREEN}✓${RESET} npm run build passes"
      rm -f "$log"
    else
      echo "  ${RED}✗${RESET} npm run build FAILED"
      echo "    log: $log"
      echo "    last 5 lines:"
      tail -5 "$log" | sed 's/^/      /'
    fi
  else
    echo "  ${RED}✗${RESET} npm run build is NOT defined in package.json"
  fi
}

# ═══════════════════════════════════════════════════════════════════
# open — cd into a project and exec claude
# ═══════════════════════════════════════════════════════════════════
cmd_open() {
  local project="${1:-}"
  if [ -z "$project" ]; then
    err "Usage: forge open <project>"
    return 1
  fi

  local dir="$PROJECTS_DIR/$project"
  if [ ! -d "$dir" ]; then
    err "Project not found: $dir"
    echo "Run './scripts/forge.sh list' to see available projects."
    return 1
  fi

  if ! command -v claude &> /dev/null; then
    err "claude CLI not found in PATH."
    echo "Install instructions: https://docs.claude.com/en/docs/claude-code"
    echo ""
    echo "You can still cd into the project manually:"
    echo "  cd $dir"
    return 1
  fi

  head_ "Opening Claude Code in $project"
  echo "${DIM}$dir${RESET}"
  echo ""
  cd "$dir" && exec claude
}

# ═══════════════════════════════════════════════════════════════════
# Dispatch
# ═══════════════════════════════════════════════════════════════════
CMD="${1:-}"
[ "$#" -gt 0 ] && shift

case "$CMD" in
  new)            cmd_new "$@" ;;
  list|ls)        cmd_list "$@" ;;
  status)         cmd_status "$@" ;;
  open)           cmd_open "$@" ;;
  help|--help|-h) print_help ;;
  "")             print_help; exit 1 ;;
  *)
    err "Unknown command: $CMD"
    echo ""
    print_help
    exit 1
    ;;
esac
