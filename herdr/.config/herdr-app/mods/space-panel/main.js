// Space (C-f a, or the panel's "Space" button). It always opens on This space: a card per
// agent in the shown space, most urgent first. Each card: tab number, name and worktree branch; state and how
// long it's been in it; what it's working on (the ticket's title, else the title Claude gives
// its terminal); how far along (the pipeline's stages from the ticket, else Claude's task
// list); and what it's doing now (the question and its options, the tool in flight timed
// against its usual run, or the start of its last reply). Running sub-agents and background
// shells hang under it. Idle agents fold into one row at the bottom.
//
// herdr gives the agents, tabs, branches and states live. The rest comes from
// `board list --json` (the agent-board mod's state files, enriched with the ticket),
// re-read every 3 s, but only while this view is the one the panel shows. A board entry
// belongs to the agent whose terminal id it recorded (herdr.terminal, from $HC_TERMINAL_ID).
// Sessions started before the mod wrote that field fall back to the folder, when only one
// agent and one entry share it.
//
// "‹ Spaces" (or s) goes to All spaces: one row per space with its session count and how
// many need you, are working, are done or idle, plus what the most urgent one is about.
// Picking a row shows that space in herdr and comes back to This space.
//
// Keys (when focused): j/k or ↑/↓ move, ⏎ go, 1-9 answer the selected question,
// v by attention / by tab, i show or fold the idle ones, s all spaces, h/esc back to the
// terminal (in All spaces: back to This space).

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex, ScrollHandle } from "gpui-base";
import { agents, panes, spaces, terminals, theme, run, exec, hc, layout, nextCommand, checking, notify } from "herdr";

const POLL_MS = 3000;
const RANK = { blocked: 5, working: 4, background: 3, done: 2, idle: 1 };
const LABEL = { blocked: "needs you", working: "working", background: "background", done: "done", idle: "idle" };

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// Is this view the one the panel shows?
function shown() {
  const root = layout(), panel = find(root, "panel"), body = find(root, "panel-body");
  return Boolean(panel && !panel.hidden && body?.active === "space-panel");
}

// The agents mod's own cleaning: drops a status glyph/spinner before the title.
const clean = (s) => (s ?? "").replace(/^[^\p{L}\p{N}\p{Ps}\p{Pi}]+/u, "").replace(/^\[ [!.] \] /, "").trim();
const norm = (p) => (p || "").replace(/\/+$/, "");
const clip = (s, n) => (s && s.length > n ? s.slice(0, n - 1) + "…" : s || "");

function ago(ms) {
  if (!ms) return "";
  const s = Math.max(0, (Date.now() - ms) / 1000);
  if (s < 60) return "now";
  if (s < 3600) return `${Math.floor(s / 60)}m`;
  if (s < 86400) return `${Math.floor(s / 3600)}h`;
  return `${Math.floor(s / 86400)}d`;
}
function clock(ms) {
  const s = Math.max(0, Math.round(ms / 1000));
  return s < 3600 ? `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}` : `${Math.floor(s / 3600)}h${String(Math.floor((s % 3600) / 60)).padStart(2, "0")}`;
}

export default class Space extends View {
  init(_props, cx) {
    this.board = [];
    this.loaded = false;
    this.last = 0;
    this.busy = false;
    this.byTab = false;
    this.showIdle = false;
    this.sel = null; // the selected card's terminal address
    this.view = "this"; // "this" (the shown space) or "all" (every space)
    this.spaceSel = null; // the selected row in All spaces
    this.handle = cx.focus_handle();
    this.scroll = ScrollHandle.new();
    if (checking()) return;
    cx.spawn(async (cx) => { for (;;) { const c = await nextCommand(); if (c === "focus") { this.handle.focus(); cx.notify(); } } });
    // Checked every second, read every POLL_MS while shown, and at once when it's opened.
    cx.timer.every(1000, (cx) => {
      if (!shown()) { this.wasShown = false; return; }
      // Every time the panel opens, it opens on This space.
      if (!this.wasShown && this.view !== "this") { this.view = "this"; cx.notify(); }
      if (!this.wasShown || Date.now() - this.last >= POLL_MS) this.refresh(cx);
      this.wasShown = true;
    });
    this.refresh(cx);
  }

