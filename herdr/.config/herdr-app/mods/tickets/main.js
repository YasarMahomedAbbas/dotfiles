// Tickets pane (C-f t): the project's GitHub Project board from `lazytickets export`,
// as area → status → tickets. Sub-issues stay in their own column tagged ↑ #parent;
// a parent shows its done/total. A ticket with an `issue-<n>` tab shows that tab's
// live state. Keys: j/k (or ↑/↓, ctrl-j/ctrl-k) move, Enter/space folds a group,
// p cycles presets, / searches (fuzzy title, or #number), f opens the filter panel
// (status / label / assignee checkboxes like the TUI's filter builder: OR within a
// group, AND across; F clears), r refreshes, o opens the ticket on GitHub.
// Folds and the filter are saved per project in localStorage, so they survive
// closing the pane and restarting herdr.
// Start ▸ (Enter or s on a ticket, or the button on the selected row) asks, then runs
// `herd --recipe ticket -- "#<n>"` from the board's folder, detached: the recipe can
// outlast a mod's 30 s exec limit, so its output goes to a log that's watched for the
// exit code. A ticket with a live herd shows Go ▸ instead (`herd go <key>`).
// In the sidebar (no props) it follows the focused terminal's folder, which picks the
// project. As a pane, props { cwd } or { project } pin it.

import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input, Scrollbar, v_virtual_list, VirtualListScrollHandle } from "gpui-base";
import { props, exec, spaces, panes, focused, terminals, theme, notify, nextCommand, home, readTextFile } from "herdr";

const ROW_H = 26;
const LIVE = { working: ["working", "ansi3"], blocked: ["needs you", "ansi1"], done: ["done", "ansi2"], idle: ["idle", "dim"] };

// Same buckets as the lazytickets TUI's status colours.
function statusColor(t, status) {
  const s = (status || "").toLowerCase();
  if (/progress|doing|wip/.test(s)) return t.ansi3;
  if (/done|closed|complete|ship|merged/.test(s)) return t.ansi2;
  if (/review|feedback|test|qa|approv/.test(s)) return t.ansi5;
  if (/block|hold|stuck/.test(s)) return t.ansi1;
  if (/future|backlog/.test(s)) return t.dim;
  return t.ansi4;
}
const foldedByDefault = (status) => /future|done/i.test(status || "");
const DIMS = ["status", "label", "assignee"];
const DIM_LABEL = { status: "Status", label: "Label", assignee: "Assignee" };
const emptyFilter = () => ({ status: new Set(), label: new Set(), assignee: new Set() });
const lc = (s) => (s ?? "").toLowerCase();
// The TUI's `/` is a fuzzy (skim) match: the query's letters in order, gaps allowed.
const fuzzy = (q, s) => { let i = 0; for (const c of s) if (c === q[i]) i++; return i === q.length; };

export default class Tickets extends View {
  init(_props, cx) {
    const p = props() ?? {};
    this.cwd = p.cwd ?? null;
    this.project = p.project ?? null;
    this.follow = !p.cwd && !p.project;
    if (this.follow) this.cwd = this.location();
    this.cacheKey = "export:" + (this.project ?? this.cwd ?? "");
    this.data = null;
    this.error = null;
    this.loading = false;
    this.preset = 0;
    this.folded = new Set();  // saved per project (see loadView/saveView)
    this.filter = emptyFilter(); // f: status / label / assignee checkboxes, saved per project
    this.filtering = false;   // the filter panel is showing instead of the board
    this.fsel = null;         // filter panel row key
    this.fscroll = VirtualListScrollHandle.new();
    this.sel = null;          // row key
    this.query = "";
    this.searching = false;
    this.confirm = null;      // ticket waiting on the Start confirm strip
    this.starting = new Set(); // ticket numbers whose herd is being started
    this.handle = cx.focus_handle();
    this.scroll = VirtualListScrollHandle.new(); // so j/k keep the selection on screen
    this.input = InputState.new({ placeholder: "Search title or #number" });
    this.input.on("change", (_e, cx) => { this.query = this.input.value(); cx.notify(); });
    this.input.on("submit", (_e, cx) => { this.searching = false; this.handle.focus(); cx.notify(); });
    try {
      const cached = localStorage.getItem(this.cacheKey);
      if (cached) this.adopt(JSON.parse(cached));
    } catch (_) {}
    cx.spawn(async (cx) => { for (;;) { const c = await nextCommand(); if (c === "focus") { this.handle.focus(); cx.notify(); } } });
    this.refresh(cx, false);
    // Sidebar copy: follow the focused terminal's folder (checked gently, off the render path).
    if (this.follow) cx.timer.every(800, (cx) => this.followFocus(cx));
  }

