#!/usr/bin/env python3
"""
session-export.py - Convert Claude Code JSONL sessions to searchable markdown.

Usage:
  python3 session-export.py --transcript /path/to/session.jsonl
  python3 session-export.py --backfill /path/to/sessions/dir/
"""

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path

VAULT_DIR = Path.home() / ".claude" / "vault" / "sessions"
INDEX_FILE = VAULT_DIR / ".index"
MAX_BLOCKS = 200
MAX_FILE_SIZE = 50 * 1024 * 1024
MAX_TEXT_LEN = 2000


def load_index():
    if INDEX_FILE.exists():
        return set(INDEX_FILE.read_text().strip().splitlines())
    return set()


def save_to_index(session_id):
    with open(INDEX_FILE, "a") as f:
        f.write(session_id + "\n")


def extract_file_paths(content_blocks):
    paths = set()
    for block in content_blocks:
        if block.get("type") != "tool_use":
            continue
        inp = block.get("input", {})
        for key in ("file_path", "path", "filePath"):
            if key in inp and isinstance(inp[key], str):
                p = inp[key]
                if "/Desktop/" in p:
                    paths.add(p.split("/Desktop/")[-1].split("/", 1)[-1] if "/" in p.split("/Desktop/")[-1] else p)
                elif not p.startswith("/"):
                    paths.add(p)
    return paths


def extract_user_text(message):
    content = message.get("message", {}).get("content", "")
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(block["text"])
            elif isinstance(block, str):
                parts.append(block)
        return "\n".join(parts).strip()
    return ""


def extract_assistant_text(message):
    content = message.get("message", {}).get("content", [])
    if isinstance(content, str):
        return content.strip()
    if not isinstance(content, list):
        return ""
    parts = []
    for block in content:
        if isinstance(block, dict) and block.get("type") == "text":
            text = block.get("text", "").strip()
            if text:
                if len(text) > MAX_TEXT_LEN:
                    text = text[:MAX_TEXT_LEN] + "\n\n[truncated]"
                parts.append(text)
    return "\n\n".join(parts)


def export_session(jsonl_path):
    jsonl_path = Path(jsonl_path)
    if not jsonl_path.exists():
        return None

    session_id = jsonl_path.stem
    index = load_index()
    if session_id in index:
        return None

    messages = []
    metadata = {}
    files_touched = set()
    large_file = jsonl_path.stat().st_size > MAX_FILE_SIZE
    block_count = 0

    with open(jsonl_path, "r", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            msg_type = obj.get("type")

            if msg_type == "user" and not metadata:
                metadata = {
                    "session_id": obj.get("sessionId", session_id),
                    "branch": obj.get("gitBranch", "unknown"),
                    "slug": obj.get("slug", ""),
                    "cwd": obj.get("cwd", ""),
                }

            if msg_type == "user":
                text = extract_user_text(obj)
                if text and not text.startswith("<"):
                    messages.append(("user", text))
                    block_count += 1

            elif msg_type == "assistant":
                text = extract_assistant_text(obj)
                content = obj.get("message", {}).get("content", [])
                if isinstance(content, list):
                    files_touched.update(extract_file_paths(content))
                if text:
                    messages.append(("assistant", text))
                    block_count += 1

            if large_file and block_count >= MAX_BLOCKS:
                messages.append(("system", f"[Session truncated at {MAX_BLOCKS} blocks due to size]"))
                break

    user_count = sum(1 for role, _ in messages if role == "user")
    if user_count < 2:
        save_to_index(session_id)
        return None

    mtime = jsonl_path.stat().st_mtime
    date_str = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d")

    topics = []
    for role, text in messages:
        if role == "user" and len(topics) < 3:
            topic = text[:100].replace("\n", " ").strip()
            if topic:
                topics.append(topic)

    fm_lines = [
        "---",
        f"session_id: {metadata.get('session_id', session_id)}",
        f"date: {date_str}",
        f"branch: {metadata.get('branch', 'unknown')}",
        f"slug: {metadata.get('slug', '')}",
    ]
    if files_touched:
        fm_lines.append("files_touched:")
        for fp in sorted(files_touched)[:20]:
            fm_lines.append(f"  - {fp}")
    if topics:
        fm_lines.append("topics:")
        for t in topics:
            fm_lines.append(f'  - "{t}"')
    fm_lines.append("---")

    body_lines = [f"\n# Session: {date_str} ({session_id[:8]})\n"]
    for role, text in messages:
        if role == "user":
            body_lines.append(f"## User\n{text}\n")
        elif role == "assistant":
            body_lines.append(f"## Assistant\n{text}\n")
        elif role == "system":
            body_lines.append(f"*{text}*\n")

    output_path = VAULT_DIR / f"{date_str}_{session_id[:8]}.md"
    output_path.write_text("\n".join(fm_lines) + "\n" + "\n".join(body_lines))
    save_to_index(session_id)
    return output_path


def backfill(sessions_dir):
    sessions_dir = Path(sessions_dir)
    exported = 0
    skipped = 0
    for jsonl_file in sorted(sessions_dir.glob("*.jsonl")):
        result = export_session(jsonl_file)
        if result:
            exported += 1
            print(f"  Exported: {result.name}")
        else:
            skipped += 1
    print(f"\nDone: {exported} exported, {skipped} skipped")


def main():
    parser = argparse.ArgumentParser(description="Export Claude Code sessions to markdown")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--transcript", help="Path to a single JSONL session file")
    group.add_argument("--backfill", help="Path to directory containing JSONL sessions")
    args = parser.parse_args()

    VAULT_DIR.mkdir(parents=True, exist_ok=True)

    if args.transcript:
        result = export_session(args.transcript)
        if result:
            print(f"Exported: {result}")
        else:
            print("Skipped (already exported or trivial)")
    else:
        backfill(args.backfill)


if __name__ == "__main__":
    main()
