#!/bin/bash
# setup.sh - One-command setup for the QMD memory system
# Usage: bash setup.sh [project-sessions-dir]
#
# project-sessions-dir: Path to Claude Code sessions directory (optional)
#   Default: auto-detected from ~/.claude/projects/

set -e

VAULT_DIR="$HOME/.claude/vault"
HOOKS_DIR="$HOME/.claude/hooks"
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== QMD Memory System Setup ==="
echo ""

# Step 1: Install QMD
if command -v qmd &>/dev/null; then
  echo "✓ QMD already installed ($(qmd --version 2>/dev/null || echo 'version unknown'))"
else
  echo "Installing QMD..."
  npm install -g @tobilu/qmd
  echo "✓ QMD installed"
fi

# Step 2: Create vault structure
echo ""
echo "Creating vault at $VAULT_DIR..."
mkdir -p "$VAULT_DIR"/{sessions,decisions,project-docs,patterns}
mkdir -p "$HOOKS_DIR"
echo "✓ Vault directories created"

# Step 3: Install hook scripts
echo ""
echo "Installing hook scripts..."
cp "$SKILL_DIR/session-export.py" "$HOOKS_DIR/session-export.py"
cp "$SKILL_DIR/session-end.sh" "$HOOKS_DIR/session-end.sh"
chmod +x "$HOOKS_DIR/session-end.sh"
echo "✓ Hook scripts installed at $HOOKS_DIR"

# Step 4: Configure QMD collections
echo ""
echo "Configuring QMD collections..."
for col in sessions decisions project-docs patterns; do
  if qmd collection list 2>/dev/null | grep -q "^$col "; then
    echo "  Collection '$col' already exists"
  else
    qmd collection add "$VAULT_DIR/$col" --name "$col" 2>/dev/null
    echo "  ✓ Added collection: $col"
  fi
done

# Step 5: Add context descriptions
echo ""
echo "Adding collection context..."
qmd context add "qmd://sessions/" "Exported Claude Code conversation sessions with timestamps, topics, and files modified" 2>/dev/null || true
qmd context add "qmd://decisions/" "Key architectural and product decisions made during development" 2>/dev/null || true
qmd context add "qmd://project-docs/" "Project documentation, briefs, architecture docs, and guides" 2>/dev/null || true
qmd context add "qmd://patterns/" "Reusable code patterns, debugging notes, and conventions" 2>/dev/null || true
echo "✓ Context descriptions added"

# Step 6: Copy project docs if in a project directory
if [ -d "docs" ]; then
  echo ""
  echo "Found docs/ directory — copying to vault..."
  cp docs/*.md "$VAULT_DIR/project-docs/" 2>/dev/null || true
  echo "✓ Project docs copied"
fi

# Step 7: Backfill existing sessions
SESSIONS_DIR="${1:-}"
if [ -z "$SESSIONS_DIR" ]; then
  # Auto-detect: find the most recent project sessions directory
  SESSIONS_DIR=$(find "$HOME/.claude/projects" -name "*.jsonl" -maxdepth 2 2>/dev/null | head -1 | xargs dirname 2>/dev/null || echo "")
fi

if [ -n "$SESSIONS_DIR" ] && [ -d "$SESSIONS_DIR" ]; then
  SESSION_COUNT=$(ls "$SESSIONS_DIR"/*.jsonl 2>/dev/null | wc -l | tr -d ' ')
  echo ""
  echo "Found $SESSION_COUNT sessions in $SESSIONS_DIR"
  echo "Backfilling..."
  python3 "$HOOKS_DIR/session-export.py" --backfill "$SESSIONS_DIR"
else
  echo ""
  echo "⚠ No sessions directory found. Skipping backfill."
  echo "  Run manually: python3 ~/.claude/hooks/session-export.py --backfill /path/to/sessions/"
fi

# Step 8: Index and embed
echo ""
echo "Indexing vault..."
qmd update 2>&1
echo ""
echo "Generating embeddings (first run downloads ~330MB model)..."
qmd embed 2>&1
echo "✓ Vault indexed and embedded"

# Step 9: Install QMD skill globally
echo ""
echo "Installing QMD skill..."
qmd skill install --global 2>/dev/null || true
echo "✓ QMD skill installed"

# Step 10: Print next steps
echo ""
echo "============================================"
echo "✓ QMD Memory System setup complete!"
echo "============================================"
echo ""
echo "Vault: $VAULT_DIR"
echo "Hooks: $HOOKS_DIR"
echo ""
echo "REMAINING MANUAL STEPS:"
echo ""
echo "1. Add SessionEnd hook to your project's .claude/settings.json:"
echo '   "hooks": {'
echo '     "SessionEnd": ['
echo '       {'
echo '         "hooks": ['
echo '           {'
echo '             "type": "command",'
echo '             "command": "bash ~/.claude/hooks/session-end.sh",'
echo '             "timeout": 5'
echo '           }'
echo '         ]'
echo '       }'
echo '     ]'
echo '   }'
echo ""
echo "2. Install the /recall skill:"
echo "   Copy the recall/ skill folder into your project's .claude/skills/"
echo ""
echo "3. Add to your CLAUDE.md:"
echo '   ## Session Startup'
echo '   For complex tasks, use /recall to load context from past sessions.'
echo '   The vault at ~/.claude/vault/ is searchable via QMD.'
echo ""
echo "4. Test it:"
echo '   qmd search "your topic" -n 5'
echo '   qmd query "your question" -n 3'
echo ""