  // The focused terminal's folder (else the space's), like the Changes panel does.
  location() {
    const f = focused();
    const pane = f?.pane ? panes().find((x) => x.pane === f.pane) : null;
    const space = spaces().find((x) => x.active);
    return pane?.cwd || f?.cwd || space?.folder || null;
  }

  // Sidebar copy: when the focused folder changes, show that folder's project.
  followFocus(cx) {
    if (!this.follow) return;
    const loc = this.location();
    if (!loc || loc === this.cwd) return;
    this.cwd = loc;
    this.cacheKey = "export:" + loc;
    let cached = null;
    try { cached = JSON.parse(localStorage.getItem(this.cacheKey) || "null"); } catch (_) {}
    if (cached) this.adopt(cached); else { this.data = null; }
    this.error = null;
    this.refresh(cx, false);
  }

  adopt(d) {
    if (this.data?.project !== d.project) {
      this.sel = null; this.fsel = null; this.preset = 0;
      try { const pr = Number(localStorage.getItem("preset:" + d.project)); if (Number.isInteger(pr)) this.preset = pr; } catch (_) {}
      this.loadView(d.project);
    }
    this.data = d;
    // Done / Future start folded. Re-adding is harmless: opening one of those
    // groups is stored as an "open:" override, not by removing this key.
    for (const t of d.tickets) if (foldedByDefault(t.status)) this.folded.add("s:" + (t.status ?? ""));
    if (this.preset >= (d.presets?.length ?? 0)) this.preset = 0;
  }

  // Folds and the filter survive closing the pane: localStorage, per project.
  loadView(project) {
    this.folded = new Set();
    this.filter = emptyFilter();
    try {
      const v = JSON.parse(localStorage.getItem("view:" + project) || "null");
      if (Array.isArray(v?.folded)) this.folded = new Set(v.folded);
      for (const dim of DIMS) if (Array.isArray(v?.filter?.[dim])) this.filter[dim] = new Set(v.filter[dim]);
    } catch (_) {}
  }

  saveView() {
    if (!this.data?.project) return;
    const filter = Object.fromEntries(DIMS.map((dim) => [dim, [...this.filter[dim]]]));
    try { localStorage.setItem("view:" + this.data.project, JSON.stringify({ folded: [...this.folded], filter })); } catch (_) {}
  }

  filterCount() { return DIMS.reduce((n, dim) => n + this.filter[dim].size, 0); }

  // Like the TUI's filter builder: OR within a group, AND across groups.
  keeps(t) {
    const f = this.filter;
    return (!f.status.size || f.status.has(lc(t.status))) &&
      (!f.label.size || (t.labels ?? []).some((l) => f.label.has(lc(l)))) &&
      (!f.assignee.size || (t.assignees ?? []).some((a) => f.assignee.has(lc(a))));
  }

  // The preset's tickets that pass the filter (search not applied).
  visibleTickets() {
    const d = this.data;
    if (!d) return [];
    const preset = d.presets[this.preset];
    const shown = preset ? new Set(preset.tickets) : null;
    return d.tickets.filter((t) => (!shown || shown.has(t.number)) && this.keeps(t));
  }

