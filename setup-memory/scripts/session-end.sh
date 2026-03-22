#!/bin/bash
# session-end.sh - SessionEnd hook for Claude Code
# Exports the completed session to the vault and re-indexes QMD

LOG=~/.claude/hooks/session-end.log

log() { echo "$(date '+%H:%M:%S') $1" >> "$LOG"; }

log "Hook started"

INPUT=$(cat)
log "Got input (${#INPUT} bytes)"

# Quick check: is python3 available?
if ! command -v python3 &>/dev/null; then
  log "python3 not found, exiting"
  exit 0
fi

TRANSCRIPT_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)
log "Transcript: $TRANSCRIPT_PATH"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  log "No valid transcript, exiting"
  exit 0
fi

# Check export script exists
if [ ! -f ~/.claude/hooks/session-export.py ]; then
  log "session-export.py not found, exiting"
  exit 0
fi

# Ensure qmd is in PATH (npm global bin)
export PATH="$PATH:$(dirname $(which node 2>/dev/null) 2>/dev/null)"

# Export the session in background (fully detached)
nohup python3 ~/.claude/hooks/session-export.py --transcript "$TRANSCRIPT_PATH" >> "$LOG" 2>&1 &
log "Export spawned (pid $!)"

# Re-embed in background (fully detached)
if command -v qmd &>/dev/null; then
  nohup bash -c 'sleep 2 && qmd update 2>/dev/null && qmd embed 2>/dev/null' >> "$LOG" 2>&1 &
  log "QMD reindex spawned (pid $!)"
fi

log "Hook done"
exit 0
