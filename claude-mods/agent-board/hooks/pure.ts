// Pure helpers for the agent-board mod: no `$`, no I/O.

/** The user's Design artifact type (claude.ai). Compared by its id. */
export const DESIGN_TYPE_URL = 'https://claude.ai/artifact/QKN21svewxgyPb6SYRqWnd'

export const clip = (s: string, n = 120): string => (s.length > n ? `${s.slice(0, n - 1)}…` : s)

export const firstLine = (s: string): string => {
  const line = s.split('\n').find(l => l.trim() !== '') ?? ''
  return line.trim()
}

/**
 * The key a Bash command's duration is recorded under: first line, leading
 * `cd <dir> &&` and `VAR=value` assignments stripped, then the first word plus
 * the second when it is not a flag or an operator (`pnpm test -- foo` → `pnpm test`).
 */
export const normaliseCommand = (command: string): string => {
  let s = firstLine(command)
  for (let i = 0; i < 8; i++) {
    const before = s
    s = s.replace(/^cd\s+(?:'[^']*'|"[^"]*"|\S+)\s*(?:&&|;)\s*/, '')
    s = s.replace(/^(?:env\s+)?[A-Za-z_][A-Za-z0-9_]*=(?:'[^']*'|"[^"]*"|\S*)\s+/, '')
    s = s.replace(/^(?:time|command|exec|nice)\s+/, '')
    if (s === before) break
  }
  const words = s.split(/\s+/).filter(Boolean)
  const [w1, w2] = words
  if (w1 === undefined) return ''
  return w2 !== undefined && !/^[-|&;<>(]/.test(w2) ? `${w1} ${w2}` : w1
}

export const median = (xs: readonly number[]): number | null => {
  if (xs.length === 0) return null
  const s = [...xs].sort((a, b) => a - b)
  const mid = Math.floor(s.length / 2)
  const hi = s[mid] as number
  return s.length % 2 === 1 ? hi : Math.round(((s[mid - 1] as number) + hi) / 2)
}

/** `claude-opus-5-5[1m]` → `Opus 5.5 (1M context)`; anything else as given. */
export const prettyModel = (id: string): string => {
  const m = /(opus|sonnet|haiku|fable)-(\d+)(?:-(\d{1,2}))?(?:-\d{8})?(\[1m\])?/i.exec(id)
  if (!m) return id
  const family = (m[1] as string).charAt(0).toUpperCase() + (m[1] as string).slice(1).toLowerCase()
  const version = m[3] !== undefined ? `${m[2]}.${m[3]}` : (m[2] as string)
  return `${family} ${version}${m[4] ? ' (1M context)' : ''}`
}

export type TaskNote = { id: string; status: string }

/**
 * The background-task notifications in a text:
 * `<task-notification><task-id>b12</task-id><status>completed</status>…`.
 */
export const parseTaskNotifications = (text: string): TaskNote[] => {
  if (!text.includes('task-notification')) return []
  const out: TaskNote[] = []
  const blocks = text.match(/<task-notification>[\s\S]*?<\/task-notification>/g) ?? []
  for (const b of blocks) {
    const id = /<task[-_]id>\s*([^<\s]+)\s*<\/task[-_]id>/.exec(b)?.[1]
    const status = /<status>\s*([^<]+?)\s*<\/status>/.exec(b)?.[1] ?? 'completed'
    if (id) out.push({ id, status })
  }
  return out
}

export type DesignLine = { url: string; issue: number | null; boards: number | null; title: string | null }

/** `DESIGN_CANVAS issue=<n|none> url=<url> [boards=<n>] [title="…"]` lines. */
export const parseDesignLines = (text: string): DesignLine[] => {
  if (!text.includes('DESIGN_CANVAS')) return []
  const out: DesignLine[] = []
  for (const line of text.split('\n')) {
    const m = /DESIGN_CANVAS\s+issue=(\S+)\s+url=(\S+)/.exec(line)
    if (!m) continue
    const issue = /^#?(\d+)$/.exec(m[1] as string)
    const boards = /\bboards=(\d+)/.exec(line)
    const title = /\btitle=(?:"([^"]*)"|(\S+))/.exec(line)
    out.push({
      url: (m[2] as string).replace(/[`'")\].,]+$/, ''),
      issue: issue ? Number(issue[1]) : null,
      boards: boards ? Number(boards[1]) : null,
      title: title ? (title[1] ?? title[2] ?? null) : null,
    })
  }
  return out
}

/** The artifact id at the end of a claude.ai artifact url. */
export const artifactId = (url: string): string =>
  url.replace(/[?#].*$/, '').replace(/\/+$/, '').split('/').pop() ?? url

export const isDesignType = (url: unknown): boolean =>
  typeof url === 'string' && artifactId(url) === artifactId(DESIGN_TYPE_URL)

/** A short subject for a tool call's input, for `current.detail`. */
export const describeCall = (tool: string, input: Record<string, unknown>): string => {
  const str = (k: string): string | undefined => {
    const v = input[k]
    return typeof v === 'string' && v.trim() !== '' ? v : undefined
  }
  if (tool === 'Bash') return clip(firstLine(str('command') ?? ''))
  if (tool === 'Agent') return clip(str('description') ?? firstLine(str('prompt') ?? ''))
  if (tool === 'Skill') return clip(str('skill') ?? '')
  if (tool === 'AskUserQuestion') {
    const q = (input.questions as Array<{ header?: string; question?: string }> | undefined)?.[0]
    return clip(q?.header ?? q?.question ?? '')
  }
  const path = str('file_path') ?? str('notebook_path') ?? str('path')
  if (path) return clip(path.split('/').pop() || path)
  const v = str('description') ?? str('subject') ?? str('pattern') ?? str('url') ?? str('query') ??
    str('action') ?? str('prompt') ?? str('skill') ?? str('taskId') ?? str('task_id')
  return v ? clip(firstLine(v)) : ''
}

/** A short summary of a permission request's tool input. */
export const summariseInput = (tool: string, input: unknown): string => {
  if (input === null || typeof input !== 'object') return ''
  const rec = input as Record<string, unknown>
  if (tool === 'Bash' && typeof rec.command === 'string') return clip(firstLine(rec.command), 200)
  const d = describeCall(tool, rec)
  if (d) return d
  try {
    return clip(JSON.stringify(input), 200)
  } catch {
    return ''
  }
}

/** Every text in a row's content (string, or blocks with `text`/`content`). */
export const contentText = (content: unknown, depth = 0): string => {
  if (typeof content === 'string') return content
  if (!Array.isArray(content) || depth > 2) return ''
  const parts: string[] = []
  for (const b of content) {
    if (typeof b === 'string') parts.push(b)
    else if (b && typeof b === 'object') {
      const blk = b as { text?: unknown; content?: unknown }
      if (typeof blk.text === 'string') parts.push(blk.text)
      else if (blk.content !== undefined) parts.push(contentText(blk.content, depth + 1))
    }
  }
  return parts.join('\n')
}