  // Filter panel rows: a heading per group, then a checkbox per value on the board
  // (within the preset), with how many tickets carry it. Checked values the board
  // no longer has stay listed so they can be unticked.
  filterRows() {
    const d = this.data;
    if (!d) return [];
    const preset = d.presets[this.preset];
    const shown = preset ? new Set(preset.tickets) : null;
    const pool = d.tickets.filter((t) => !shown || shown.has(t.number));
    const values = {
      status: (t) => (t.status ? [t.status] : []),
      label: (t) => t.labels ?? [],
      assignee: (t) => t.assignees ?? [],
    };
    const rows = [];
    if (this.filterCount()) rows.push({ kind: "fclear", key: "fclear" });
    for (const dim of DIMS) {
      const seen = new Map(); // lowercased → { value, count }
      for (const t of pool) for (const v of values[dim](t)) {
        const k = lc(v);
        const e = seen.get(k) ?? { value: v, count: 0 };
        e.count++;
        seen.set(k, e);
      }
      for (const k of this.filter[dim]) if (!seen.has(k)) seen.set(k, { value: k, count: 0 });
      let opts = [...seen.entries()];
      if (dim === "status") {
        const rank = (k) => { const i = d.status_order.findIndex((s) => lc(s) === k); return i < 0 ? 1e9 : i; };
        opts.sort((a, b) => rank(a[0]) - rank(b[0]));
      } else opts.sort((a, b) => b[1].count - a[1].count || a[1].value.localeCompare(b[1].value));
      if (!opts.length) continue;
      rows.push({ kind: "fhead", key: "fh:" + dim, label: DIM_LABEL[dim], n: this.filter[dim].size });
      for (const [k, e] of opts) rows.push({ kind: "fopt", key: `fo:${dim}:${k}`, dim, k, value: e.value, count: e.count, on: this.filter[dim].has(k) });
    }
    return rows;
  }

  toggleFilter(r) {
    if (r.kind === "fclear") { this.filter = emptyFilter(); this.fsel = null; }
    else if (r.kind === "fhead") { if (this.filter[r.key.slice(3)].size) this.filter[r.key.slice(3)] = new Set(); else return; }
    else if (r.kind === "fopt") { const s = this.filter[r.dim]; s.has(r.k) ? s.delete(r.k) : s.add(r.k); }
    else return;
    this.saveView();
  }

  moveFilter(delta) {
    const rows = this.filterRows();
    if (!rows.length) return;
    let i = rows.findIndex((r) => r.key === this.fsel);
    i = i < 0 ? 0 : Math.max(0, Math.min(rows.length - 1, i + delta));
    this.fsel = rows[i].key;
    this.fscroll.scroll_to_item(i);
  }

  openFilter(on) {
    this.filtering = on;
    this.searching = false;
    this.handle.focus();
  }

  // `inRender`: called while drawing, where cx.notify() isn't allowed (the fetch
  // notifies when it lands).
  refresh(cx, force, inRender = false) {
    if (this.loading) { this.again = true; return; }
    this.loading = true;
    if (!inRender) cx.notify();
    const args = ["export", "--json"];
    if (this.project) args.push("--project", this.project);
    if (force) args.push("--refresh");
    cx.spawn(async (cx) => {
      try {
        const r = await exec("lazytickets", args, this.cwd ? { cwd: this.cwd } : {});
        if (r.code === 0) {
          this.adopt(JSON.parse(r.stdout));
          this.error = null;
          try { localStorage.setItem(this.cacheKey, r.stdout); } catch (_) {}
        } else this.error = (r.stderr || r.stdout).trim().replace(/^Error:\s*/, "") || `lazytickets exited with ${r.code}`;
      } catch (e) {
        this.error = "Couldn't run lazytickets: " + e;
      }
      this.loading = false;
      if (this.again) { this.again = false; this.refresh(cx, false); }
      cx.notify();
    });
  }

  // Ticket herds (started by `herd --recipe ticket`) → their state, matched to this
  // board by the ticket URL's repo. herd labels: ticket.ref, ticket.url, herd.state.
  liveStates() {
    const out = {};
    const repos = (this.data?.repos ?? []).map((r) => r.toLowerCase());
    for (const term of terminals()) {
      const l = term.labels ?? {};
      if (l["herd.recipe"] !== "ticket" || !l["ticket.ref"] || term.state !== "live") continue;
      const repo = /github\.com\/([^/]+\/[^/]+)\//.exec(l["ticket.url"] ?? "")?.[1]?.toLowerCase();
      if (repos.length && repo && !repos.includes(repo)) continue;
      const status = typeof term.status === "object" ? term.status?.state : term.status;
      const st = l["herd.state"] === "blocked" || status === "blocked" ? "blocked"
        : l["herd.state"] === "done" || status === "done" ? "done"
        : status === "working" ? "working" : "idle";
      out[l["ticket.ref"]] = { st, key: l["herd.key"] ?? null };
    }
    return out;
  }

