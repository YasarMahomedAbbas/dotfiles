#!/usr/bin/env python3
"""retro digest: turn Claude Code session logs into a short list of signals.

  digest.py [--since WHEN] [--until WHEN] [--project SUBSTR] [--top N] [--json FILE]
      One block per unit (a herd ticket, or a project), sessions ranked by friction.
  digest.py --read SESSION_ID [--max-chars N]
      A compact transcript of one session (and its subagents) for a deep read.

WHEN is an ISO date/time (2026-11-08, 2026-11-08T14:00) or a span back from now (6h, 1d, 7d).
Logs: ~/.claude/projects/<dir>/<session>.jsonl, subagents in <session>/subagents/*.jsonl.
Sessions that ran /retro are left out.
"""
import argparse, json, os, re, sys, glob
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

LOGS = os.path.expanduser("~/.claude/projects")
HERD_PROJECTS = os.path.expanduser("~/.config/herd/projects.json")
HOME = os.path.expanduser("~")

# Words that usually mean the human is correcting or redirecting the agent.
CORRECTION = re.compile(
    r"\b(no[,.!]|nope|don'?t|do not|stop|wrong|instead|actually|i said|i told you|again|"
    r"why did you|why are you|not what i|that'?s not|undo|revert|you forgot|you missed|"
    r"never|should have|shouldn'?t)\b", re.I)
DENIED = ("The user doesn't want to proceed", "Permission for this action was denied",
          "Permission for this command was denied", "was blocked by", "denied by")


def parse_when(s, now):
    if not s:
        return None
    m = re.fullmatch(r"(\d+)([hdw])", s)
    if m:
        n, u = int(m[1]), m[2]
        return now - timedelta(hours=n) if u == "h" else now - timedelta(days=n * (7 if u == "w" else 1))
    dt = datetime.fromisoformat(s)
    return dt if dt.tzinfo else dt.astimezone()


def ts(d):
    t = d.get("timestamp")
    if not t:
        return None
    try:
        return datetime.fromisoformat(t.replace("Z", "+00:00"))
    except ValueError:
        return None


# ---------------------------------------------------------------- units (herd tickets / projects)
def load_units():
    """[(regex, label_fmt)] from herd's projects.json: worktree paths -> 'project#n', roots -> 'project'."""
    rules = []
    try:
        projects = json.load(open(HERD_PROJECTS))
    except (OSError, ValueError):
        projects = {}
    for name, p in projects.items():
        root = os.path.expanduser(p.get("root", ""))
        if not root:
            continue
        wt = p.get("worktree")
        if wt:
            wt = os.path.expanduser(wt)
            path = os.path.normpath(wt if os.path.isabs(wt) else os.path.join(root, wt))
            rx = re.escape(path).replace(r"\{n\}", r"(?P<id>\d+)").replace(r"\{ref\}", r"(?P<id>[^/]+)") \
                .replace(r"\{REF\}", r"(?P<id>[^/]+)")
            rules.append((re.compile("^" + rx + "(/|$)"), name + "#{id}"))
        rules.append((re.compile("^" + re.escape(os.path.normpath(root)) + "(/|$)"), name))
    return rules


def unit_of(cwd, rules):
    if not cwd:
        return "?"
    for rx, fmt in rules:
        m = rx.match(cwd)
        if m:
            return fmt.format(**m.groupdict())
    rel = cwd[len(HOME) + 1:] if cwd.startswith(HOME + "/") else cwd
    parts = rel.split("/")
    # ~/projects/<group>/<repo> or ~/projects/<repo>
    if parts[0] == "projects" and len(parts) >= 3 and parts[1] in ("personal", "org", "social"):
        if parts[1] == "org" and len(parts) >= 4:
            return parts[3]
        return parts[2]
    if parts[0] == "projects" and len(parts) >= 2:
        return parts[1]
    return "~/" + "/".join(parts[:2]) if rel != cwd else cwd


# ---------------------------------------------------------------- one session
def text_of(content):
    if isinstance(content, str):
        return content
    out = []
    for b in content or []:
        if isinstance(b, dict):
            if b.get("type") == "text":
                out.append(b.get("text", ""))
            elif b.get("type") == "tool_result":
                out.append(text_of(b.get("content")))
    return "\n".join(out)


