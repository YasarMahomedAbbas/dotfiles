// agent-board: writes this session's status to ~/.cache/claude-board/<key>.json
// for the agent board (docs/agent-board.md, section 1). Observe only: every
// hook passes its event on unchanged and swallows its own failures.
import type { EngineInterface, Register } from 'claude-code'
import {
  contentText,
  describeCall,
  firstLine,
  clip,
  isDesignType,
  median,
  normaliseCommand,
  parseDesignLines,
  parseTaskNotifications,
  prettyModel,
  summariseInput,
  artifactId,
} from './pure.ts'

type $ = EngineInterface
type BoardState = 'needs_you' | 'working' | 'background' | 'idle'
type Option = { key: string; label: string }
type Attention = {
  kind: 'permission' | 'question' | 'plan'
  title: string
  text: string
  options: Option[]
  since: number
  /** the main-loop call it belongs to: resolving that call clears it */
  callId?: string
}
type Agent = {
  id: string
  type: string
  description: string
  status: string
  started: number
  ended: number | null
  parent: string | null
  teammate?: boolean
  /** seen in `$.agent.list()` at least once */
  listed?: boolean
}
type Shell = { id: string; command: string; status: string; started: number; ended: number | null }
type Task = { id?: string; subject: string; status: string }
type Design = { url: string; title: string | null; issue: number | null; boards: number | null; at: number }
type Call = {
  id: string
  tool: string
  detail: string
  started: number
  typical_ms: number | null
  runs: number
  durKey?: string
  asked?: boolean
}

const HEARTBEAT_MS = 10_000
/** A Remote Control session id as Claude Code sets it (`session_…`); anything else is null. */
const REMOTE_ID = /^session_[A-Za-z0-9]{1,64}$/
const KEEP = 20
const DUR_RUNS = 20
const DUR_KEYS = 400
const RUNNING = new Set(['running', 'pending', 'waiting', 'needs_you'])
const PERMISSION_OPTIONS: Option[] = [
  { key: '1', label: 'Yes' },
  { key: '2', label: "Yes, don't ask again" },
  { key: '3', label: 'No' },
]
const PLAN_OPTIONS: Option[] = [
  { key: '1', label: 'Yes, auto-accept edits' },
  { key: '2', label: 'Yes, manually approve edits' },
  { key: '3', label: 'No, keep planning' },
]

// ---------------------------------------------------------------- identity
const id = {
  dir: '',
  key: '',
  pane: null as string | null,
  sessionId: '',
  pid: null as number | null,
  tmux: null as { session: string; pane: string; window: string } | null,
  tmuxId: null as string | null,
  cwd: '',
  branch: null as string | null,
  model: null as string | null,
  project: '',
}

// ---------------------------------------------------------------- session state
const S = {
  state: 'idle' as BoardState,
  since: 0,
  finished_at: null as number | null,
  inTurn: false,
  attention: null as Attention | null,
  calls: new Map<string, Call>(),
  agents: [] as Agent[],
  shells: [] as Shell[],
  tasks: [] as Task[],
  designs: [] as Design[],
}

let started = false
let ended = false
let tick = 0
let timer: { cancel: () => void } | null = null
let flushing: Promise<void> | null = null
let dirty = false
let tmuxState: string | null = null
let durations: Record<string, number[]> | null = null
let callSeq = 0
/** The Remote Control id, read once per heartbeat; null while not connected. */
let remote: string | null = null
let remoteMisses = 0

const resetSession = (): void => {
  S.state = 'idle'
  S.finished_at = null
  S.inTurn = false
  S.attention = null
  S.calls.clear()
  S.agents = []
  S.shells = []
  S.tasks = []
  S.designs = []
}

// ---------------------------------------------------------------- helpers
const now = async ($: $): Promise<number> => {
  try {
    return await $.clock.now()
  } catch {
    return Date.now()
  }
}

const run = async ($: $, argv: string[], cwd?: string): Promise<string | null> => {
  try {
    const r = await $.process.run(argv, { timeoutMs: 5000, ...(cwd ? { cwd } : {}) })
    return r.exitCode === 0 ? r.stdout : null
  } catch {
    return null
  }
}

