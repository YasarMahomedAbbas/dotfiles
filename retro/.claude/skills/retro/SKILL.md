---
name: retro
description: Run a retrospective over recent Claude Code sessions (all projects, herd ticket runs included) and turn what went wrong into fixes to the agents' environment — steering files, skills, review checklists, checks, herd. User-invoked only, e.g. "/retro", "/retro last day", "/retro travelsmart last week", "/retro since 2026-11-01".
disable-model-invocation: true
---

# retro

You look back over a window of Claude Code sessions and find what in the agents' **environment** made them slow,
wrong, or needy — then the user decides what to change. You are not grading the code they wrote; you are
improving the files, skills, checks and tools that the next session starts with.

Do the analysis read-only. Nothing is edited until the user decides, in step 6.

## 0. Arguments

`/retro [window] [project]`, both optional, any order, plain words:

- **window**: `since last retro` (default), `last day` (`1d`), `last week` (`7d`), `6h`, or a date `2026-11-01`.
- **project**: narrows to units whose name contains it (`travelsmart`, `personal-assistant`, `vault`…).

## 1. Anchor and follow-up

Retro notes live in `~/projects/vault/My-Vault/20-projects/agent-retros/`, one per run, named
`YYYY-MM-DD-retro.md` (`-2`, `-3` for a second run that day). The newest one's **Window:** line ends with the
time it covered up to; for "since last retro" that is your `--since`. No retro yet → default to `7d` and say so.

Read the newest note's **Decisions** table. For each row not already `done`/`dropped`, check whether it
happened (look at the file it targeted, the herd, the ticket) and carry the result into today's note under
**Follow-up**. A decision that keeps not happening is itself a finding.

## 2. Digest

```bash
D=~/.claude/skills/retro/scripts/digest.py
$D --since <ISO or span> [--project <name>] --top 8 --json <scratchpad>/digest.json > <scratchpad>/digest.md
```

Read `digest.md`. It groups sessions into **units** — a herd ticket run (`travelsmart#2158`, the worktree's
sessions: pipeline stages, reviews, resumes) or a project — ranked by a friction score, and lists per session:
your prompts flagged as `maybe correction`, interrupts, denied tool calls, tool errors by kind, commands repeated
3+ times, outputs over 15k chars, prompts the user answered (AskUserQuestion answers and permission prompts —
mostly the former: gates that needed the user), skills run, PRs, cost. Sessions that ran
`/retro` are excluded. The score only orders the reading; it is not a verdict.

Before any deep read, scan across units for **patterns**: the same error kind, denial or big-output command in
several sessions is one systemic finding you can already name (e.g. `Edit: File has not been read yet` ×26 across
the week). Many patterns need no deep read at all.

## 3. Deep reads

Pick about 5 units (more if the user asked): the highest scores, weighted toward **human** friction —
corrections, interrupts, denials, repeated permission prompts — over raw error counts, and toward herd ticket runs
that needed the user when they should have run alone. Skip units whose signals the patterns already explain.

Give each to a subagent (in parallel, one message). Brief each with: the unit, its digest block, the categories
in step 4, and this:

> Read the sessions with `~/.claude/skills/retro/scripts/digest.py --read <session-id>` (compact transcript,
> subagents included; `--max-chars` to see more). Read its output directly, or save it under a name that
> includes the session id: other deep reads run in parallel in the same scratchpad. Find the moments where the agent lost time, got it wrong, or
> needed the user — and the cause in its environment: a missing pointer, a misleading instruction, a skill step
> that didn't fit, a check that didn't exist, a tool that dumped too much. Before proposing a fix, open the file you
> would change and check the fix isn't already there. Don't edit anything. Return at most 6 findings, each:
> category · what happened (session id + time) · cause · proposed fix (exact file, and the wording or change) ·
> severity guess. Say "nothing worth fixing" if that's the truth.

## 4. Categories

Where each kind of fix goes in this setup:

