// Tickets pane (C-f t): the project's GitHub Project board from `lazytickets export`,
// as area → status → tickets. Sub-issues stay in their own column tagged ↑ #parent;
// a parent shows its done/total. A ticket with an `issue-<n>` tab shows that tab's
// live state. Keys: j/k (or ↑/↓, ctrl-j/ctrl-k) move, Enter/space folds a group,
// p cycles presets, / searches, r refreshes, o opens the ticket on GitHub.
// In the sidebar (no props) it follows the focused terminal's folder, which picks the
// project. As a pane, props { cwd } or { project } pin it.

import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { props, exec, spaces, panes, focused, terminals, theme, notify, nextCommand } from "herdr";

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
    this.folded = new Set();
    this.foldedSeeded = false;
    this.sel = null;          // row key
    this.query = "";
    this.searching = false;
    this.handle = cx.focus_handle();
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
    if (this.data?.project !== d.project) { this.foldedSeeded = false; this.folded = new Set(); this.sel = null; this.preset = 0;
      try { const pr = Number(localStorage.getItem("preset:" + d.project)); if (Number.isInteger(pr)) this.preset = pr; } catch (_) {} }
    this.data = d;
    if (!this.foldedSeeded) {
      for (const t of d.tickets) if (foldedByDefault(t.status)) this.folded.add("s:" + (t.status ?? ""));
      this.foldedSeeded = true;
    }
    if (this.preset >= (d.presets?.length ?? 0)) this.preset = 0;
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
      out[l["ticket.ref"]] = st;
    }
    return out;
  }

  rows() {
    const d = this.data;
    if (!d) return [];
    const preset = d.presets[this.preset];
    const shown = preset ? new Set(preset.tickets) : null;
    const q = this.query.trim().toLowerCase().replace(/^#/, "");
    const byN = new Map(d.tickets.map((t) => [t.number, t]));
    const tickets = d.tickets.filter((t) => (!shown || shown.has(t.number)) &&
      (!q || t.title.toLowerCase().includes(q) || String(t.number).startsWith(q)));

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
    this.sel = rows[i].key;
  }

  openOnGitHub(t) {
    if (t?.url) exec("xdg-open", [t.url]).catch(() => {});
  }

  key(e, cx) {
    if (this.searching) {
      if (e.keystroke === "escape") { this.searching = false; this.query = ""; this.input.set_value?.(""); this.handle.focus(); cx.stop_propagation(); cx.notify(); }
      return;
    }
    const rows = this.rows();
    const cur = rows.find((r) => r.key === this.sel);
    switch (e.keystroke) {
      case "j": case "down": case "ctrl-j": this.move(1); break;
      case "k": case "up": case "ctrl-k": this.move(-1); break;
      case "g": this.sel = rows[0]?.key ?? null; break;
      case "shift-g": this.sel = rows[rows.length - 1]?.key ?? null; break;
      case "enter": case "space": case "z": if (cur && cur.kind !== "ticket") this.toggle(cur); break;
      case "p": if (this.data?.presets.length) { this.preset = (this.preset + 1) % this.data.presets.length; this.savePreset(); } break;
      case "shift-p": if (this.data?.presets.length) { this.preset = (this.preset + this.data.presets.length - 1) % this.data.presets.length; this.savePreset(); } break;
      case "r": this.refresh(cx, true); break;
      case "o": if (cur?.kind === "ticket") this.openOnGitHub(cur.t); break;
      case "/": this.searching = true; this.input.focus(); break;
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
      .when(Boolean(d), (e) => e.child(div().text_size(11.5).text_color(t.dim).child(this.countLabel(d.tickets.filter((x) => d.presets[this.preset]?.tickets.includes(x.number) ?? true)))))
      .child(div().flex_1())
      .when(this.loading, (e) => e.child(div().text_size(11).text_color(t.dim).child("refreshing…")))
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
        .bg(r.key === this.sel ? t.selected : t.background).hover((s) => s.bg(r.key === this.sel ? t.selected : t.hover))
        .on_click((_e, cx) => { this.sel = r.key; if (r.kind !== "ticket") this.toggle(r); this.handle.focus(); cx.notify(); });
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
      const st = live[String(tk.number)];
      if (st) { const [w, c] = LIVE[st] ?? [st, "dim"]; el = el.child(h_flex().flex_none().gap(5).items_center().text_size(11).text_color(t.dim).child(div().size(7).rounded(4).bg(t[c] ?? t.dim)).child(w)); }
      return el;
    };

    let body;
    if (!d && this.error) body = div().p(14).text_color(t.muted).child(this.error);
    else if (!d) body = div().p(14).text_color(t.dim).child("Loading the board…");
    else if (!rows.length) body = div().p(14).text_color(t.dim).child(this.query ? "Nothing matches" : "No tickets in this preset");
    else body = v_flex().id("tickets-list").flex_1().min_h(0).overflow_y_scrollbar().px(4).py(2).children(rows.map((r, i) => row(r, i)));

    return v_flex().id("tickets").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .on_mouse_down("left", () => { if (!this.searching) this.handle.focus(); })
      .size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background).border_1().border_color(t.border).text_size(12.5).text_color(t.foreground)
      .child(header)
      .when(Boolean(search), (e) => e.child(search))
      .when(Boolean(d && this.error), (e) => e.child(div().flex_none().px(12).py(4).text_size(11).text_color(t.ansi1).child(this.error)))
      .child(body)
      .child(h_flex().flex_none().h(22).px(12).items_center().border_t(1).border_color(t.border).text_size(10.5).text_color(t.dim)
        .child("j/k move · enter fold · p preset · / search · r refresh · o GitHub"));
  }
}