const filePath = (): string => `${id.dir}/${id.key}.json`

const anyRunning = (): boolean =>
  S.agents.some(a => RUNNING.has(a.status)) || S.shells.some(s => s.status === 'running')

const derive = (): BoardState =>
  S.inTurn && S.attention ? 'needs_you' : S.inTurn ? 'working' : anyRunning() ? 'background' : 'idle'

const current = (): Call | null => {
  let last: Call | null = null
  for (const c of S.calls.values()) last = c
  return last
}

/** Re-derive the state, stamp `since`, and schedule a write. Never throws. */
const touch = async ($: $): Promise<void> => {
  try {
    const next = derive()
    if (next !== S.state) {
      const t = await now($)
      S.state = next
      S.since = t
      if (next === 'idle') S.finished_at = t
      void setTmuxState($)
    }
    if (!S.inTurn) S.attention = null
    void flush($)
  } catch {
    // observe only
  }
}

const setTmuxState = async ($: $): Promise<void> => {
  if (!id.tmuxId || ended || tmuxState === S.state) return
  tmuxState = S.state
  await run($, ['tmux', 'set-option', '-t', id.tmuxId, '@board_state', S.state])
}

const snapshot = (heartbeat: number): string => {
  const cur = current()
  const doc: Record<string, unknown> = {
    v: 1,
    session_id: id.sessionId,
    pid: id.pid,
    heartbeat,
    tmux: id.tmux,
    cwd: id.cwd,
    branch: id.branch,
    model: id.model,
    remote,
    state: S.state,
    since: S.since,
    finished_at: S.finished_at,
  }
  if (S.state === 'needs_you' && S.attention) {
    const { callId: _drop, ...attention } = S.attention
    doc.attention = attention
  }
  doc.current = cur
    ? { tool: cur.tool, detail: cur.detail, started: cur.started, typical_ms: cur.typical_ms, runs: cur.runs }
    : null
  doc.agents = S.agents.map(a => ({
    id: a.id,
    type: a.type,
    description: a.description,
    status: a.status,
    started: a.started,
    ended: a.ended,
    parent: a.parent,
  }))
  doc.shells = S.shells.map(s => ({ id: s.id, command: s.command, status: s.status, started: s.started, ended: s.ended }))
  doc.tasks = S.tasks.map(t => ({ subject: t.subject, status: t.status }))
  doc.designs = S.designs
  return `${JSON.stringify(doc, null, 2)}\n`
}

/** Writes the file atomically (`<key>.json.tmp`, then `mv`), coalescing bursts. */
const flush = ($: $): Promise<void> => {
  if (flushing) {
    dirty = true
    return flushing
  }
  flushing = (async () => {
    try {
      do {
        dirty = false
        if (!started || ended || !id.key || !id.dir) return
        const text = snapshot(await now($))
        const path = filePath()
        const tmp = `${path}.tmp`
        await $.fs.write(tmp, text)
        if (ended) return
        await $.process.run(['mv', '-f', tmp, path], { timeoutMs: 5000 })
      } while (dirty)
    } catch {
      // a missed write is made good by the next change or heartbeat
    }
  })().finally(() => {
    flushing = null
  })
  return flushing
}

const trim = <T extends { status: string }>(xs: T[], isLive: (x: T) => boolean): T[] => {
  if (xs.length <= KEEP) return xs
  const out: T[] = []
  let done = 0
  for (const x of xs) {
    if (isLive(x)) out.push(x)
    else if (out.length < KEEP && done < KEEP) {
      out.push(x)
      done++
    }
  }
  return out
}

const addAgent = (a: Agent): void => {
  const at = S.agents.findIndex(x => x.id === a.id)
  if (at >= 0) S.agents[at] = { ...S.agents[at], ...a }
  else S.agents.unshift(a)
  S.agents = trim(S.agents, x => RUNNING.has(x.status))
}