def is_human(d):
    o = (d.get("origin") or {}).get("kind")
    if o == "human":
        return True
    if o is None and not d.get("isMeta") and not d.get("toolUseResult") and not d.get("sourceToolUseID"):
        c = d.get("message", {}).get("content")
        if isinstance(c, str):
            return not c.startswith("<") and not c.startswith("[Request interrupted")
        if isinstance(c, list):
            return all(isinstance(b, dict) and b.get("type") == "text" for b in c) and bool(c) \
                and not text_of(c).startswith(("<", "[Request interrupted", "Caveat:"))
    return False


def tool_brief(name, inp):
    inp = inp or {}
    for k in ("command", "file_path", "pattern", "query", "skill", "url", "description", "prompt"):
        if k in inp:
            v = str(inp[k]).replace("\n", " ")
            return f"{name}({v[:140]})"
    return f"{name}({json.dumps(inp)[:120]})"


def scan(path, since, until, rules):
    s = dict(path=path, id=os.path.basename(path)[:-6], title="", cwd="", branch="", start=None, end=None,
             human=[], corrections=[], interrupts=0, denied=[], errors=Counter(), err_samples=[],
             tools=Counter(), skills=Counter(), big=[], cmds=Counter(), tokens=0, out_tokens=0,
             cost=None, prs=set(), subagents=0, peer_msgs=0, in_window=False, is_retro=False,
             permission_prompts=0)
    uses = {}
    try:
        f = open(path, errors="replace")
    except OSError:
        return None
    for line in f:
        try:
            d = json.loads(line)
        except ValueError:
            continue
        t = d.get("type")
        if t == "ai-title":
            s["title"] = d.get("aiTitle", "")
        elif t == "pr-link":
            s["prs"].add(d.get("prUrl", ""))
        elif t == "cost-state":
            s["cost"] = d.get("totalCostUSD")
        if t not in ("user", "assistant"):
            continue
        when = ts(d)
        if when:
            s["start"] = s["start"] or when
            s["end"] = when
            if (not since or when >= since) and (not until or when <= until):
                s["in_window"] = True
        s["cwd"] = s["cwd"] or d.get("cwd", "")
        s["branch"] = s["branch"] or d.get("gitBranch", "")
        msg = d.get("message", {})
        if t == "assistant":
            u = msg.get("usage") or {}
            s["tokens"] += u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) \
                + u.get("cache_creation_input_tokens", 0)
            s["out_tokens"] += u.get("output_tokens", 0)
            for b in msg.get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    name, inp = b.get("name", "?"), b.get("input") or {}
                    s["tools"][name] += 1
                    uses[b.get("id")] = (name, inp)
                    if name == "Skill":
                        s["skills"][inp.get("skill", "?")] += 1
                        if inp.get("skill") == "retro":
                            s["is_retro"] = True
                    if name in ("Agent", "Task"):
                        s["subagents"] += 1
                    if name == "Bash":
                        s["cmds"][re.sub(r"\s+", " ", inp.get("command", ""))[:200]] += 1
            continue
        # user entries
        pd = d.get("permissionDecision") or {}
        if pd.get("source", "").startswith("user"):
            s["permission_prompts"] += 1
        if (d.get("origin") or {}).get("kind") == "peer":
            s["peer_msgs"] += 1
        c = msg.get("content")
        raw = text_of(c) if not isinstance(c, str) else c
        if "<command-name>/retro" in raw:
            s["is_retro"] = True
        for m in re.finditer(r"<command-name>/?([\w:-]+)</command-name>", raw):
            s["skills"]["/" + m[1]] += 1
        if "[Request interrupted" in raw and not d.get("toolUseResult"):
            s["interrupts"] += 1
        if is_human(d):
            s["human"].append(raw.strip())
            if len(s["human"]) > 1 and CORRECTION.search(raw[:600]):
                s["corrections"].append(raw.strip())
        if isinstance(c, list):
            for b in c:
                if not (isinstance(b, dict) and b.get("type") == "tool_result"):
                    continue
                body = text_of(b.get("content"))
                name, inp = uses.get(b.get("tool_use_id"), ("?", {}))
                if len(body) > 15000:
                    s["big"].append((len(body), tool_brief(name, inp)))
                if any(x in body[:300] for x in DENIED):
                    s["denied"].append(tool_brief(name, inp) + " -> " + body[:160].replace("\n", " "))
                elif b.get("is_error"):
                    key = re.sub(r"\d+", "N", re.sub(r"<[^>]+>", "", body)[:60]).strip()
                    s["errors"][f"{name}: {key}"] += 1
                    if len(s["err_samples"]) < 6:
                        s["err_samples"].append(tool_brief(name, inp) + " -> " + body[:200].replace("\n", " "))
    f.close()
    if not s["start"]:
        return None
    sub_dir = path[:-6] + "/subagents"
    s["sub_files"] = sorted(glob.glob(sub_dir + "/*.jsonl"))
    for sf in s["sub_files"]:
        sub = scan(sf, None, None, rules)
        if sub:
            s["tokens"] += sub["tokens"]
            s["out_tokens"] += sub["out_tokens"]
            s["errors"] += Counter({"(sub) " + k: v for k, v in sub["errors"].items()})
            s["denied"] += ["(sub) " + x for x in sub["denied"]]
            s["big"] += [(n, "(sub) " + b) for n, b in sub["big"]]
    s["unit"] = unit_of(s["cwd"], rules)
    s["loops"] = [(n, c) for c, n in s["cmds"].items() if n >= 3 and c]
    s["score"] = (3 * s["interrupts"] + 3 * len(s["corrections"]) + 2 * len(s["denied"])
                  + sum(s["errors"].values()) + 2 * len(s["loops"]) + len(s["big"])
                  + 2 * s["permission_prompts"])
    return s