  refresh(cx) {
    if (this.busy) return;
    this.busy = true;
    this.last = Date.now();
    cx.spawn(async (cx) => {
      try {
        const r = await exec("board", ["list", "--json"], { timeout: 10000 });
        if (r.code === 0) { this.board = JSON.parse(r.stdout || "[]"); this.error = null; }
        else this.error = (r.stderr || "board list failed").trim().split("\n").pop();
      } catch (e) {
        this.error = String(e);
      }
      this.loaded = true;
      this.busy = false;
      cx.notify();
    });
  }

  // Every agent in the shown space, each with its tab, pane, board entry and resolved state.
  cards(space) {
    if (!space) return [];
    const all = agents().filter((a) => a.space === space.id);
    const terms = new Map(terminals().map((x) => [x.address, x]));
    // A sub-agent with its own pane hangs under its parent instead of getting a card.
    const mine = new Set(all.map((a) => a.address));
    const top = all.filter((a) => !mine.has(terms.get(a.address)?.parent));
    const paneOf = new Map(panes().filter((p) => p.terminal).map((p) => [p.terminal, p]));
    const tabs = new Map(space.tabs.map((t) => [t.id, t]));
    const live = this.board.filter((b) => !b.stale);
    const byTerm = new Map(live.filter((b) => b.herdr?.terminal).map((b) => [b.herdr.terminal, b]));
    // Fallback for entries without herdr.terminal: a folder only one agent and one entry share.
    const cwdOf = (a) => norm(paneOf.get(a.address)?.cwd ?? terms.get(a.address)?.cwd);
    const count = (xs, f) => xs.reduce((m, x) => m.set(f(x), (m.get(f(x)) ?? 0) + 1), new Map());
    const agentsAt = count(top, cwdOf);
    const loose = live.filter((b) => !b.herdr?.terminal);
    const entriesAt = count(loose, (b) => norm(b.cwd));
    return top.map((a) => {
      const pane = paneOf.get(a.address);
      const tab = tabs.get(a.tab);
      const cwd = cwdOf(a);
      let b = byTerm.get(a.address);
      if (!b && cwd && agentsAt.get(cwd) === 1 && entriesAt.get(cwd) === 1) b = loose.find((x) => norm(x.cwd) === cwd);
      let state = a.status ?? "idle";
      if (b?.state === "needs_you") state = "blocked";
      else if (b?.state === "background" && (state === "idle" || state === "done")) state = "background";
      const since = state === "working" ? (tab?.working_since ?? b?.since) : (b?.since ?? tab?.changed_at);
      const kids = [...terms.values()].filter((x) => x.parent === a.address && x.state === "live");
      return { a, pane, tab, b, cwd, state, since, kids, branch: pane?.branch ?? b?.branch ?? null };
    });
  }

  order(cards) {
    const byTab = (x, y) => (x.a.tab_index - y.a.tab_index) || (x.a.seq - y.a.seq);
    if (this.byTab) return [...cards].sort(byTab);
    return [...cards].sort((x, y) => (RANK[y.state] - RANK[x.state]) || (x.since ?? 0) - (y.since ?? 0) || byTab(x, y));
  }

  go(c) {
    if (!c) return;
    run("tab.select", { id: c.a.tab });
    run("pane.focus", { terminal: c.a.address });
  }

  answer(c, key) {
    const opts = c?.b?.attention?.options ?? [];
    if (c?.state !== "blocked" || !opts.some((o) => o.key === key)) return false;
    hc(["keys", c.a.address, key]).then((r) => {
      if (r.code !== 0) notify({ title: "This space", body: `Couldn't answer: ${(r.stderr || "").trim()}`, level: "error" });
    });
    return true;
  }

  jump(s) {
    if (!s) return;
    this.view = "this";
    if (!s.active) run("space.select", { id: s.id });
  }