const endTask = (taskId: string, status: string, t: number): boolean => {
  let hit = false
  const word = /fail|error/i.test(status) ? 'failed' : /kill|stop|cancel/i.test(status) ? 'killed' : 'completed'
  for (const s of S.shells) {
    if (s.id === taskId && s.status === 'running') {
      s.status = word
      s.ended = t
      hit = true
    }
  }
  for (const a of S.agents) {
    if (a.id === taskId && RUNNING.has(a.status)) {
      a.status = word
      a.ended = t
      hit = true
    }
  }
  return hit
}

const addDesign = (d: Design): void => {
  const at = S.designs.findIndex(x => artifactId(x.url) === artifactId(d.url))
  if (at >= 0) {
    const old = S.designs[at] as Design
    S.designs.splice(at, 1)
    d = {
      url: d.url,
      title: d.title ?? old.title,
      issue: d.issue ?? old.issue,
      boards: d.boards ?? old.boards,
      at: d.at,
    }
  }
  S.designs.unshift(d)
  S.designs = S.designs.slice(0, KEEP)
}

const scanText = (text: string, t: number): boolean => {
  let changed = false
  for (const n of parseTaskNotifications(text)) changed = endTask(n.id, n.status, t) || changed
  for (const d of parseDesignLines(text)) {
    addDesign({ url: d.url, title: d.title, issue: d.issue, boards: d.boards, at: t })
    changed = true
  }
  return changed
}

// ---------------------------------------------------------------- durations ($.store)
const loadDurations = async ($: $): Promise<Record<string, number[]>> => {
  if (durations) return durations
  try {
    const v = await $.store.get('durations')
    durations = v && typeof v === 'object' ? (v as Record<string, number[]>) : {}
  } catch {
    durations = {}
  }
  return durations
}

const recordDuration = async ($: $, key: string, ms: number): Promise<void> => {
  const all = await loadDurations($)
  const runs = [...(all[key] ?? []), ms].slice(-DUR_RUNS)
  delete all[key]
  all[key] = runs
  const keys = Object.keys(all)
  for (const k of keys.slice(0, Math.max(0, keys.length - DUR_KEYS))) delete all[k]
  try {
    await $.store.set('durations', all)
  } catch {
    // history is best effort
  }
}

// ---------------------------------------------------------------- identity / polling
const refreshIdentity = async ($: $, full: boolean): Promise<void> => {
  const jobs: Promise<void>[] = []
  if (id.pane) {
    jobs.push(
      run($, ['tmux', 'display-message', '-p', '-t', id.pane, '#{session_name}\t#{window_index}\t#{session_id}']).then(
        out => {
          const [session, window, sid] = (out ?? '').replace(/\n$/, '').split('\t')
          if (session && sid) {
            id.tmux = { session, pane: id.pane as string, window: window ?? '' }
            if (id.tmuxId !== sid) tmuxState = null
            id.tmuxId = sid
          }
        },
      ),
    )
  }
  if (id.cwd) {
    jobs.push(
      run($, ['git', '-C', id.cwd, 'branch', '--show-current']).then(out => {
        id.branch = out?.trim() || null
      }),
    )
  }
  if (full && id.cwd) {
    jobs.push(
      run($, ['git', '-C', id.cwd, 'rev-parse', '--path-format=absolute', '--git-common-dir', '--show-prefix']).then(
        out => {
          const [common, prefix = ''] = (out ?? '').split('\n')
          const root = common ? common.replace(/\/\.git\/?$/, '') : id.cwd
          id.project = `${root}/${prefix.trim()}`.replace(/\/+$/, '')
        },
      ),
    )
    jobs.push(findPid($))
  }
  await Promise.all(jobs)
  if (!id.project) id.project = id.cwd
}

/**
 * The plugin API exposes no process id: the parent of a child we start is the
 * process that runs the hooks; walk up /proc to the `claude` process if that
 * is a helper, else keep the first parent.
 */
