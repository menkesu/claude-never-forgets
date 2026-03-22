---
name: setup-memory
description: >
  Set up a persistent memory system for Claude Code using QMD (local search engine
  by Tobias Lutke). Installs QMD, creates a vault, exports past sessions to searchable
  markdown, configures auto-indexing hooks, and installs the /recall skill. Use when:
  user says /setup-memory, "set up memory", "install QMD", "make sessions searchable",
  "I want Claude to remember past sessions", or when setting up a new machine/project
  with the QMD memory system.
---

# Setup Memory — QMD-based Context Recall for Claude Code

Give Claude Code persistent memory across sessions using QMD, a local search engine
with BM25, semantic, and hybrid search. Based on Artem Zhutov's "Grep Is Dead" approach.

**Source**: [github.com/tobi/qmd](https://github.com/tobi/qmd) by Tobias Lutke (Shopify CEO)

## What This Sets Up

```
~/.claude/vault/              Searchable knowledge base
├── sessions/                 Auto-exported Claude Code conversations
├── decisions/                Key architectural/product decisions
├── project-docs/             Project documentation
└── patterns/                 Reusable code patterns

~/.claude/hooks/              Automation scripts
├── session-export.py         JSONL → markdown converter
└── session-end.sh            SessionEnd hook (auto-exports on close)

.claude/skills/recall/        /recall skill for searching the vault
```

## Quick Setup (Automated)

Run the setup script — it handles everything:

```bash
bash .claude/skills/setup-memory/scripts/setup.sh
```

The script will:

1. Install QMD globally via npm
2. Create the vault directory structure
3. Install hook scripts to `~/.claude/hooks/`
4. Configure 4 QMD collections (sessions, decisions, project-docs, patterns)
5. Copy any `docs/` files into the vault
6. Auto-detect and backfill existing Claude Code sessions
7. Generate search embeddings (~330MB model download on first run)
8. Install the QMD skill globally

After the script completes, finish the manual steps it prints.

## Manual Setup (Step by Step)

### 1. Install QMD

```bash
npm install -g @tobilu/qmd
```

### 2. Create vault and install hooks

```bash
mkdir -p ~/.claude/vault/{sessions,decisions,project-docs,patterns}
mkdir -p ~/.claude/hooks
cp .claude/skills/setup-memory/scripts/session-export.py ~/.claude/hooks/
cp .claude/skills/setup-memory/scripts/session-end.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/session-end.sh
```

### 3. Configure QMD collections

```bash
qmd collection add ~/.claude/vault/sessions --name sessions
qmd collection add ~/.claude/vault/decisions --name decisions
qmd collection add ~/.claude/vault/project-docs --name project-docs
qmd collection add ~/.claude/vault/patterns --name patterns
```

### 4. Copy project docs into vault

```bash
cp docs/*.md ~/.claude/vault/project-docs/
```

Note: QMD does not follow symlinks. Use file copies.

### 5. Backfill existing sessions

```bash
python3 ~/.claude/hooks/session-export.py \
  --backfill ~/.claude/projects/<project-path>/
```

Find the project path: `ls ~/.claude/projects/`

### 6. Index and embed

```bash
qmd update
qmd embed    # First run downloads ~330MB embedding model
```

### 7. Add SessionEnd hook

Add to `.claude/settings.json` inside the `"hooks"` object:

```json
"SessionEnd": [
  {
    "hooks": [
      {
        "type": "command",
        "command": "bash ~/.claude/hooks/session-end.sh",
        "timeout": 5
      }
    ]
  }
]
```

### 8. Install /recall skill

```bash
cp -r .claude/skills/setup-memory/assets/recall-skill .claude/skills/recall
```

### 9. Add to CLAUDE.md

```markdown
## Session Startup

For complex tasks or when continuing prior work, use `/recall` to load
context from past sessions. The vault at `~/.claude/vault/` contains
all session history, searchable via QMD (`qmd query "<topic>"`).
```

## How It Works

**Session export**: Each JSONL session is parsed to extract only user messages and
assistant text responses (no tool calls, no thinking blocks). Output is clean markdown
with YAML frontmatter containing session_id, date, branch, files_touched, and topics.

**SessionEnd hook**: Fires when you close Claude Code. Exports the session and
re-indexes QMD in the background. Under 500ms for the export; embedding is backgrounded.

**QMD search modes**:

- `qmd search "topic"` — BM25 keyword search (instant)
- `qmd vsearch "concept"` — Semantic search by meaning (finds related content even without exact words)
- `qmd query "question"` — Hybrid with reranking (best quality, ~2s)

**/recall skill**: Wraps QMD search with three modes — temporal (by date), topic
(by concept), and files (by files touched). Claude reads top results and synthesizes context.

## Seeding the Vault

After setup, optionally seed `decisions/` and `patterns/` with project knowledge:

```bash
cat > ~/.claude/vault/decisions/my-feature.md << 'EOF'
---
date: 2026-03
status: completed
---
# My Feature
What was built, why, and key implementation details.
## Key files
- path/to/main/file.ts
EOF
```

## Troubleshooting

- **`qmd: command not found`** — Ensure npm global bin is in PATH: `export PATH="$PATH:$(npm bin -g)"`
- **Embedding fails** — First `qmd embed` downloads a ~330MB model. Needs internet.
- **Hook doesn't fire** — Verify `SessionEnd` is inside the `"hooks"` key in settings.json
- **0 files indexed** — Run `qmd update` after adding files. QMD doesn't auto-detect new files.
- **Symlinks show 0 files** — QMD doesn't follow symlinks. Copy files instead.