  keyAll(e, cx) {
    const list = spaces();
    const at = Math.max(0, list.findIndex((s) => s.id === this.spaceSel));
    const k = e.keystroke, n = list.length;
    if (["j", "down", "ctrl-n", "ctrl-j"].includes(k) && n) this.spaceSel = list[(at + 1) % n].id;
    else if (["k", "up", "ctrl-p", "ctrl-k"].includes(k) && n) this.spaceSel = list[(at + n - 1) % n].id;
    else if (k === "enter") this.jump(list[at]);
    else if (["escape", "h", "backspace", "s"].includes(k)) this.view = "this";
    else return;
    cx.stop_propagation();
    cx.notify();
  }

  key(e, cx) {
    if (this.view === "all") return this.keyAll(e, cx);
    const list = this.visible ?? [];
    const at = Math.max(0, list.findIndex((c) => c.a.address === this.sel));
    const move = (d) => { const n = list.length; if (!n) return; this.sel = list[(at + d + n) % n].a.address; this.scroll.scroll_to_item((at + d + n) % n); };
    const k = e.keystroke;
    if (["j", "down", "ctrl-n", "ctrl-j"].includes(k)) move(1);
    else if (["k", "up", "ctrl-p", "ctrl-k"].includes(k)) move(-1);
    else if (k === "enter") this.go(list[at]);
    else if (k === "v") this.byTab = !this.byTab;
    else if (k === "i") this.showIdle = !this.showIdle;
    else if (k === "s" || k === "backspace") { this.view = "all"; this.spaceSel = spaces().find((s) => s.active)?.id ?? null; }
    else if (k === "h" || k === "escape") run("pane.go", { direction: "left" });
    else if (/^[1-9]$/.test(k)) { if (!this.answer(list[at], k)) return; }
    else return;
    cx.stop_propagation();
    cx.notify();
  }

  // ----------------------------------------------------------------- rendering

  status(t, state, since) {
    const color = t[state === "background" ? "working" : state] ?? t.dim;
    const icon = state === "working"
      ? svg("mods/workspace-chrome/spinner.svg").size(11).flex_none().text_color(t.working).spin(900)
      : state === "blocked"
        ? div().flex_none().px(6).h(17).rounded(5).bg(t.blocked + "26").text_size(10.5).font_semibold().text_color(t.blocked).flex().items_center().child("Needs you")
        : state === "idle"
          ? div().size(7).flex_none().rounded(4).border(1.5).border_color(t.idle ?? t.dim)
          : div().size(7).flex_none().rounded(4).bg(color);
    const text = state === "blocked" ? ago(since) : `${LABEL[state]}${since ? " " + ago(since) : ""}`;
    return h_flex().flex_none().gap(5).items_center().text_size(11).text_color(state === "idle" ? t.dim : color)
      .child(icon).child(text);
  }

  headline(c) {
    const tk = c.b?.ticket;
    if (tk?.title) return { issue: tk.issue ? `#${tk.issue}` : null, text: tk.title };
    const live = clean(c.a.title);
    const prog = c.a.program?.name;
    const path = /^[~/]/.test((c.a.title ?? "").replace(/^[^\p{L}\p{N}~/]+/u, ""));
    const telling = live && live !== c.a.address && live !== prog && !path && live.toLowerCase() !== c.a.program?.key;
    return { issue: null, text: telling ? live : (c.tab?.name ?? prog ?? "agent") };
  }