const findPid = async ($: $): Promise<void> => {
  const out = await run($, ['sh', '-c', 'echo $PPID'])
  let pid = Number(out?.trim())
  if (!Number.isInteger(pid) || pid <= 1) return
  id.pid = pid
  for (let i = 0; i < 3 && pid > 1; i++) {
    try {
      const comm = (await $.fs.read(`/proc/${pid}/comm`)) as string
      if (/claude/i.test(comm)) {
        id.pid = pid
        return
      }
      const stat = (await $.fs.read(`/proc/${pid}/stat`)) as string
      pid = Number(stat.slice(stat.lastIndexOf(')') + 2).split(' ')[1])
    } catch {
      return
    }
  }
}

/**
 * Claude Code sets CLAUDE_CODE_BRIDGE_SESSION_ID in hook and Bash subprocesses while
 * the session has a Remote Control connection, and removes it when that ends. Read the
 * mod's own env first, else a child's. A failed read keeps the last value for one more
 * heartbeat, then reports null.
 */
const readRemote = async ($: $): Promise<void> => {
  let raw: string | null | undefined = await $.env.get('CLAUDE_CODE_BRIDGE_SESSION_ID').catch(() => undefined)
  if (!raw) raw = await run($, ['sh', '-c', 'printf %s "$CLAUDE_CODE_BRIDGE_SESSION_ID"'])
  if (raw === null) {
    remoteMisses++
    if (remoteMisses > 1) remote = null
    return
  }
  remoteMisses = 0
  const value = raw.trim()
  remote = REMOTE_ID.test(value) ? value : null
}

const pollAgents = async ($: $): Promise<boolean> => {
  let list
  try {
    list = await $.agent.list()
  } catch {
    return false
  }
  const t = await now($)
  let changed = false
  const seen = new Set<string>()
  for (const info of list) {
    seen.add(info.id)
    const known = S.agents.find(a => a.id === info.id)
    if (!known) {
      addAgent({
        id: info.id,
        type: info.type,
        description: info.description,
        status: info.status,
        started: t,
        ended: RUNNING.has(info.status) ? null : t,
        parent: info.parentId ?? null,
        teammate: info.teammateId !== undefined,
        listed: true,
      })
      changed = true
      continue
    }
    known.listed = true
    const keepAsk = known.status === 'needs_you' && RUNNING.has(info.status)
    if (!keepAsk && known.status !== info.status) {
      known.status = info.status
      known.ended = RUNNING.has(info.status) || info.status === 'idle' ? null : (known.ended ?? t)
      changed = true
    }
  }
  for (const a of S.agents) {
    if (a.listed && !seen.has(a.id) && RUNNING.has(a.status)) {
      a.status = 'completed'
      a.ended = t
      changed = true
    }
  }
  return changed
}

const heartbeat = async ($: $): Promise<void> => {
  if (ended) return
  tick++
  try {
    await pollAgents($)
    await readRemote($)
    if (tick % 3 === 0) await refreshIdentity($, false)
    if (!id.sessionId) id.sessionId = await $.session.id()
  } catch {
    // keep beating
  }
  await touch($)
  void setTmuxState($)
  await flush($)
}

/** Picks up what an earlier load of this mod wrote for this session (a hot reload). */
const restore = async ($: $): Promise<void> => {
  try {
    const prev = JSON.parse((await $.fs.read(filePath())) as string) as Record<string, unknown>
    if (prev.session_id !== id.sessionId) return
    const arr = <T>(v: unknown): T[] => (Array.isArray(v) ? (v as T[]) : [])
    S.agents = arr<Agent>(prev.agents)
    S.shells = arr<Shell>(prev.shells)
    S.tasks = arr<Task>(prev.tasks)
    S.designs = arr<Design>(prev.designs)
    S.finished_at = typeof prev.finished_at === 'number' ? prev.finished_at : null
    if (prev.state === 'working' || prev.state === 'needs_you') S.inTurn = true
    if (prev.state === 'needs_you' && prev.attention && typeof prev.attention === 'object') {
      S.attention = prev.attention as Attention
    }
    S.state = derive()
    S.since = typeof prev.since === 'number' && prev.state === S.state ? prev.since : S.since
  } catch {
    // no earlier file
  }
}

