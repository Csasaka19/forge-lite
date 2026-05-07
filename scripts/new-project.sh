#!/bin/bash
set -e

# Usage: ./scripts/new-project.sh <project-name>
# Run from the forge-lite/ directory.

PROJECT_NAME="${1:?Usage: ./scripts/new-project.sh <project-name>}"
FORGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$FORGE_DIR/../$PROJECT_NAME"

if [ -d "$PROJECT_DIR" ]; then
  echo "Error: $PROJECT_DIR already exists."
  exit 1
fi

echo "Creating project: $PROJECT_NAME"
echo "Location: $PROJECT_DIR"
echo ""

# Create project directory structure
mkdir -p "$PROJECT_DIR"/{docs,.claude/{rules,commands}}

# Copy templates
cp "$FORGE_DIR/templates/CLAUDE.md.template" "$PROJECT_DIR/CLAUDE.md"
cp "$FORGE_DIR/templates/project-spec.md" "$PROJECT_DIR/docs/product-spec.md"
cp "$FORGE_DIR/context/react-stack.md" "$PROJECT_DIR/docs/react-stack.md"
cp "$FORGE_DIR/context/design-system.md" "$PROJECT_DIR/docs/design-system.md"

# Create the .claude/rules/react-conventions.md (lazy-loaded when touching .tsx files)
cat > "$PROJECT_DIR/.claude/rules/react-conventions.md" << 'RULE'
---
paths:
  - "**/*.tsx"
  - "**/*.ts"
---
When writing React components, follow the conventions in docs/react-stack.md.
Read it before creating any new component. Key rules:
- Functional components only.
- Named exports for shared components, default exports for pages.
- Mobile-first Tailwind classes.
- Every interactive element needs a visible focus state.
- Run `npm run dev` after creating each page to verify it renders.
RULE

# Create the build-feature command
cat > "$PROJECT_DIR/.claude/commands/build-feature.md" << 'CMD'
Build a feature for this project. Follow this procedure:

1. Read docs/product-spec.md to understand the full product.
2. Read docs/design-brief.md for visual direction.
3. Identify which feature or page to build based on my request.
4. Plan the implementation: list the files you'll create or modify.
5. Build it. After each file, verify the build still passes (`npm run dev`).
6. Handle all states: default, loading, empty, error.
7. Test on mobile viewport (375px) mentally — use mobile-first classes.
8. When done, show me what was created and any remaining TODOs.

If the project hasn't been scaffolded yet, scaffold it first using the react-vite-builder skill.
CMD

# Create the review command
cat > "$PROJECT_DIR/.claude/commands/review.md" << 'CMD'
Review the current state of this project:

1. Read docs/product-spec.md and compare it to what's built.
2. List every page/feature from the spec.
3. For each, mark: ✅ built, 🟡 partial, ❌ not started.
4. Check for: broken links, missing error states, mobile responsiveness issues.
5. Run `npm run build` and report any errors.
6. Summarize: what's done, what's left, what's broken.
CMD

# Initialize git
cd "$PROJECT_DIR"
git init
echo "node_modules/\ndist/\n.env\n.env.local\n*.log\n.DS_Store" > .gitignore

# Replace placeholder in CLAUDE.md
sed -i "s/\[Project Name\]/$PROJECT_NAME/g" CLAUDE.md 2>/dev/null || \
  sed -i '' "s/\[Project Name\]/$PROJECT_NAME/g" CLAUDE.md

echo ""
echo "✅ Project scaffolded at: $PROJECT_DIR"
echo ""
echo "Next steps:"
echo "  1. cd $PROJECT_DIR"
echo "  2. Edit docs/product-spec.md with your product details"
echo "  3. Edit docs/design-brief.md with your visual direction"
echo "  4. Open Claude Code: claude"
echo "  5. Say: /build-feature scaffold the project and build the home page"
echo ""
