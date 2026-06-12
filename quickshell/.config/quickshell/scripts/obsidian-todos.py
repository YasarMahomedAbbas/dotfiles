#!/usr/bin/env python3
"""Emit the next-N incomplete Obsidian tasks by due date as JSON.

Scans the vault for Tasks-plugin checkboxes ("- [ ] ... 📅 YYYY-MM-DD"),
keeps the ones that carry a date, sorts by that date ascending (overdue
first), and prints the top N as JSON for the quickshell dashboard.
"""
import json
import os
import re
import sys
from datetime import date

VAULT = os.environ.get(
    "OBSIDIAN_VAULT", "/home/dracul/projects/vault/My-Vault"
)
LIMIT = int(os.environ.get("OBSIDIAN_TODO_LIMIT", "3"))

# Mirror the home.md Tasks filter ("path does not include 90-meta/templates").
# .trash/.obsidian are added because the Tasks plugin never indexes them either;
# 50-archive is intentionally NOT excluded — the home page lists those too.
SKIP_DIRS = {".trash", ".obsidian", "90-meta/templates"}

TASK_RE = re.compile(r"^\s*- \[ \]\s+(.*\S)\s*$")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
DUE_RE = re.compile(r"📅\s*(\d{4}-\d{2}-\d{2})")
SCHED_RE = re.compile(r"⏳\s*(\d{4}-\d{2}-\d{2})")
# Tasks-plugin metadata to scrub from the visible text.
META_RE = re.compile(r"\s*[📅⏳➕✅🛫❌🔁]\s*\d{4}-\d{2}-\d{2}")
PRIO_RE = re.compile(r"[🔺⏫🔼🔽⏬]")
LINK_RE = re.compile(r"\[\[([^\]|]*\|)?([^\]]+)\]\]")


def parse_date(s):
    try:
        y, m, d = (int(x) for x in s.split("-"))
        return date(y, m, d)
    except (ValueError, TypeError):
        return None


def clean(text):
    text = META_RE.sub("", text)
    text = PRIO_RE.sub("", text)
    text = LINK_RE.sub(lambda m: m.group(2), text)  # [[a|b]] -> b
    text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)   # **bold** -> bold
    text = re.sub(r"#(\S+)", "", text)               # drop #tags
    return re.sub(r"\s+", " ", text).strip()


def skip(path):
    rel = os.path.relpath(path, VAULT)
    return any(rel == d or rel.startswith(d + os.sep) for d in SKIP_DIRS)


def rel_label(due, today):
    delta = (due - today).days
    if delta < -1:
        return f"{-delta}d ago"
    if delta == -1:
        return "yesterday"
    if delta == 0:
        return "today"
    if delta == 1:
        return "tomorrow"
    return f"in {delta}d"


def main():
    today = date.today()
    tasks = []
    for root, dirs, files in os.walk(VAULT):
        dirs[:] = [d for d in dirs if not skip(os.path.join(root, d))]
        for name in files:
            if not name.endswith(".md"):
                continue
            path = os.path.join(root, name)
            if skip(path):
                continue
            try:
                with open(path, encoding="utf-8") as fh:
                    lines = fh.readlines()
            except OSError:
                continue
            in_fence = False
            for line in lines:
                if FENCE_RE.match(line):
                    in_fence = not in_fence
                    continue
                if in_fence:
                    continue
                m = TASK_RE.match(line)
                if not m:
                    continue
                raw = m.group(1)
                dm = DUE_RE.search(raw) or SCHED_RE.search(raw)
                if not dm:
                    continue
                due = parse_date(dm.group(1))
                if due is None:
                    continue
                text = clean(raw)
                if not text:
                    continue
                tasks.append((due, text))

    tasks.sort(key=lambda t: t[0])
    out = [
        {
            "text": text,
            "due": due.isoformat(),
            "rel": rel_label(due, today),
            "overdue": due < today,
        }
        for due, text in tasks[:LIMIT]
    ]
    json.dump(out, sys.stdout)


if __name__ == "__main__":
    main()