const start = async ($: $, cwd: string): Promise<void> => {
  if (started) return
  const [pane, home, sessionId, model] = await Promise.all([
    $.env.get('TMUX_PANE').catch(() => undefined),
    $.env.get('HOME').catch(() => undefined),
    $.session.id().catch(() => ''),
    $.session.model().catch(() => ''),
  ])
  id.pane = pane || null
  id.sessionId = sessionId
  id.dir = `${home || '/tmp'}/.cache/claude-board`
  id.key = id.pane ? id.pane.replace(/^%/, '') : `nopane-${sessionId}`
  id.cwd = cwd
  id.model = model ? prettyModel(model) : null
  S.since = await now($)
  await Promise.all([refreshIdentity($, true), readRemote($)])
  await restore($)
  started = true
  ended = false
  timer?.cancel()
  timer = $.clock.every(HEARTBEAT_MS, () => {
    void heartbeat($)
  })
  void setTmuxState($)
  await flush($)
}

const finish = async ($: $, isClear: boolean): Promise<void> => {
  const path = filePath()
  if (!isClear) {
    ended = true
    timer?.cancel()
    timer = null
  }
  if (flushing) await flushing.catch(() => undefined)
  await run($, ['rm', '-f', path, `${path}.tmp`])
  if (!isClear && id.tmuxId) await run($, ['tmux', 'set-option', '-u', '-t', id.tmuxId, '@board_state'])
  if (isClear) {
    resetSession()
    S.since = await now($)
    tmuxState = null
  }
}

// ---------------------------------------------------------------- tool calls
const clearAttention = (): boolean => {
  if (!S.attention) return false
  S.attention = null
  return true
}

const asRecord = (v: unknown): Record<string, unknown> =>
  v && typeof v === 'object' ? (v as Record<string, unknown>) : {}

const onToolStart = async ($: $, tool: string, input: Record<string, unknown>, agentId: string | undefined): Promise<Call | null> => {
  const t = await now($)
  if (agentId) {
    const a = S.agents.find(x => x.id === agentId)
    if (a?.status === 'needs_you') {
      a.status = 'running'
      void touch($)
    }
    return null
  }
  S.inTurn = true
  clearAttention()
  const isBackground = tool === 'Bash' && input.run_in_background === true
  if (isBackground) {
    void touch($)
    return null
  }
  const call: Call = {
    id: typeof input.tool_use_id === 'string' ? input.tool_use_id : `call-${++callSeq}`,
    tool,
    detail: describeCall(tool, input),
    started: t,
    typical_ms: null,
    runs: 0,
  }
  if (tool === 'Bash' && typeof input.command === 'string') {
    const norm = normaliseCommand(input.command)
    if (norm) {
      call.durKey = `${id.project || id.cwd}\u0000${norm}`
      const runs = (await loadDurations($))[call.durKey] ?? []
      call.runs = runs.length
      call.typical_ms = runs.length >= 3 ? median(runs) : null
    }
  }
  if (tool === 'AskUserQuestion') {
    const q = (input.questions as Array<{ header?: string; question?: string; options?: Array<{ label?: string }> }> | undefined)?.[0]
    S.attention = {
      kind: 'question',
      title: q?.header || 'Question',
      text: q?.question ?? '',
      options: (q?.options ?? []).map((o, i) => ({ key: String(i + 1), label: o.label ?? '' })),
      since: t,
      callId: call.id,
    }
  } else if (tool === 'ExitPlanMode') {
    S.attention = {
      kind: 'plan',
      title: 'Plan',
      text: 'Claude has a plan ready for approval',
      options: PLAN_OPTIONS,
      since: t,
      callId: call.id,
    }
  }
  S.calls.set(call.id, call)
  void touch($)
  return call
}