  progress(t, c) {
    const tk = c.b?.ticket;
    if (tk?.stages?.length && tk.stage_index) {
      const cur = tk.stage_index - 1;
      const part = tk.checkpoints_total ? [tk.checkpoints_done ?? 0, tk.checkpoints_total]
        : tk.tasks_total ? [tk.tasks_done ?? 0, tk.tasks_total] : null;
      // A sliver at 0/7, so the current stage never looks like one still to come.
      const frac = part ? Math.max(0.08, Math.min(1, part[0] / Math.max(1, part[1]))) : 0.5;
      return h_flex().gap(3).children(tk.stages.map((s, i) => {
        const done = i < cur, now = i === cur;
        const bar = now
          ? div().w_full().h(4).rounded(2).bg(t.raised).overflow_hidden().child(div().h_full().w(`${Math.round(frac * 100)}%`).bg(t.working))
          : div().h(4).rounded(2).bg(done ? t.done : t.raised);
        return v_flex().flex_1().min_w(0).gap(3)
          .child(bar)
          .child(div().truncate().text_size(10).text_color(now ? t.foreground : done ? t.muted : t.dim).when(now, (e) => e.font_semibold())
            .child(now && part ? `${s} ${part[0]}/${part[1]}` : s));
      }));
    }
    const tasks = c.b?.tasks ?? [];
    if (!tasks.length) return null;
    const done = tasks.filter((x) => x.status === "completed").length;
    const cur = tasks.find((x) => x.status === "in_progress") ?? tasks.find((x) => x.status !== "completed");
    const full = done === tasks.length;
    return h_flex().gap(8).items_center().text_size(11.5).text_color(t.muted)
      .child(h_flex().w(60).h(4).flex_none().rounded(2).bg(t.raised).overflow_hidden()
        .child(div().h_full().w(Math.round(60 * done / tasks.length)).bg(full ? t.done : t.working)))
      .child(div().flex_none().child(`${done}/${tasks.length}`))
      .when(Boolean(cur), (e) => e.child(div().min_w(0).truncate().child(`· ${cur.subject}`)));
  }