# ---------------------------------------------------------------- output
def fmt_dur(s):
    m = int((s["end"] - s["start"]).total_seconds() // 60)
    return f"{m // 60}h{m % 60:02d}m" if m >= 60 else f"{m}m"


def clip(x, n):
    x = re.sub(r"\s+", " ", x)
    return x if len(x) <= n else x[:n] + "…"


def digest(args):
    now = datetime.now(timezone.utc).astimezone()
    since, until = parse_when(args.since, now), parse_when(args.until, now)
    rules = load_units()
    sessions = []
    for path in glob.glob(LOGS + "/*/*.jsonl"):
        if since and datetime.fromtimestamp(os.path.getmtime(path)).astimezone() < since:
            continue
        s = scan(path, since, until, rules)
        if not s or not s["in_window"] or s["is_retro"]:
            continue
        if args.project and args.project.lower() not in s["unit"].lower():
            continue
        sessions.append(s)

    units = defaultdict(list)
    for s in sessions:
        units[s["unit"]].append(s)
    ranked = sorted(units.items(), key=lambda kv: -sum(x["score"] for x in kv[1]))

    win = f"{since:%Y-%m-%d %H:%M} → {(until or now):%Y-%m-%d %H:%M}" if since else "all time"
    print(f"# retro digest  {win}")
    print(f"{len(sessions)} sessions in {len(units)} units, "
          f"{sum(len(s['human']) for s in sessions)} human prompts, "
          f"{sum(s['interrupts'] for s in sessions)} interrupts, "
          f"{sum(len(s['denied']) for s in sessions)} denials, "
          f"{sum(sum(s['errors'].values()) for s in sessions)} tool errors, "
          f"${sum(s['cost'] or 0 for s in sessions):.0f} spent\n")

    print("## Units by friction")
    for unit, ss in ranked:
        sc = sum(x["score"] for x in ss)
        print(f"- {unit}: score {sc}, {len(ss)} sessions, "
              f"{sum(len(x['human']) for x in ss)} prompts, ${sum(x['cost'] or 0 for x in ss):.0f}")
    print()

    for unit, ss in ranked[:args.top]:
        print(f"## {unit}")
        for s in sorted(ss, key=lambda x: x["start"]):
            skills = ", ".join(f"{k}×{v}" if v > 1 else k for k, v in s["skills"].most_common(6))
            print(f"### {s['id'][:8]}  {s['start']:%m-%d %H:%M} {fmt_dur(s)}  score {s['score']}  "
                  f"{s['title'] or '(untitled)'}")
            br = f"branch {s['branch']} · " if s["branch"] not in ("", "HEAD") else ""
            print(f"  {br}{len(s['human'])} prompts · {s['out_tokens'] / 1e3:.0f}k out tokens"
                  + (f" · ${s['cost']:.2f}" if s["cost"] else "")
                  + (f" · {s['subagents']} subagents" if s["subagents"] else "")
                  + (f" · {s['peer_msgs']} peer msgs" if s["peer_msgs"] else ""))
            if skills:
                print(f"  skills: {skills}")
            if s["prs"]:
                print(f"  PRs: {' '.join(sorted(s['prs']))}")
            if s["human"]:
                print(f"  first prompt: {clip(s['human'][0], 160)}")
            for c in s["corrections"][:5]:
                print(f"  maybe correction: {clip(c, 220)}")
            if s["interrupts"]:
                print(f"  interrupts: {s['interrupts']}")
            if s["permission_prompts"]:
                print(f"  prompts the user answered (questions or permissions): {s['permission_prompts']}")
            for x in s["denied"][:4]:
                print(f"  denied: {clip(x, 220)}")
            for k, v in s["errors"].most_common(5):
                print(f"  error ×{v}: {clip(k, 120)}")
            for n, c in sorted(s["loops"], reverse=True)[:3]:
                print(f"  repeated ×{n}: {clip(c, 140)}")
            for n, b in sorted(s["big"], reverse=True)[:3]:
                print(f"  big output {n // 1000}k chars: {clip(b, 140)}")
        print()

    if args.json:
        out = [{k: (v if not isinstance(v, (set, Counter, datetime)) else
                    (sorted(v) if isinstance(v, set) else dict(v) if isinstance(v, Counter) else v.isoformat()))
                for k, v in s.items() if k not in ("cmds",)} for s in sessions]
        json.dump(out, open(args.json, "w"), indent=1, default=str)
        print(f"(full data: {args.json})")


# ---------------------------------------------------------------- --read
def read(args):
    hits = glob.glob(f"{LOGS}/*/{args.read}*.jsonl")
    if not hits:
        sys.exit(f"no session {args.read}")
    path = hits[0]
    budget = [args.max_chars]

    def emit(x):
        if budget[0] <= 0:
            return
        budget[0] -= len(x) + 1
        print(x)

    def render(p, indent=""):
        uses = {}
        for line in open(p, errors="replace"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            t = d.get("type")
            if t not in ("user", "assistant"):
                continue
            when = ts(d)
            hm = f"{when.astimezone():%H:%M}" if when else "--:--"
            c = d.get("message", {}).get("content")
            if t == "assistant":
                for b in c or []:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "text" and b.get("text", "").strip():
                        emit(f"{indent}{hm} AGENT: {clip(b['text'], 600)}")
                    elif b.get("type") == "tool_use":
                        uses[b.get("id")] = b.get("name")
                        emit(f"{indent}{hm}   → {tool_brief(b.get('name'), b.get('input'))}")
                continue
            if is_human(d):
                emit(f"{indent}{hm} USER: {clip(text_of(c) if not isinstance(c, str) else c, 1500)}")
                continue
            o = (d.get("origin") or {}).get("kind")
            if o in ("peer", "coordinator", "task-notification"):
                emit(f"{indent}{hm} [{o}] {clip(text_of(c) if not isinstance(c, str) else c, 300)}")
                continue
            if isinstance(c, str) and "[Request interrupted" in c:
                emit(f"{indent}{hm} USER INTERRUPTED")
            if isinstance(c, list):
                for b in c:
                    if isinstance(b, dict) and b.get("type") == "text" and "[Request interrupted" in b.get("text", ""):
                        emit(f"{indent}{hm} USER INTERRUPTED")
                    if isinstance(b, dict) and b.get("type") == "tool_result":
                        body = text_of(b.get("content"))
                        bad = b.get("is_error") or any(x in body[:300] for x in DENIED)
                        if bad:
                            emit(f"{indent}      ✗ {clip(body, 400)}")
                        elif len(body) > 15000:
                            emit(f"{indent}      ({len(body) // 1000}k chars of output)")
        return uses

    print(f"# session {os.path.basename(path)[:-6]}\n")
    render(path)
    for sf in sorted(glob.glob(path[:-6] + "/subagents/*.jsonl")):
        meta = sf[:-6] + ".meta.json"
        desc = ""
        try:
            desc = json.load(open(meta)).get("description", "")
        except (OSError, ValueError):
            pass
        emit(f"\n## subagent {os.path.basename(sf)[6:14]} {desc}")
        render(sf, "  ")
    if budget[0] <= 0:
        print(f"\n(cut at {args.max_chars} chars; raise --max-chars to see more)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--since")
    ap.add_argument("--until")
    ap.add_argument("--project")
    ap.add_argument("--top", type=int, default=8, help="units to show in detail (default 8)")
    ap.add_argument("--json")
    ap.add_argument("--read", metavar="SESSION_ID")
    ap.add_argument("--max-chars", type=int, default=60000)
    args = ap.parse_args()
    read(args) if args.read else digest(args)


if __name__ == "__main__":
    main()