const onToolEnd = async (
  $: $,
  tool: string,
  input: Record<string, unknown>,
  agentId: string | undefined,
  call: Call | null,
  r: { result?: unknown; isError?: true; deny?: string },
): Promise<void> => {
  const t = await now($)
  const result = asRecord(r.result)
  if (call) {
    S.calls.delete(call.id)
    if (S.attention?.callId === call.id) S.attention = null
  }
  if (!agentId && S.attention?.kind === 'permission' && S.calls.size === 0) S.attention = null

  if (tool === 'Bash') {
    const bgId = typeof result.backgroundTaskId === 'string' ? result.backgroundTaskId : null
    if (bgId && result.backgroundEndsWithFinalResponse !== true) {
      S.shells.unshift({
        id: bgId,
        command: clip(firstLine(String(input.command ?? ''))),
        status: 'running',
        started: call?.started ?? t,
        ended: null,
      })
      S.shells = trim(S.shells, s => s.status === 'running')
    } else if (call?.durKey && !call.asked && r.deny === undefined && result.interrupted !== true) {
      void recordDuration($, call.durKey, t - call.started)
    }
  } else if (tool === 'TaskCreate' && r.deny === undefined) {
    const task = asRecord(result.task)
    S.tasks.push({
      id: typeof task.id === 'string' ? task.id : undefined,
      subject: String(input.subject ?? task.subject ?? ''),
      status: 'pending',
    })
  } else if (tool === 'TaskUpdate' && r.deny === undefined && result.success !== false) {
    const at = S.tasks.findIndex(x => x.id === input.taskId)
    if (at >= 0) {
      const task = S.tasks[at] as Task
      if (input.status === 'deleted') S.tasks.splice(at, 1)
      else {
        if (typeof input.status === 'string') task.status = input.status
        if (typeof input.subject === 'string') task.subject = input.subject
      }
    }
  } else if (tool === 'TodoWrite' && !agentId && Array.isArray(input.todos)) {
    S.tasks = (input.todos as Array<{ content?: string; status?: string }>).map(x => ({
      subject: x.content ?? '',
      status: x.status ?? 'pending',
    }))
  } else if (tool === 'TaskStop') {
    const tid = input.task_id ?? input.shell_id ?? result.task_id
    if (typeof tid === 'string') endTask(tid, 'killed', t)
  } else if (tool === 'Artifact' && r.deny === undefined && r.isError === undefined) {
    const type = asRecord(result.type)
    if ((isDesignType(input.type_url) || isDesignType(type.url)) && typeof result.url === 'string') {
      addDesign({
        url: result.url,
        title: typeof result.title === 'string' ? result.title : typeof input.title === 'string' ? input.title : null,
        issue: null,
        boards: null,
        at: t,
      })
    }
  } else if (tool === 'Agent' && result.status === 'async_launched' && typeof result.agentId === 'string') {
    if (!S.agents.some(a => a.id === result.agentId)) {
      addAgent({
        id: result.agentId,
        type: String(input.subagent_type ?? 'general-purpose'),
        description: String(input.description ?? ''),
        status: 'running',
        started: call?.started ?? t,
        ended: null,
        parent: agentId ?? null,
      })
    }
  }
  void touch($)
}