| Category | Look for | Fix goes to |
|---|---|---|
| **Repeated corrections** | The user told agents the same thing twice, in one session or across sessions. | User-level: memory (`~/.claude/projects/<dir>/memory/`) or `~/.claude/CLAUDE.md`. Repo-level: the repo's `CLAUDE.md`, as a pointer if it's long. |
| **Pipeline handoffs** | A stage ran in the wrong order, re-did another stage's work, looped review↔fix, stalled on a gate ("needs you") it could have passed, or the next stage lacked something the previous should have left. | The stage's skill. travel-smart: `Frontend/.claude/skills/frontend-*`. Other repos: their installed copy in `.claude/skills/` **and** the template in `~/projects/personal/skills/` (fix both, or say which). |
| **Review gaps** | A mistake that passed review and was caught later (by the user, a later stage, CI). | Mechanical (a pattern, a banned API, a file location) → a check (next row). Judgement → the reviewer: travel-smart `Docs/Frontend/guardrails/` + the `frontend-review` checklist; elsewhere `review-implementation`. Rules belong in review, not in the implementer's context. |
| **Automated checks** | An error a lint, typecheck, test, hook or CI job could have caught. | First read what exists (`package.json` scripts, `.husky/`, `.github/workflows/`, e.g. travel-smart's `frontend-pr.yml`, `context-budget.yml`): a check that exists but isn't wired or run is the finding. No guardrail at all is a finding. |
| **Navigation** | Long search chains before finding a file or fact; hidden dependencies between files. | A one-line pointer in the nearest `CLAUDE.md` or the skill that needed it. |
| **Steering bloat & no-ops** | Steering files the agent ignored, contradicted, or didn't need; very long `CLAUDE.md`s (travel-smart `Frontend/CLAUDE.md` is ~750 lines). | Delete the no-op, move rules to review/checks, leave pointers. |
| **Tool economy** | Big outputs (whole files `cat`ed, unbounded `gh`/`git diff`), retry loops, the same lookup in every session, avoidable tool errors, permission prompts on safe commands. | The skill or `CLAUDE.md` that causes it; a script in place of a repeated chain; `fewer-permission-prompts` / settings allowlist for safe commands. |
| **Information access** | The agent needed something it couldn't see (logs, a service's state, a doc that isn't linked). | Tee the logs somewhere known, a read-only CLI, a doc pointer. |
| **herd / infra** | Worktree, seeding, setup, tab/label or herdr friction in ticket runs. | `~/projects/personal/dotfiles-herd` (herd, recipes, `projects.json`) — note the live symlinks follow that checkout. |

## 5. Write the note

Merge the subagents' findings with your patterns; dedupe; drop anything you can't point to a session for.
Severity:

- **high** — recurred across units or sessions, or cost real user time or money, or let a wrong result through.
- **medium** — one clear instance with an obvious cheap fix.
- **low** — polish.

Write `20-projects/agent-retros/YYYY-MM-DD-retro.md` (vault rules: kebab-case, one paragraph per line, no
hard wraps, frontmatter exactly as below, no other keys):

```markdown
---
type: note
status: active
domain: personal
created: YYYY-MM-DD
tags: [ai]
---

# Retro YYYY-MM-DD

**Window:** 2026-11-02T09:39 → 2026-11-09T09:39 · **Scope:** all (or the project) · **Sessions:** 68 in 29 units, 5 read in full · **Cost in window:** $543

## Follow-up
(last retro's open decisions, each: done / not done / partly, one line why)

## Findings
### <target: travel-smart | global ~/.claude | skills template | herd | personal-assistant …>
- **[high] <short title>** (<category>) — what happened, with session ids · cause · proposed fix: <file> — <change>.

## Decisions
| # | Finding | Decision | Where | Status |
|---|---|---|---|---|
```

Group findings by target, high first within each. Keep each finding to a few lines; the evidence is the session
id, not a quote. Add the note to the list in `agent-retros.md`.

## 6. Decide

Present the findings briefly (counts by severity and target, then the high ones), then go through them with
`AskUserQuestion`, 2–3 findings per round, highest first, each with a recommended option:

- **Fix now** — small, local, clear: you make the change in this session after the walk-through.
- **Herd it** — real work in a repo: start it with the `herd` skill (one herd per repo, with the finding as the task).
- **Ticket** — belongs in that project's tracker; draft it and confirm before creating.
- **Drop** — not worth it, or wrong.

Record each answer in the Decisions table as you go. Then do the "fix now" ones (each its own edit; commit only
where the user's normal flow commits), start the herds, draft the tickets. Set each row's Status (`done`,
`herded`, `ticketed`, `open`, `dropped`); when nothing is `open`, set the note's `status: done`.

End with a few lines: what changed, what's running, what's left open — and the note's path.

## Principles

- **Fix the environment, not the session.** "The agent should have been more careful" is not a finding;
  "nothing told it X lives in Y" is.
- **Prefer, in order:** a check that makes the mistake impossible → a reviewer rule → a pointer → an instruction.
  Implementing agents carry the most context; reviewers get a diff and the least — put standards on the reviewer.
- **Removing beats adding.** A deleted no-op instruction is a win; every line added to a `CLAUDE.md` is paid by
  every session in that repo.
- **Evidence or it didn't happen.** Every finding names a session. No session, no finding.