  // Start ▸ step 1: the confirm strip. A ticket with a live herd goes there instead.
  askStart(tk, cx) {
    const live = this.liveStates()[String(tk.number)];
    if (live?.key) return this.goTo(live.key);
    if (this.starting.has(tk.number)) return;
    this.confirm = tk;
    this.handle.focus();
  }

  goTo(key) {
    exec("herd", ["go", key], this.cwd ? { cwd: this.cwd } : {})
      .then((r) => { if (r.code !== 0) notify({ title: "herd go", body: (r.stderr || r.stdout).trim(), level: "error" }); })
      .catch((e) => notify({ title: "herd go", body: String(e), level: "error" }));
  }

  // Start ▸ step 2: run the ticket recipe detached, then watch its log for the exit code.
  start(tk, cx) {
    this.confirm = null;
    if (!this.cwd) { notify({ title: "Start pipeline", body: "No folder to start from", level: "error" }); return; }
    const n = tk.number;
    const log = `${home()}/.cache/herd/start-${(this.data?.project ?? "board").replace(/[^\w.-]/g, "_")}-${n}.log`;
    const script = 'mkdir -p "${2%/*}"; herd --recipe ticket -- "$1" >"$2" 2>&1; echo "herd-exit=$?" >>"$2"';
    this.starting.add(n);
    cx.spawn(async (cx) => {
      try {
        const r = await exec("setsid", ["-f", "sh", "-c", script, "start", "#" + n, log], { cwd: this.cwd });
        if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim() || `exit ${r.code}`);
      } catch (e) {
        this.starting.delete(n);
        notify({ title: `#${n}: couldn't start herd`, body: String(e), level: "error" });
        cx.notify();
        return;
      }
      notify({ title: `Starting #${n}`, body: tk.title, timeout: 2500 });
      cx.notify();
      const began = Date.now();
      const watch = cx.timer.every(2000, (cx) => {
        readTextFile(log).then((text) => {
          const m = /herd-exit=(\d+)\s*$/.exec(text ?? "");
          if (!m && Date.now() - began < 10 * 60 * 1000) return;
          watch.cancel();
          this.starting.delete(n);
          if (!m) notify({ title: `#${n}: herd is taking long`, body: "See " + log, level: "warning" });
          else if (m[1] !== "0") {
            const tail = (text ?? "").replace(/herd-exit=\d+\s*$/, "").trim().split("\n").slice(-4).join("\n");
            notify({ title: `#${n}: herd failed`, body: tail || "See " + log, level: "error" });
          }
          cx.notify();
        }).catch(() => {});
      });
    });
  }

  rows() {
    const d = this.data;
    if (!d) return [];
    const q = this.query.trim().toLowerCase();
    const digits = /^#?\d+$/.test(q) ? q.replace(/^#/, "") : null;
    const fq = q.replace(/\s+/g, "");
    const byN = new Map(d.tickets.map((t) => [t.number, t]));
    const tickets = this.visibleTickets().filter((t) => !q ||
      (digits ? String(t.number).startsWith(digits) : fuzzy(fq, t.title.toLowerCase())));

    const order = [...d.status_order];
    for (const t of tickets) if (!order.some((s) => s.toLowerCase() === (t.status ?? "").toLowerCase())) order.push(t.status ?? "");
    const areas = d.areas.length ? [...d.areas, "Other"] : [null];
    const searching = Boolean(q);
    const rows = [];
    for (const area of areas) {
      const inArea = tickets.filter((t) => !area || t.area === area);
      if (!inArea.length) continue;
      let depth = 0;
      if (area) {
        const key = "a:" + area;
        rows.push({ kind: "area", key, label: area, count: this.countLabel(inArea), depth: 0 });
        if (this.folded.has(key) && !searching) continue;
        depth = 1;
      }
      for (const status of order) {
        const inStatus = inArea.filter((t) => (t.status ?? "").toLowerCase() === status.toLowerCase());
        if (!inStatus.length) continue;
        const key = (area ? "a:" + area + "/" : "") + "s:" + status;
        const foldKey = "s:" + status;
        const folded = (this.folded.has(key) || (this.folded.has(foldKey) && !this.folded.has("open:" + key))) && !searching;
        rows.push({ kind: "status", key, foldKey, label: status || "No status", count: inStatus.length, depth, folded });
        if (folded) continue;
        for (const t of inStatus) rows.push({ kind: "ticket", key: "t:" + t.number + "@" + key, t, parent: t.parent ? byN.get(t.parent) : null, depth: depth + 1 });
      }
    }
    return rows;
  }

  countLabel(list) {
    const open = list.filter((t) => !t.done && !/future/i.test(t.status ?? "")).length;
    const fut = list.filter((t) => /future/i.test(t.status ?? "")).length;
    return `${open} open` + (fut ? ` · ${fut} future` : "");
  }

  isFolded(r) {
    if (r.kind === "area") return this.folded.has(r.key);
    return r.folded;
  }

  toggle(r) {
    this.toggleFold(r);
    this.saveView();
  }

  toggleFold(r) {
    if (r.kind === "area") { this.folded.has(r.key) ? this.folded.delete(r.key) : this.folded.add(r.key); return; }
    if (r.kind !== "status") return;
    if (r.folded) {
      // Opening: clear an explicit fold, and override a default fold for this group.
      this.folded.delete(r.key);
      if (this.folded.has(r.foldKey)) this.folded.add("open:" + r.key);
    } else {
      this.folded.delete("open:" + r.key);
      this.folded.add(r.key);
    }
  }

  move(delta) {
    const rows = this.rows();
    if (!rows.length) return;
    let i = rows.findIndex((r) => r.key === this.sel);
    i = i < 0 ? 0 : Math.max(0, Math.min(rows.length - 1, i + delta));
    this.select(rows, i);
  }

  // A click on a row (the list's on_item_click): a group folds; a ticket is selected,
  // and clicking the selected ticket (its Start ▸ / Go ▸ label included) starts it.
  clicked(key, cx) {
    if (this.filtering) {
      const r = this.filterRows().find((x) => x.key === key);
      if (r) { this.fsel = key; this.toggleFilter(r); }
      this.handle.focus();
      cx.notify();
      return;
    }
    const r = this.rows().find((x) => x.key === key);
    if (!r) return;
    if (r.kind !== "ticket") { this.sel = key; this.toggle(r); }
    else if (this.sel === key) this.askStart(r.t, cx);
    else this.sel = key;
    this.handle.focus();
    cx.notify();
  }

  // Select row i and bring it on screen.
  select(rows, i) {
    if (!rows[i]) return;
    this.sel = rows[i].key;
    this.scroll.scroll_to_item(i);
  }

  openOnGitHub(t) {
    if (t?.url) exec("xdg-open", [t.url]).catch(() => {});
  }

  key(e, cx) {
    if (this.searching) {
      if (e.keystroke === "escape") { this.searching = false; this.query = ""; this.input.set_value?.(""); this.handle.focus(); cx.stop_propagation(); cx.notify(); }
      return;
    }
    if (this.confirm) {
      switch (e.keystroke) {
        case "enter": case "y": this.start(this.confirm, cx); break;
        case "escape": case "n": case "q": this.confirm = null; break;
        default: return;
      }
      cx.stop_propagation();
      cx.notify();
      return;
    }
    if (this.filtering) {
      const fr = this.filterRows();
      const fcur = fr.find((r) => r.key === this.fsel);
      switch (e.keystroke) {
        case "j": case "down": case "ctrl-j": this.moveFilter(1); break;
        case "k": case "up": case "ctrl-k": this.moveFilter(-1); break;
        case "g": if (fr[0]) { this.fsel = fr[0].key; this.fscroll.scroll_to_item(0); } break;
        case "shift-g": if (fr.length) { this.fsel = fr[fr.length - 1].key; this.fscroll.scroll_to_item(fr.length - 1); } break;
        case "space": case "enter": case "x": if (fcur) this.toggleFilter(fcur); break;
        case "c": case "shift-f": this.filter = emptyFilter(); this.saveView(); break;
        case "escape": case "f": case "q": this.openFilter(false); break;
        default: return;
      }
      cx.stop_propagation();
      cx.notify();
      return;
    }
    const rows = this.rows();
    const cur = rows.find((r) => r.key === this.sel);
    switch (e.keystroke) {
      case "enter": case "s": if (cur?.kind === "ticket") { this.askStart(cur.t, cx); break; } if (e.keystroke === "s") return;
        if (cur) this.toggle(cur); break;
      case "j": case "down": case "ctrl-j": this.move(1); break;
      case "k": case "up": case "ctrl-k": this.move(-1); break;
      case "g": this.select(rows, 0); break;
      case "shift-g": this.select(rows, rows.length - 1); break;
      case "space": case "z": if (cur && cur.kind !== "ticket") this.toggle(cur); break;
      case "p": if (this.data?.presets.length) { this.preset = (this.preset + 1) % this.data.presets.length; this.savePreset(); } break;
      case "shift-p": if (this.data?.presets.length) { this.preset = (this.preset + this.data.presets.length - 1) % this.data.presets.length; this.savePreset(); } break;
      case "r": this.refresh(cx, true); break;
      case "o": if (cur?.kind === "ticket") this.openOnGitHub(cur.t); break;
      case "/": this.searching = true; this.input.focus(); break;
      case "f": this.openFilter(true); break;
      case "shift-f": if (!this.filterCount()) return; this.filter = emptyFilter(); this.saveView(); break;
      default: return;
    }
    cx.stop_propagation();
    cx.notify();
  }

  savePreset() { try { localStorage.setItem("preset:" + (this.data?.project ?? ""), String(this.preset)); } catch (_) {} }

  render(cx) {
    const t = theme();
    const d = this.data;
    const rows = this.rows();
    const live = this.liveStates();
    if (this.sel && !rows.some((r) => r.key === this.sel)) this.sel = rows[0]?.key ?? null;
    const focused = this.handle.is_focused?.() ?? true;

    const header = h_flex().flex_none().h(42).px(14).gap(8).items_center().border_b(1).border_color(t.border)
      .child(div().font_semibold().text_color(t.foreground).truncate().child(d ? d.project : "Tickets"))
      .when(Boolean(d), (e) => e.child(div().text_size(11.5).text_color(t.dim).truncate().child(this.countLabel(this.visibleTickets()))))
      .child(div().flex_1())
      .when(this.loading, (e) => e.child(div().text_size(11).text_color(t.dim).child("refreshing…")))
      .when(Boolean(d), (e) => {
        const n = this.filterCount();
        const on = n > 0 || this.filtering;
        return e.child(h_flex().id("filter").flex_none().h(22).px(8).gap(4).items_center().rounded(5).border_1()
          .border_color(on ? t.accent : t.border).text_size(11.5).text_color(on ? t.accent : t.muted)
          .cursor_pointer().hover((s) => s.bg(t.hover))
          .on_click((_e, cx) => { this.openFilter(!this.filtering); cx.notify(); })
          .child(n ? `filter · ${n}` : "filter"));
      })
      .when(Boolean(d?.presets.length), (e) => e.child(
        h_flex().id("preset").h(22).px(8).gap(4).items_center().rounded(5).border_1().border_color(t.border).text_size(11.5).text_color(t.muted)
          .cursor_pointer().hover((s) => s.bg(t.hover))
          .on_click((_e, cx) => { this.preset = (this.preset + 1) % d.presets.length; this.savePreset(); cx.notify(); })
          .child(d.presets[this.preset]?.name ?? "") .child(div().text_color(t.dim).child("▾"))));

    const search = this.searching || this.query
      ? h_flex().flex_none().px(10).py(6).border_b(1).border_color(t.border)
          .child(Input.new(this.input).h(26).px(8).rounded(6).border_1().border_color(this.searching ? t.accent : t.border).bg(t.background).text_size(12).text_color(t.foreground))
      : null;

    const row = (r, i) => {
      const sel = r.key === this.sel && focused;
      const pad = 6 + r.depth * 16;
      let el = h_flex().id(r.key).h(ROW_H).pl(pad).pr(10).gap(7).items_center().rounded(5).cursor_pointer()
        .bg(r.key === this.sel ? t.selected : t.background).hover((s) => s.bg(r.key === this.sel ? t.selected : t.hover));
      // No on_click here: a virtual list's rows can't carry handlers (it throws and the
      // row isn't drawn). Clicks go through the list's on_item_click (clicked()).
      if (r.kind === "area" || r.kind === "status") {
        const open = !this.isFolded(r);
        el = el.child(div().w(10).flex_none().text_size(9).text_color(t.dim).child(open ? "▾" : "▸"));
        if (r.kind === "status") el = el.child(div().size(8).flex_none().rounded(4).bg(statusColor(t, r.label)));
        return el.child(div().flex_none().text_color(t.foreground).when(r.kind === "area", (x) => x.font_semibold()).when(r.kind === "status", (x) => x.font_medium()).child(r.label))
          .child(div().flex_none().text_size(11.5).text_color(t.dim).child(String(r.count)));
      }
      const tk = r.t;
      el = el.child(div().w(10).flex_none())
        .child(div().flex_none().text_size(11.5).text_color(t.dim).child("#" + tk.number))
        .child(div().flex_1().min_w(0).truncate().text_color(tk.done ? t.dim : t.foreground).child(tk.title));
      if (tk.sub_issues.length) {
        const pct = Math.round((100 * tk.sub_done) / tk.sub_issues.length);
        el = el.child(h_flex().flex_none().gap(5).items_center().text_size(11).text_color(t.dim)
          .child(div().w(34).h(4).rounded(2).bg(t.border).child(div().h_full().rounded(2).bg(t.ansi2).w(Math.round(34 * pct / 100))))
          .child(`${tk.sub_done}/${tk.sub_issues.length}`));
      }
      if (tk.parent) el = el.child(div().flex_none().px(5).rounded(8).border_1().border_color(t.border).text_size(10.5).text_color(t.dim).child("↑ #" + tk.parent));
      const lv = live[String(tk.number)];
      if (lv) { const [w, c] = LIVE[lv.st] ?? [lv.st, "dim"]; el = el.child(h_flex().flex_none().gap(5).items_center().text_size(11).text_color(t.dim).child(div().size(7).rounded(4).bg(t[c] ?? t.dim)).child(w)); }
      else if (this.starting.has(tk.number)) el = el.child(div().flex_none().text_size(11).text_color(t.dim).child("starting…"));
      if (r.key === this.sel && !this.starting.has(tk.number) && (!lv || lv.key)) {
        // Clicking the selected row (this label included) starts: see clicked().
        el = el.child(h_flex().flex_none().h(18).px(7).items_center().rounded(4).border_1().border_color(t.accent)
          .text_size(11).text_color(t.accent)
          .child(lv ? "Go ▸" : "Start ▸"));
      }
      return el;
    };

    // Filter panel row. Same rule as the board: no on_click on virtual-list rows.
    const frow = (r) => {
      const sel = r.key === this.fsel;
      const el = h_flex().id(r.key).h(ROW_H).px(10).gap(7).items_center().rounded(5).cursor_pointer()
        .bg(sel ? t.selected : t.background).hover((s) => s.bg(sel ? t.selected : t.hover));
      if (r.kind === "fclear") return el.text_color(t.accent).text_size(11.5).child("✕  Clear all filters");
      if (r.kind === "fhead") return el.child(div().font_semibold().text_color(t.foreground).child(r.label))
        .when(r.n > 0, (x) => x.child(div().text_size(11).text_color(t.dim).child(`${r.n} on · ⏎ clears`)));
      return el.pl(22)
        .child(h_flex().size(13).flex_none().rounded(3).border_1().border_color(r.on ? t.accent : t.input ?? t.border)
          .bg(r.on ? t.accent : t.background).text_size(10).text_color(t.background).items_center().justify_center().child(r.on ? "✓" : ""))
        .when(r.dim === "status", (x) => x.child(div().size(8).flex_none().rounded(4).bg(statusColor(t, r.value))))
        .child(div().flex_1().min_w(0).truncate().text_color(r.count ? t.foreground : t.dim).child(r.value))
        .child(div().flex_none().text_size(11).text_color(t.dim).child(String(r.count)));
    };

    let body;
    if (!d && this.error) body = div().p(14).text_color(t.muted).child(this.error);
    else if (!d) body = div().p(14).text_color(t.dim).child("Loading the board…");
    else if (this.filtering) {
      const fr = this.filterRows();
      if (this.fsel && !fr.some((r) => r.key === this.fsel)) this.fsel = fr[0]?.key ?? null;
      if (!this.fsel) this.fsel = fr[0]?.key ?? null;
      body = div().flex_1().min_h(0).relative().px(4).py(2)
        .child(v_virtual_list("tickets-filter", fr.length, ROW_H, (i) => fr[i].key,
          (range) => fr.slice(range.start, range.end).map((r) => frow(r)))
          .on_item_click((key, cx) => this.clicked(key, cx)).track_scroll(this.fscroll).size_full())
        .child(Scrollbar.vertical("tickets-filter").viewport_from_layout().absolute().inset_0());
    }
    else if (!rows.length) body = div().p(14).text_color(t.dim).child(this.query ? "Nothing matches" : this.filterCount() ? "No tickets match the filter (f to change, F clears)" : "No tickets in this preset");
    else body = div().flex_1().min_h(0).relative().px(4).py(2)
      .child(v_virtual_list("tickets-list", rows.length, ROW_H, (i) => rows[i].key,
        (range) => rows.slice(range.start, range.end).map((r, k) => row(r, range.start + k)))
        .on_item_click((key, cx) => this.clicked(key, cx)).track_scroll(this.scroll).size_full())
      .child(Scrollbar.vertical("tickets-list").viewport_from_layout().absolute().inset_0());

    return v_flex().id("tickets").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .on_mouse_down("left", () => { if (!this.searching) this.handle.focus(); })
      .size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background).border_1().border_color(t.border).text_size(12.5).text_color(t.foreground)
      .child(header)
      .when(Boolean(search), (e) => e.child(search))
      .when(Boolean(d && this.error), (e) => e.child(div().flex_none().px(12).py(4).text_size(11).text_color(t.ansi1).child(this.error)))
      .child(body)
      .when(Boolean(this.confirm), (e) => {
        const tk = this.confirm;
        const btn = (id, label, primary, onClick) => h_flex().id(id).h(24).px(10).items_center().rounded(6).cursor_pointer()
          .border_1().border_color(primary ? t.accent : t.border).bg(primary ? t.accent : t.raised)
          .text_color(primary ? t.background : t.foreground).text_size(11.5).hover((s) => s.opacity(0.88)).on_click(onClick).child(label);
        return e.child(v_flex().flex_none().px(12).py(8).gap(6).border_t(1).border_color(t.accent).bg(t.raised)
          .child(div().truncate().text_color(t.foreground).font_medium().child(`#${tk.number} ${tk.title}`))
          .child(div().text_size(11.5).text_color(t.muted).child(`Starts ${d?.skill ? "/" + d.skill + " " : "the pipeline on "}#${tk.number} in a herd (new tab, worktree included)`))
          .child(h_flex().gap(8).justify_end()
            .child(btn("confirm-no", "Cancel  esc", false, (_e, cx) => { this.confirm = null; cx.notify(); }))
            .child(btn("confirm-yes", "Start pipeline  ⏎", true, (_e, cx) => { this.start(tk, cx); cx.notify(); }))));
      })
      .child(h_flex().flex_none().h(22).px(12).items_center().border_t(1).border_color(t.border).text_size(10.5).text_color(t.dim)
        .child(this.filtering ? "j/k move · space toggle · c clear · esc/f done"
          : "j/k move · ⏎ start/fold · p preset · f filter · / search · r refresh · o GitHub"));
  }
}
