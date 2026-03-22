---
name: recall
description: >
  Search and load context from past Claude Code sessions, decisions,
  and project knowledge using QMD. Use when: user says /recall,
  "what did we do", "what was I working on", "remind me about",
  "find that session where", or when starting complex tasks with
  likely prior history.
---

# Recall - Memory Search

Search `~/.claude/vault/` via QMD for prior sessions, decisions, patterns.

## Collections

- **sessions** — Exported Claude Code conversations
- **decisions** — Key architectural/product decisions
- **project-docs** — Product briefs, architecture, design system
- **patterns** — Reusable code patterns and conventions

## Modes

### Temporal ("yesterday", "last week")

Search sessions by date:

```bash
qmd search "2026-03-19" -c sessions -n 10
```

For a date range, use multi-get with glob:

```bash
qmd multi-get "sessions/2026-03-1*.md"
```

### Topic ("what do we know about X")

Hybrid search across all collections (best quality):

```bash
qmd query "<topic>" -n 5
```

Keyword only (faster, no reranker):

```bash
qmd search "<topic>" -n 5
```

Semantic (when exact words are unknown):

```bash
qmd vsearch "<concept>" -n 5
```

Search a specific collection:

```bash
qmd search "<topic>" -c decisions -n 5
```

### Files ("sessions that touched X")

```bash
qmd search "files_touched.*<filename>" -c sessions -n 10
```

## Workflow

1. Determine the recall mode from the user's request
2. Run the appropriate qmd command(s) via Bash
3. Read the top 2-3 results using the Read tool to get full content
4. Synthesize and present the relevant context
5. Ask if the user wants to dig deeper

## Tips

- `qmd search` is instant. Use for quick lookups.
- `qmd query` uses a reranker model. Best quality but slower (~2s).
- `qmd vsearch` finds meaning even without exact keywords.
- Session files are at `~/.claude/vault/sessions/{date}_{id}.md`
- Each session has YAML frontmatter: session_id, date, branch, files_touched, topics
- Use `qmd status` to check vault health and document counts
