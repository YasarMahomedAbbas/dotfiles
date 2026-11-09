import { describe, expect, mock, test } from 'claude-code/testing'
import type { AgentInfo, On } from 'claude-code'
import type { Engine } from 'claude-code/testing'

const HOME = '/home/t'
const FILE = `${HOME}/.cache/claude-board/42.json`
const DESIGN = 'https://claude.ai/artifact/QKN21svewxgyPb6SYRqWnd'

type Board = Record<string, any>
type ToolAnswer = (e: Record<string, unknown>) => unknown

/** The world beneath the mod: files, host commands, the session, a clock. */
const world = (on: On, tools: Record<string, ToolAnswer> = {}, env: Record<string, string> = {}) => {
  const files = new Map<string, string>([['/proc/4242/comm', 'claude\n']])
  const runs: string[][] = []
  const agents: AgentInfo[] = []
  /** What a child shell sees as CLAUDE_CODE_BRIDGE_SESSION_ID; null makes the read fail. */
  const bridge = { value: '' as string | null }
  const clock = mock.clock(on, { now: 1_000_000 })
  mock.store(on)
  mock.env(on, { TMUX_PANE: '%42', HOME, ...env })

  const ok = (stdout = '') => ({
    value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
  })
  on('fs.write', ($, e) => {
    files.set(e.path, e.text)
    return { value: undefined }
  })
  on('fs.read', ($, e) => {
    const text = files.get(e.path)
    return text === undefined ? { deny: `ENOENT ${e.path}` } : { value: text }
  })
  on('process.run', ($, e) => {
    const a = [...e.argv]
    runs.push(a)
    if (a[0] === 'mv') {
      files.set(a[3] as string, files.get(a[2] as string) ?? '')
      files.delete(a[2] as string)
      return ok()
    }
    if (a[0] === 'rm') {
      for (const p of a.slice(2)) files.delete(p)
      return ok()
    }
    if (a[0] === 'tmux' && a[1] === 'display-message') return ok('issue-1654\t1\t$3\n')
    if (a[0] === 'git' && a.includes('branch')) return ok('fix/frontend/sign-in\n')
    if (a[0] === 'git') return ok('/w/repo/.git\nFrontend/\n')
    if (a[0] === 'sh' && String(a[2]).includes('CLAUDE_CODE_BRIDGE_SESSION_ID')) {
      return bridge.value === null
        ? { value: { exitCode: 1, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
        : ok(bridge.value)
    }
    if (a[0] === 'sh') return ok('4242\n')
    return ok()
  })
  on('session.id', () => ({ value: 'sess-1' }))
  on('session.model', () => ({ value: 'claude-opus-5-5[1m]' }))
  on('agent.list', () => ({ value: [...agents] }))
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('session.end', ($, e) => ({ sessionId: e.sessionId }))
  on('turn.start', ($, e) => ({ turnId: e.turnId }))
  on('turn.complete', ($, e) => ({ text: e.answer }))
  on('prompt.submit', ($, e) => ({ text: e.text }))
  on('agent.spawn', () => ({ model: 'claude-haiku-4-5', agentId: 'a1' }))
  on('classic.PermissionRequest', () => ({}))
  on('classic.Notification', () => ({}))
  on('tool.call', async ($, e) => {
    const answer = tools[String(e.tool)]
    const result = answer ? await answer(e as unknown as Record<string, unknown>) : { ok: true }
    return { result } as never
  })

  const board = (): Board => {
    const text = files.get(FILE)
    if (text === undefined) throw new Error('no state file')
    return JSON.parse(text) as Board
  }
  return { files, runs, agents, bridge, clock, board }
}

const begin = async ($: Engine, w: ReturnType<typeof world>) => {
  await $.session.start({ cwd: '/w/repo/Frontend', surface: 'terminal', isInteractive: true })
  await w.clock.settle()
}

const turnStart = async ($: Engine, w: ReturnType<typeof world>, text = 'go', turnId = 't1') => {
  await $.turn.start({ text, turnId })
  await w.clock.settle()
}

const turnEnd = async ($: Engine, w: ReturnType<typeof world>, extra: { agentId?: string; answer?: string } = {}) => {
  await $.turn.complete({
    answer: extra.answer ?? '',
    durationMs: 10,
    isAborted: false,
    turnId: extra.agentId ? `run-${extra.agentId}` : 't1',
    reason: 'answer',
    ...(extra.agentId ? { agentId: extra.agentId } : {}),
  })
  await w.clock.settle()
}

/** The Agent tool starting a background subagent from the main loop. */
const spawn = ($: Engine, description: string) =>
  $.agent.spawn({
    tool_use_id: 'tu-agent',
    prompt: description,
    description,
    subagentType: 'Explore',
    provider: { plugin: 'engine', tier: 'core' },
    parentModel: 'claude-opus-5-5[1m]',
    background: true,
    fork: false,
  } as never)

/** A tool answer the test releases by hand. */
const held = () => {
  let release: (v: unknown) => void = () => {}
  const answer: ToolAnswer = () => new Promise(r => (release = r))
  return { answer, release: (v: unknown = { ok: true }) => release(v) }
}

describe('identity and file', () => {
  test('writes the contract fields at session start', async ($, on) => {
    const w = world(on)
    await begin($, w)
    const b = w.board()
    expect(b.v).toBe(1)
    expect(b.session_id).toBe('sess-1')
    expect(b.pid).toBe(4242)
    expect(b.tmux).toEqual({ session: 'issue-1654', pane: '%42', window: '1' })
    expect(b.cwd).toBe('/w/repo/Frontend')
    expect(b.branch).toBe('fix/frontend/sign-in')
    expect(b.model).toBe('Opus 5.5 (1M context)')
    expect(b.state).toBe('idle')
    expect(b.current).toBe(null)
    expect(b.attention).toBe(undefined)
    expect(w.files.has(`${FILE}.tmp`)).toBe(false)
    // heartbeat
    const before = b.heartbeat as number
    await w.clock.advance(10_000)
    expect(w.board().heartbeat).toBe(before + 10_000)
  })

  test('session.end removes the file and the tmux option', async ($, on) => {
    const w = world(on)
    await begin($, w)
    expect(w.files.has(FILE)).toBe(true)
    await $.session.end({ reason: 'prompt_input_exit', sessionId: 'sess-1', resume: { id: 'sess-1' } } as never)
    await w.clock.settle()
    expect(w.files.has(FILE)).toBe(false)
    expect(w.runs.some(a => a.join(' ') === 'tmux set-option -u -t $3 @board_state')).toBe(true)
    await w.clock.advance(30_000)
    expect(w.files.has(FILE)).toBe(false)
  })

  test('a session.start after a non-clear session.end (resume) writes the file again', async ($, on) => {
    const w = world(on)
    await begin($, w)
    await $.session.end({ reason: 'resume', sessionId: 'sess-1', resume: { id: 'sess-1' } } as never)
    await w.clock.settle()
    expect(w.files.has(FILE)).toBe(false)
    w.runs.length = 0
    await begin($, w)
    expect(w.board().state).toBe('idle')
    expect(w.runs.some(a => a.join(' ') === 'tmux set-option -t $3 @board_state idle')).toBe(true)
    await turnStart($, w)
    expect(w.board().state).toBe('working')
    const before = w.board().heartbeat as number
    await w.clock.advance(10_000)
    expect(w.board().heartbeat).toBe(before + 10_000)
  })
})

describe('remote control', () => {
  const RC = 'session_01AbCdEfGhIjKlMn'

  test('written when a child shell sees the variable, null when it is absent', async ($, on) => {
    const w = world(on)
    w.bridge.value = RC
    await begin($, w)
    expect(w.board().remote).toBe(RC)
    expect(w.runs.some(a => a[0] === 'sh' && a[2] === 'printf %s "$CLAUDE_CODE_BRIDGE_SESSION_ID"')).toBe(true)

    w.bridge.value = ''
    await w.clock.advance(10_000)
    expect(w.board().remote).toBe(null)
  })

  test('absent at start is null, and a new id shows on the next heartbeat', async ($, on) => {
    const w = world(on)
    await begin($, w)
    const b = w.board()
    expect('remote' in b).toBe(true)
    expect(b.remote).toBe(null)
    w.bridge.value = RC
    await w.clock.advance(10_000)
    expect(w.board().remote).toBe(RC)
    w.bridge.value = 'session_02Other'
    await w.clock.advance(10_000)
    expect(w.board().remote).toBe('session_02Other')
  })

  test('a value not shaped like a session id is null', async ($, on) => {
    const w = world(on)
    for (const bad of ['sess-1', 'session_', 'session_a b', `session_${'a'.repeat(65)}`, 'x; rm -rf /']) {
      w.bridge.value = bad
      await (w.files.has(FILE) ? w.clock.advance(10_000) : begin($, w))
      expect(w.board().remote).toBe(null)
    }
  })

  test("the mod's own env wins, without starting a shell", async ($, on) => {
    const w = world(on, {}, { CLAUDE_CODE_BRIDGE_SESSION_ID: RC })
    await begin($, w)
    expect(w.board().remote).toBe(RC)
    expect(w.runs.some(a => a[0] === 'sh' && String(a[2]).includes('CLAUDE_CODE_BRIDGE'))).toBe(false)
  })

  test('a failed read keeps the last value for one heartbeat, then null', async ($, on) => {
    const w = world(on)
    w.bridge.value = RC
    await begin($, w)
    w.bridge.value = null
    await w.clock.advance(10_000)
    expect(w.board().remote).toBe(RC)
    await w.clock.advance(10_000)
    expect(w.board().remote).toBe(null)
    w.bridge.value = RC
    await w.clock.advance(10_000)
    expect(w.board().remote).toBe(RC)
  })
})

describe('states', () => {
  test('idle → working → needs_you (AskUserQuestion) → working on the next tool call', async ($, on) => {
    const ask = held()
    const w = world(on, { AskUserQuestion: ask.answer })
    await begin($, w)
    expect(w.board().state).toBe('idle')

    await turnStart($, w)
    expect(w.board().state).toBe('working')
    expect(w.runs.some(a => a.join(' ') === 'tmux set-option -t $3 @board_state working')).toBe(true)

    const asking = $.tool.call({
      tool: 'AskUserQuestion',
      questions: [
        {
          question: 'Run the 8-step Edge guide?',
          header: 'Results',
          multiSelect: false,
          options: [
            { label: 'All 8 passed', description: '' },
            { label: 'Defer to QA', description: '' },
          ],
        },
        { question: 'Second?', header: 'Other', multiSelect: false, options: [{ label: 'x', description: '' }] },
      ],
    } as never)
    await w.clock.settle()
    let b = w.board()
    expect(b.state).toBe('needs_you')
    expect(b.attention).toMatchObject({
      kind: 'question',
      title: 'Results',
      text: 'Run the 8-step Edge guide?',
      options: [
        { key: '1', label: 'All 8 passed' },
        { key: '2', label: 'Defer to QA' },
      ],
    })
    expect(b.current.tool).toBe('AskUserQuestion')

    await $.tool.call({ tool: 'Read', file_path: '/w/repo/README.md' } as never)
    await w.clock.settle()
    b = w.board()
    expect(b.state).toBe('working')
    expect(b.attention).toBe(undefined)

    ask.release()
    await asking
    await turnEnd($, w)
    b = w.board()
    expect(b.state).toBe('idle')
    expect(typeof b.finished_at).toBe('number')
  })

  test('a background wake-up turn (empty text) is working', async ($, on) => {
    const w = world(on)
    await begin($, w)
    await turnStart($, w, '')
    expect(w.board().state).toBe('working')
  })

  test('ExitPlanMode → needs_you (plan)', async ($, on) => {
    const plan = held()
    const w = world(on, { ExitPlanMode: plan.answer })
    await begin($, w)
    await turnStart($, w)
    const p = $.tool.call({ tool: 'ExitPlanMode' } as never)
    await w.clock.settle()
    expect(w.board().state).toBe('needs_you')
    expect(w.board().attention.kind).toBe('plan')
    plan.release({ plan: 'x', isAgent: false })
    await p
    await w.clock.settle()
    expect(w.board().state).toBe('working')
  })

  test('main-loop permission prompt → needs_you, cleared by the next tool call or the turn end', async ($, on) => {
    const bash = held()
    const w = world(on, { Bash: bash.answer })
    await begin($, w)
    await turnStart($, w)

    const running = $.tool.call({ tool: 'Bash', command: 'rm -rf build\necho done' } as never)
    await w.clock.settle()
    await $.classic.PermissionRequest({ tool_name: 'Bash', tool_input: { command: 'rm -rf build\necho done' } })
    await w.clock.settle()
    let b = w.board()
    expect(b.state).toBe('needs_you')
    expect(b.attention).toMatchObject({
      kind: 'permission',
      title: 'Bash',
      text: 'rm -rf build',
      options: [
        { key: '1', label: 'Yes' },
        { key: '2', label: "Yes, don't ask again" },
        { key: '3', label: 'No' },
      ],
    })
    expect(b.current).toMatchObject({ tool: 'Bash', detail: 'rm -rf build' })

    await $.tool.call({ tool: 'Read', file_path: '/x' } as never)
    await w.clock.settle()
    expect(w.board().state).toBe('working')

    // again, this time cleared by the turn ending
    await $.classic.PermissionRequest({ tool_name: 'Edit', tool_input: { file_path: '/w/a.ts' } })
    await w.clock.settle()
    b = w.board()
    expect(b.state).toBe('needs_you')
    expect(b.attention.text).toBe('a.ts')
    bash.release({ stdout: '', stderr: '', interrupted: false })
    await running
    await turnEnd($, w)
    b = w.board()
    expect(b.state).toBe('idle')
    expect(b.attention).toBe(undefined)
  })

  test('a subagent permission prompt does not raise the session', async ($, on) => {
    const w = world(on)
    await begin($, w)
    await turnStart($, w)
    await spawn($, 'map booking flow')
    await $.classic.PermissionRequest({
      tool_name: 'Bash',
      tool_input: { command: 'ls' },
      agent_id: 'a1',
      agent_type: 'Explore',
    })
    await w.clock.settle()
    const b = w.board()
    expect(b.state).toBe('working')
    expect(b.attention).toBe(undefined)
    expect(b.agents[0]).toMatchObject({ id: 'a1', status: 'needs_you', parent: null })
  })

  test('classic Notification idle_prompt is not needs_you', async ($, on) => {
    const w = world(on)
    await begin($, w)
    await $.classic.Notification({ message: 'Claude is waiting for your input', notification_type: 'idle_prompt' })
    await w.clock.settle()
    expect(w.board().state).toBe('idle')
    await turnStart($, w)
    await turnEnd($, w)
    await $.classic.Notification({ message: 'Claude is waiting for your input', notification_type: 'idle_prompt' })
    await w.clock.settle()
    expect(w.board().state).toBe('idle')
    expect(w.board().attention).toBe(undefined)
  })

  test('turn end with a running agent → background → idle when it finishes', async ($, on) => {
    const w = world(on)
    await begin($, w)
    await turnStart($, w)
    await spawn($, 'map booking flow')
    await turnEnd($, w)
    let b = w.board()
    expect(b.state).toBe('background')
    expect(b.agents[0]).toMatchObject({ id: 'a1', type: 'Explore', description: 'map booking flow', status: 'running', ended: null })

    await turnEnd($, w, { agentId: 'a1', answer: 'found it' })
    b = w.board()
    expect(b.state).toBe('idle')
    expect(b.agents[0].status).toBe('completed')
    expect(typeof b.agents[0].ended).toBe('number')
  })

  test('agent.list poll ends an agent the list dropped', async ($, on) => {
    const w = world(on)
    await begin($, w)
    await turnStart($, w)
    await spawn($, 'd')
    w.agents.push({ id: 'a1', description: 'd', type: 'Explore', status: 'running' })
    await turnEnd($, w)
    await w.clock.advance(10_000)
    expect(w.board().state).toBe('background')
    w.agents.length = 0
    await w.clock.advance(10_000)
    expect(w.board().state).toBe('idle')
  })

  test('background shell → background → idle on its task notification', async ($, on) => {
    const w = world(on, {
      Bash: () => ({ stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b12' }),
    })
    await begin($, w)
    await turnStart($, w)
    await $.tool.call({ tool: 'Bash', command: 'pnpm dev', run_in_background: true } as never)
    await w.clock.settle()
    expect(w.board().current).toBe(null)
    expect(w.board().shells[0]).toMatchObject({ id: 'b12', command: 'pnpm dev', status: 'running' })
    await turnEnd($, w)
    expect(w.board().state).toBe('background')
    await $.session.append({
      message: {
        type: 'user',
        role: 'user',
        isMeta: true,
        content: [
          {
            type: 'text',
            text: '<task-notification>\n<task-id>b12</task-id>\n<status>completed</status>\n<summary>done</summary>\n</task-notification>',
          },
        ],
      },
      door: 'delivery',
      origin: { kind: 'task-notification' },
      uuid: 'u-1',
    } as never)
    await w.clock.settle()
    expect(w.board().shells[0].status).toBe('completed')
    expect(w.board().state).toBe('idle')
  })
})

describe('current and durations', () => {
  test('typical_ms appears after 3 runs of the same normalised Bash command', async ($, on) => {
    let ms = 0
    const w = world(on, {
      Bash: async () => {
        await w.clock.sleep(ms)
        return { stdout: '', stderr: '', interrupted: false }
      },
    })
    await begin($, w)
    await turnStart($, w)
    const runBash = async (command: string, took: number) => {
      ms = took
      const p = $.tool.call({ tool: 'Bash', command } as never)
      await w.clock.settle()
      const during = w.board().current
      await w.clock.advance(took)
      await p
      await w.clock.settle()
      return during
    }
    let cur = await runBash('pnpm test -- foo', 5000)
    expect(cur).toMatchObject({ tool: 'Bash', detail: 'pnpm test -- foo', typical_ms: null, runs: 0 })
    cur = await runBash('FOO=1 pnpm test -- bar', 7000)
    expect(cur).toMatchObject({ typical_ms: null, runs: 1 })
    cur = await runBash('cd /w/repo && pnpm test', 9000)
    expect(cur).toMatchObject({ typical_ms: null, runs: 2 })
    cur = await runBash('pnpm test --watch=false', 1000)
    expect(cur).toMatchObject({ detail: 'pnpm test --watch=false', typical_ms: 7000, runs: 3 })
    expect(w.board().current).toBe(null)
    // another command keeps its own history
    cur = await runBash('pnpm lint', 1000)
    expect(cur).toMatchObject({ typical_ms: null, runs: 0 })
  })

  test('tasks from TaskCreate/TaskUpdate and TodoWrite', async ($, on) => {
    let n = 0
    const w = world(on, {
      TaskCreate: e => ({ task: { id: String(++n), subject: e.subject } }),
      TaskUpdate: e => ({ success: true, taskId: e.taskId, updatedFields: ['status'] }),
    })
    await begin($, w)
    await turnStart($, w)
    await $.tool.call({ tool: 'TaskCreate', subject: 'State model', description: '' } as never)
    await $.tool.call({ tool: 'TaskCreate', subject: 'Tests', description: '' } as never)
    await $.tool.call({ tool: 'TaskUpdate', taskId: '1', status: 'completed' } as never)
    await w.clock.settle()
    expect(w.board().tasks).toEqual([
      { subject: 'State model', status: 'completed' },
      { subject: 'Tests', status: 'pending' },
    ])
    await $.tool.call({
      tool: 'TodoWrite',
      todos: [{ content: 'Only', status: 'in_progress', activeForm: 'Doing' }],
    } as never)
    await w.clock.settle()
    expect(w.board().tasks).toEqual([{ subject: 'Only', status: 'in_progress' }])
  })
})

describe('designs', () => {
  test('captures a Design artifact and DESIGN_CANVAS lines', async ($, on) => {
    const w = world(on, {
      Artifact: e => ({
        created_from_type: true,
        url: 'https://claude.ai/artifact/abc123',
        version: '1',
        title: e.title,
        type: { url: DESIGN, release: '1' },
        own_files: [],
        type_files: [],
      }),
    })
    await begin($, w)
    await turnStart($, w)
    await $.tool.call({ tool: 'Artifact', type_url: DESIGN, title: 'Booking flow' } as never)
    // a non-design artifact is ignored
    await $.tool.call({ tool: 'Artifact', action: 'list' } as never)
    await w.clock.settle()
    let d = w.board().designs
    expect(d.length).toBe(1)
    expect(d[0]).toMatchObject({ url: 'https://claude.ai/artifact/abc123', title: 'Booking flow', issue: null })

    await turnEnd($, w, { answer: 'Done.\nDESIGN_CANVAS issue=1430 url=https://claude.ai/artifact/abc123 boards=11\n' })
    d = w.board().designs
    expect(d.length).toBe(1)
    expect(d[0]).toMatchObject({ url: 'https://claude.ai/artifact/abc123', title: 'Booking flow', issue: 1430, boards: 11 })

    await $.session.append({
      message: {
        type: 'assistant',
        role: 'assistant',
        content: [{ type: 'text', text: 'DESIGN_CANVAS issue=none url=https://claude.ai/artifact/zzz' }],
      },
      door: 'response',
      origin: { kind: 'model', model: 'x' },
      uuid: 'u-2',
    } as never)
    await w.clock.settle()
    d = w.board().designs
    expect(d.length).toBe(2)
    expect(d[0]).toMatchObject({ url: 'https://claude.ai/artifact/zzz', issue: null })
  })
})