// ---------------------------------------------------------------- register
export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    try {
      await start($, e.cwd)
    } catch {
      // never block the session
    }
    return next(e)
  })

  on('session.end', async ($, e, next) => {
    const isClear = e.reason === 'clear'
    try {
      await finish($, isClear)
    } catch {
      // the reader's staleness rule covers a missed removal
    }
    const r = await next(e)
    if (isClear) {
      try {
        id.sessionId = await $.session.id()
        if (!id.pane) id.key = `nopane-${id.sessionId}`
        void touch($)
      } catch {
        // the heartbeat retries
      }
    }
    return r
  })

  on('turn.start', async ($, e, next) => {
    // a typed prompt, or a background task waking the session (empty text)
    S.inTurn = true
    clearAttention()
    void touch($)
    return next(e)
  })

  on('turn.step', async function* ($, e, next) {
    try {
      if (e.agentId) {
        const a = S.agents.find(x => x.id === e.agentId)
        if (a?.status === 'needs_you') {
          a.status = 'running'
          void touch($)
        }
      } else {
        S.inTurn = true
        const m = prettyModel(e.model)
        const changed = clearAttention() || m !== id.model
        id.model = m
        if (changed) void touch($)
      }
    } catch {
      // observe only
    }
    return yield* next(e)
  })

  on('turn.complete', async ($, e, next) => {
    try {
      const t = await now($)
      if (e.agentId) {
        const a = S.agents.find(x => x.id === e.agentId)
        if (a && RUNNING.has(a.status)) {
          a.status = a.teammate ? 'idle' : e.isAborted ? 'killed' : e.reason === 'error' ? 'failed' : 'completed'
          a.ended = a.teammate ? null : t
        }
      } else {
        S.inTurn = false
        S.attention = null
        S.calls.clear()
      }
      scanText(e.answer ?? '', t)
      void touch($)
    } catch {
      // observe only
    }
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    try {
      const t = await now($)
      clearAttention()
      if (e.origin.kind === 'task-notification') scanText(e.text, t)
      void touch($)
    } catch {
      // observe only
    }
    return next(e)
  })

  on('session.append', ($, e, next) => {
    try {
      if (e.door !== 'tool-result' && e.message.type !== 'attachment') {
        const text = contentText(e.message.content)
        if (text.includes('task-notification') || text.includes('DESIGN_CANVAS')) {
          void now($).then(t => {
            if (scanText(text, t)) void touch($)
          })
        }
      }
    } catch {
      // observe only
    }
    return next(e)
  })

  on('agent.spawn', async ($, e, next) => {
    const r = await next(e)
    try {
      if (r.agentId) {
        addAgent({
          id: r.agentId,
          type: e.subagentType,
          description: e.description,
          status: 'running',
          started: await now($),
          ended: null,
          parent: e.parentAgentId ?? null,
          teammate: e.isTeammate === true,
        })
        void touch($)
      }
    } catch {
      // observe only
    }
    return r
  })

  on('tool.call', async ($, e, next) => {
    const input = e as unknown as Record<string, unknown>
    const tool = String(e.tool)
    let call: Call | null = null
    try {
      call = await onToolStart($, tool, input, e.agentId)
    } catch {
      // observe only
    }
    let r: Awaited<ReturnType<typeof next>> | undefined
    try {
      r = await next(e)
      return r
    } finally {
      try {
        await onToolEnd($, tool, input, e.agentId, call, (r ?? { isError: true }) as { result?: unknown; isError?: true; deny?: string })
      } catch {
        // observe only
      }
    }
  })

  on('classic.PermissionRequest', async ($, e, next) => {
    const r = await next(e)
    try {
      // a settings hook that decided means no dialog was shown
      if (r.decision) return r
      const t = await now($)
      if (e.agent_id) {
        const a = S.agents.find(x => x.id === e.agent_id)
        if (a) a.status = 'needs_you'
        else
          addAgent({
            id: e.agent_id,
            type: e.agent_type ?? 'agent',
            description: '',
            status: 'needs_you',
            started: t,
            ended: null,
            parent: null,
          })
      } else if (e.tool_name !== 'AskUserQuestion' && e.tool_name !== 'ExitPlanMode') {
        S.inTurn = true
        for (const c of S.calls.values()) if (c.tool === e.tool_name) c.asked = true
        S.attention = {
          kind: 'permission',
          title: e.tool_name,
          text: summariseInput(e.tool_name, e.tool_input),
          options: PERMISSION_OPTIONS,
          since: t,
        }
      }
      void touch($)
    } catch {
      // observe only
    }
    return r
  })

  // A foreground Bash shows its "ctrl+b to run in background" pill only once it
  // runs, i.e. after its permission prompt was answered.
  on('ui.render', { component: 'ToolProgress' }, ($, e, next) => {
    try {
      const props = e.props as { tool_use_id?: string }
      if (S.attention?.kind === 'permission' && props.tool_use_id && S.calls.has(props.tool_use_id)) {
        S.attention = null
        void touch($)
      }
    } catch {
      // observe only
    }
    return next(e)
  })
}