  now(t, c) {
    const b = c.b;
    if (c.state === "blocked" && b?.attention) {
      const at = b.attention;
      const q = clip(at.text || at.title || "Waiting for you", 220);
      return v_flex().gap(5)
        .child(div().text_size(12).text_color(t.foreground).child(q))
        .when((at.options ?? []).length > 0, (e) => e.child(h_flex().flex_wrap().gap(5).children(at.options.slice(0, 9).map((o) =>
          h_flex().id(`opt-${c.a.address}-${o.key}`).h(20).px(7).gap(4).items_center().rounded(5).cursor_pointer()
            .border(1).border_color(t.border).bg(t.raised).text_size(11).text_color(t.muted)
            .hover((s) => s.bg(t.hover).text_color(t.foreground))
            .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
            .on_click((_e, cx) => { cx.stop_propagation(); this.answer(c, o.key); })
            .child(div().font_semibold().text_color(t.blocked).child(o.key))
            .child(clip(o.label, 40))))));
    }
    if (b?.current && (c.state === "working" || c.state === "background")) {
      const el = Date.now() - (b.current.started ?? Date.now());
      const slow = b.current.typical_ms && el > b.current.typical_ms;
      return h_flex().gap(6).items_center().min_w(0).text_size(11.5)
        .child(div().flex_none().text_color(t.foreground).font_medium().child(b.current.tool))
        .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(b.current.detail || ""))
        .child(div().flex_none().text_size(10.5).text_color(slow ? t.ansi3 : t.dim)
          .child(b.current.typical_ms ? `${clock(el)} / ~${clock(b.current.typical_ms)}` : clock(el)));
    }
    if (b?.reply && (c.state === "done" || c.state === "idle")) {
      return div().text_size(11.5).text_color(t.muted).child(`“${clip(b.reply, 200)}”`);
    }
    return null;
  }

  kids(t, c) {
    const rows = [];
    for (const k of c.kids) rows.push({ glyph: "●", color: t[k.status] ?? t.working, what: k.name || k.agent || "agent", desc: clean(k.title ?? "") });
    for (const x of c.b?.agents ?? []) {
      if (x.status !== "running" && x.status !== "needs_you") continue;
      rows.push({ glyph: "●", color: x.status === "needs_you" ? t.blocked : t.working, what: x.type || "agent", desc: x.description || "" });
    }
    for (const s of c.b?.shells ?? []) {
      if (s.status !== "running") continue;
      rows.push({ glyph: "◆", color: t.muted, what: "shell", desc: s.command || "" });
    }
    if (!rows.length) return null;
    const shownRows = rows.slice(0, 3);
    return v_flex().gap(1).text_size(11).text_color(t.dim)
      .children(shownRows.map((r, i) => h_flex().gap(6).min_w(0).items_center()
        .child(div().flex_none().child(i === shownRows.length - 1 && rows.length <= 3 ? "└" : "├"))
        .child(div().flex_none().text_color(r.color).child(r.glyph))
        .child(div().flex_none().child(r.what))
        .child(div().min_w(0).truncate().text_color(t.muted).child(r.desc))))
      .when(rows.length > 3, (e) => e.child(div().pl(14).child(`└ ${rows.length - 3} more`)));
  }

  card(t, c, selected, focused) {
    const h = this.headline(c);
    const progress = this.progress(t, c);
    const now = this.now(t, c);
    const kids = this.kids(t, c);
    const n = c.a.tab_index ?? c.tab?.index;
    return v_flex().id(`card-${c.a.address}`).flex_none().p(10).gap(7).rounded(8).cursor_pointer()
      .border(1).border_color(selected && focused ? t.accent : t.border)
      .bg(selected ? t.selected : t.background)
      .when(c.state === "blocked", (e) => e.border_l(3).border_color(selected && focused ? t.accent : t.blocked))
      .hover((s) => s.bg(t.hover))
      .on_click((_e, cx) => { this.sel = c.a.address; this.go(c); cx.notify(); })
      .child(h_flex().gap(7).items_center().min_w(0)
        .child(div().flex_none().px(5).rounded(4).bg(t.raised).text_size(10.5).font_semibold().text_color(t.muted).child(String(n ?? "?")))
        .child(div().flex_none().max_w(120).truncate().text_size(11.5).text_color(t.muted).child(c.tab?.name ?? c.a.tab_name ?? ""))
        .child(div().flex_1().min_w(0).truncate().text_size(10.5).text_color(t.dim).child(c.branch ?? ""))
        .child(this.status(t, c.state, c.since)))
      .child(h_flex().gap(5).min_w(0).items_start()
        .when(Boolean(h.issue), (e) => e.child(div().flex_none().pt(1.5).text_size(11.5).text_color(t.dim).child(h.issue)))
        .child(div().min_w(0).text_size(13).font_semibold().text_color(t.foreground).child(clip(h.text, 120))))
      .when(Boolean(progress), (e) => e.child(progress))
      .when(Boolean(now), (e) => e.child(now))
      .when(Boolean(kids), (e) => e.child(kids));
  }

  navButton(t, id, label, action) {
    return div().id(id).flex_none().px(6).h(20).rounded(5).flex().items_center().cursor_pointer()
      .text_size(11).text_color(t.muted).bg(t.raised).hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation())
      .on_click((_e, cx) => { cx.stop_propagation(); action(); this.handle.focus(); cx.notify(); })
      .child(label);
  }

  // All spaces: a row per space, in herdr's order.
  renderAll(t) {
    const list = spaces();
    if (!list.some((s) => s.id === this.spaceSel)) this.spaceSel = list.find((s) => s.active)?.id ?? list[0]?.id ?? null;
    const focused = this.handle.is_focused?.() ?? false;
    const stateColor = (st) => (st === "idle" ? t.dim : t[st === "background" ? "working" : st] ?? t.dim);
    const total = { blocked: 0, working: 0, done: 0, idle: 0 };
    const rows = list.map((s) => {
      const cards = this.order(this.cards(s));
      const n = (st) => cards.filter((c) => c.state === st || (st === "working" && c.state === "background")).length;
      const counts = { blocked: n("blocked"), working: n("working"), done: n("done"), idle: n("idle") };
      for (const k of Object.keys(total)) total[k] += counts[k];
      const top = cards[0];
      const sel = s.id === this.spaceSel;
      const chip = (st, label) => counts[st] > 0
        ? h_flex().flex_none().gap(4).items_center().text_size(11).text_color(st === "idle" ? t.dim : stateColor(st))
          .child(st === "working"
            ? svg("mods/workspace-chrome/spinner.svg").size(10).text_color(t.working).spin(900)
            : st === "idle" ? div().size(7).rounded(4).border(1.5).border_color(t.idle ?? t.dim) : div().size(7).rounded(4).bg(stateColor(st)))
          .child(`${counts[st]}${label ? " " + label : ""}`)
        : null;
      const chips = [chip("blocked", "on hold"), chip("working", ""), chip("done", "done"), chip("idle", "idle")].filter(Boolean);
      // What the most urgent agent is about, when one isn't idle.
      let about = null;
      if (top && top.state !== "idle") {
        const h = this.headline(top);
        const q = top.state === "blocked" ? top.b?.attention?.title || top.b?.attention?.text : null;
        about = `${top.tab?.name ?? top.a.tab_name}: ${q ? clip(q, 80) : clip((h.issue ? h.issue + " " : "") + h.text, 90)}`;
      }
      return v_flex().id(`space-${s.id}`).flex_none().px(10).py(8).gap(4).rounded(8).cursor_pointer()
        .border(1).border_color(sel && focused ? t.accent : t.border).bg(sel ? t.selected : t.background)
        .hover((x) => x.bg(t.hover))
        .on_click((_e, cx) => { this.spaceSel = s.id; this.jump(s); cx.notify(); })
        .child(h_flex().gap(8).items_center().min_w(0)
          .child(div().size(8).flex_none().rounded(4).bg(top ? stateColor(top.state) : t.border))
          .child(div().flex_none().max_w(150).truncate().font_semibold().text_color(t.foreground).child(s.name))
          .when(s.active, (e) => e.child(div().flex_none().text_size(10.5).text_color(t.accent).child("here")))
          .child(div().flex_1().min_w(0).truncate().text_size(10.5).text_color(t.dim).child(s.branch ?? ""))
          .child(div().flex_none().text_size(11).text_color(t.muted).child(`${cards.length} ${cards.length === 1 ? "session" : "sessions"}`)))
        .when(chips.length > 0, (e) => e.child(h_flex().flex_wrap().gap_x(10).gap_y(2).pl(16).children(chips)))
        .when(Boolean(about), (e) => e.child(div().pl(16).truncate().text_size(11.5).text_color(top.state === "blocked" ? t.foreground : t.muted).child(about)));
    });
    const summary = [["blocked", "on hold"], ["working", "working"], ["done", "done"], ["idle", "idle"]].filter(([k]) => total[k] > 0)
      .map(([k, label]) => h_flex().gap(5).items_center().child(div().size(7).rounded(4).bg(stateColor(k))).child(`${total[k]} ${label}`));
    return v_flex().id("space").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .on_mouse_down("left", () => this.handle.focus())
      .size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background).border_1().border_color(t.border).text_size(12.5).text_color(t.foreground)
      .child(v_flex().flex_none().px(14).pt(10).pb(8).gap(5).border_b(1).border_color(t.border)
        .child(h_flex().gap(8).items_center()
          .child(this.navButton(t, "to-this", "‹ This space", () => { this.view = "this"; }))
          .child(div().font_semibold().text_size(13.5).text_color(t.foreground).child("All spaces")))
        .when(summary.length > 0, (e) => e.child(h_flex().flex_wrap().gap_x(12).gap_y(2).text_size(11).text_color(t.muted).children(summary))))
      .child(v_flex().id("space-rows").flex_1().min_h(0).p(8).gap(6).overflow_y_scrollbar().children(rows))
      .child(h_flex().flex_none().h(22).px(12).items_center().border_t(1).border_color(t.border).text_size(10.5).text_color(t.dim)
        .child("j/k move · ⏎ go to space · esc back"));
  }

  render() {
    const t = theme();
    if (this.view === "all") return this.renderAll(t);
    const space = spaces().find((s) => s.active);
    const all = this.order(this.cards(space));
    const idle = all.filter((c) => c.state === "idle");
    const busy = all.filter((c) => c.state !== "idle");
    const list = this.byTab || this.showIdle ? all : busy;
    this.visible = list;
    if (!list.some((c) => c.a.address === this.sel)) this.sel = list[0]?.a.address ?? null;
    const focused = this.handle.is_focused?.() ?? false;

    const count = (s) => all.filter((c) => c.state === s).length;
    const counts = ["blocked", "working", "background", "done", "idle"].filter((s) => count(s) > 0).map((s) =>
      h_flex().gap(5).items_center()
        .child(div().size(7).rounded(4).bg(s === "idle" ? t.dim : t[s === "background" ? "working" : s] ?? t.dim))
        .child(`${count(s)} ${LABEL[s]}`));

    const header = v_flex().flex_none().px(14).pt(10).pb(8).gap(5).border_b(1).border_color(t.border)
      .child(h_flex().gap(8).items_center()
        .child(this.navButton(t, "to-all", "‹ Spaces", () => { this.view = "all"; this.spaceSel = space?.id ?? null; }))
        .child(div().font_semibold().text_size(13.5).text_color(t.foreground).truncate().child(space?.name ?? "No space"))
        .child(div().flex_1().min_w(0).truncate().text_size(11).text_color(t.dim).child(space?.branch ?? ""))
        .child(div().id("order").flex_none().px(6).rounded(5).text_size(11).text_color(t.dim).cursor_pointer().hover((s) => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => { this.byTab = !this.byTab; cx.notify(); })
          .child(this.byTab ? "by tab" : "by attention")))
      .when(counts.length > 0, (e) => e.child(h_flex().flex_wrap().gap_x(12).gap_y(2).text_size(11).text_color(t.muted).children(counts)));

    const cards = list.map((c) => this.card(t, c, c.a.address === this.sel, focused));
    if (!this.byTab && idle.length) {
      cards.push(h_flex().id("idle-fold").flex_none().px(6).py(4).gap(8).items_center().rounded(6).cursor_pointer()
        .text_size(11.5).text_color(t.dim).hover((s) => s.bg(t.hover))
        .on_click((_e, cx) => { this.showIdle = !this.showIdle; cx.notify(); })
        .child(this.showIdle ? "▾" : "▸")
        .child(div().text_color(t.muted).child(this.showIdle ? "hide idle" : `${idle.length} idle`))
        .when(!this.showIdle, (e) => e.child(div().min_w(0).truncate().child(idle.map((c) => c.tab?.name ?? c.a.tab_name).join(" · ")))));
    }
    if (!all.length) {
      cards.push(div().p(12).text_size(12).text_color(t.dim)
        .child("No agents in this space yet. An agent shows up here once it reports its status."));
    }

    // Other spaces with something going on: one quiet line each.
    const others = spaces().filter((s) => !s.active && s.tabs.some((x) => x.status && x.status !== "idle"));
    const footer = others.length ? h_flex().flex_none().flex_wrap().px(12).py(6).gap_x(12).gap_y(3).border_t(1).border_color(t.border).text_size(11).text_color(t.dim)
      .children(others.map((s) => {
        const need = s.tabs.filter((x) => x.status === "blocked").length;
        const work = s.tabs.filter((x) => x.status === "working").length;
        const done = s.tabs.filter((x) => x.status === "done").length;
        const [color, text] = need ? [t.blocked, `${need} needs you`] : work ? [t.working, `${work} working`] : [t.done, `${done} done`];
        return h_flex().id(`sp-${s.id}`).gap(5).items_center().cursor_pointer().rounded(4).px(3).hover((x) => x.bg(t.hover))
          .on_click(() => run("space.select", { id: s.id }))
          .child(div().text_color(t.muted).child(s.name))
          .child(div().size(6).rounded(3).bg(color))
          .child(text);
      })) : null;

    return v_flex().id("space").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .on_mouse_down("left", () => this.handle.focus())
      .size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background).border_1().border_color(t.border).text_size(12.5).text_color(t.foreground)
      .child(header)
      .when(Boolean(this.error), (e) => e.child(div().flex_none().px(12).py(4).text_size(11).text_color(t.ansi1).child(`board: ${this.error}`)))
      .child(v_flex().id("cards").flex_1().min_h(0).p(8).gap(8).overflow_y_scrollbar().track_scroll(this.scroll).children(cards))
      .when(Boolean(footer), (e) => e.child(footer))
      .child(h_flex().flex_none().h(22).px(12).items_center().border_t(1).border_color(t.border).text_size(10.5).text_color(t.dim)
        .child("j/k move · ⏎ go · 1-9 answer · v order · i idle · s spaces"));
  }
}
