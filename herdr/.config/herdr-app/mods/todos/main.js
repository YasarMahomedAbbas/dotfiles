// Todos pane (C-f d, or the Todos button): my reminders and to-dos from the personal
// assistant (assistant.draculhome.org), read through `pa` (~/.claude/skills/assistant/pa),
// which holds the Cloudflare Access token, so nothing secret lives here. Writes go through
// the same API as the phone, so they get Undo and refresh the phone.
// Views: Today (overdue first, then today's to-dos, reminders and calendar events),
// Week (the week's to-dos, then each day), Someday (by tag).
// Keys: j/k move, x/space tick, a add (the server reads a "17:30" / "fri" prefix),
// tab or 1/2/3 switch view, h shows/hides done, o opens the linked vault note, r refreshes.
// Without pa or its token (the work PC) it never runs pa; my-tabs hides it there too.

import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input, Scrollbar, v_virtual_list, VirtualListScrollHandle } from "gpui-base";
import { exec, theme, notify, nextCommand, home } from "herdr";

const ROW_H = 26;
const HEAD_H = 30;
const VIEWS = [["today", "Today"], ["week", "Week"], ["someday", "Someday"]];
const POLL_MS = 60 * 1000;
const VAULT = "My-Vault";

const DAY = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function dayLabel(iso, today) {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  const s = `${DAY[dt.getUTCDay()]} ${d} ${MON[m - 1]}`;
  return iso === today ? `Today · ${s}` : s;
}
const hhmm = (s) => (s ? String(s).slice(0, 5) : "");
// Event times may be ISO datetimes or plain HH:MM.
const evTime = (s) => (!s ? "…" : /T\d\d:\d\d/.test(s) ? s.split("T")[1].slice(0, 5) : hhmm(s));

export default class Todos extends View {
  init(_props, cx) {
    this.pa = home() + "/.claude/skills/assistant/pa";
    this.view = 0;
    this.data = {};           // view name → last answer
    this.error = null;
    this.loading = false;
    this.showDone = false;
    this.sel = null;
    this.adding = false;
    this.handle = cx.focus_handle();
    this.scroll = VirtualListScrollHandle.new(); // so j/k keep the selection on screen
    this.input = InputState.new({ placeholder: "Add…  e.g. 17:30 call mum, fri buy stamps" });
    this.input.on("submit", (_e, cx) => this.add(cx));
    try {
      const v = Number(localStorage.getItem("view"));
      if (Number.isInteger(v) && v >= 0 && v < VIEWS.length) this.view = v;
      this.showDone = localStorage.getItem("showDone") === "1";
      for (const [name] of VIEWS) { const c = localStorage.getItem("view:" + name); if (c) this.data[name] = JSON.parse(c); }
    } catch (_) {}
    cx.spawn(async (cx) => { for (;;) { const c = await nextCommand(); if (c === "focus") { this.handle.focus(); cx.notify(); } } });
    this.available = null; // unknown until the check below
    cx.spawn(async (cx) => {
      const r = await exec("sh", ["-c", 'test -f "$1" && test -x "$2"', "sh",
        home() + "/.config/assistant/token.env", this.pa]).catch(() => ({ code: 1 }));
      this.available = r.code === 0;
      if (this.available) this.refresh(cx);
      cx.notify();
    });
    cx.timer.every(POLL_MS, (cx) => this.refresh(cx)); // refresh() skips itself until available
  }

  get name() { return VIEWS[this.view][0]; }

  refresh(cx, inRender = false) {
    if (!this.available) return;
    if (this.loading) { this.again = true; return; }
    this.loading = true;
    const name = this.name;
    if (!inRender) cx.notify();
    cx.spawn(async (cx) => {
      try {
        const r = await exec(this.pa, ["get", `/api/reminders?view=${name}`]);
        if (r.code === 0) {
          this.data[name] = JSON.parse(r.stdout);
          this.error = null;
          try { localStorage.setItem("view:" + name, r.stdout); } catch (_) {}
        } else this.error = (r.stderr || r.stdout).trim().replace(/^pa:\s*/, "") || `pa exited with ${r.code}`;
      } catch (e) {
        this.error = "Couldn't run pa: " + e;
      }
      this.loading = false;
      if (this.again) { this.again = false; this.refresh(cx); }
      cx.notify();
    });
  }

  setView(i, cx) {
    this.view = (i + VIEWS.length) % VIEWS.length;
    this.sel = null;
    try { localStorage.setItem("view", String(this.view)); } catch (_) {}
    this.refresh(cx);
  }

  rows() {
    const d = this.data[this.name];
    if (!d) return [];
    const keep = (it) => this.showDone || it.status !== "done";
    const rows = [];
    const section = (key, label, items, events = [], tone = null) => {
      const shown = items.filter(keep);
      if (!shown.length && !events.length) return;
      rows.push({ kind: "head", key: "h:" + key, label, count: shown.filter((x) => x.status !== "done").length, tone });
      for (const ev of events) rows.push({ kind: "event", key: `e:${key}:${ev.title}:${ev.start}`, ev });
      for (const it of shown) rows.push({ kind: "item", key: "i:" + it.id, it });
    };
    section("overdue", "Overdue", d.overdue ?? [], [], "ansi1");
    if (this.name === "someday") {
      const byTag = new Map();
      for (const it of d.someday ?? []) { const k = it.tag || "untagged"; if (!byTag.has(k)) byTag.set(k, []); byTag.get(k).push(it); }
      for (const [tag, items] of byTag) section("t:" + tag, "#" + tag, items);
    } else {
      section("week", "This week", d.week ?? []);
      for (const day of d.days ?? []) section("d:" + day.date, dayLabel(day.date, d.today), day.items ?? [], day.events ?? [], day.date === d.today ? "accent" : null);
    }
    return rows;
  }

  counts() {
    const d = this.data[this.name];
    if (!d) return null;
    const all = [...(d.overdue ?? []), ...(d.week ?? []), ...(d.someday ?? []), ...(d.days ?? []).flatMap((x) => x.items ?? [])];
    return { open: all.filter((x) => x.status !== "done").length, done: all.filter((x) => x.status === "done").length, overdue: (d.overdue ?? []).length };
  }

  move(delta) {
    const rows = this.rows().filter((r) => r.kind === "item");
    if (!rows.length) return;
    let i = rows.findIndex((r) => r.key === this.sel);
    i = i < 0 ? 0 : Math.max(0, Math.min(rows.length - 1, i + delta));
    this.select(rows[i]);
  }

  // A click on a row (the list's on_item_click): selects an item; clicking the
  // selected item ticks it. Headings and events do nothing.
  clicked(key, cx) {
    const r = this.rows().find((x) => x.key === key);
    if (r?.kind !== "item") return;
    if (this.sel === key) this.tick(r.it, cx);
    else this.sel = key;
    this.handle.focus();
    cx.notify();
  }

  // Select an item row and bring it on screen (the list also holds headings and events).
  select(r) {
    if (!r) return;
    this.sel = r.key;
    const i = this.rows().findIndex((x) => x.key === r.key);
    if (i >= 0) this.scroll.scroll_to_item(i);
  }

  tick(it, cx) {
    if (!it?.tickable) return;
    const done = it.status !== "done";
    it.status = done ? "done" : "open"; // shown at once; the refresh brings the server's row
    cx.notify();
    cx.spawn(async (cx) => {
      try {
        const r = await exec(this.pa, [done ? "done" : "undone", it.id]);
        if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim());
      } catch (e) {
        notify({ title: "Todos", body: `Couldn't ${done ? "tick" : "untick"} “${it.title}”: ${e.message ?? e}`, level: "error" });
      }
      this.refresh(cx);
    });
  }

  add(cx) {
    const text = this.input.value().trim();
    this.adding = false;
    this.input.set_value("");
    this.handle.focus();
    cx.notify();
    if (!text) return;
    const args = ["add", text];
    if (this.name === "week") args.push("bucket=week");
    if (this.name === "someday") args.push("bucket=someday");
    cx.spawn(async (cx) => {
      try {
        const r = await exec(this.pa, args);
        if (r.code !== 0) throw new Error((r.stderr || r.stdout).trim());
      } catch (e) {
        notify({ title: "Todos", body: `Couldn't add “${text}”: ${e.message ?? e}`, level: "error" });
      }
      this.refresh(cx);
    });
  }

  openNote(it) {
    if (!it?.note?.path) return;
    const url = `obsidian://open?vault=${encodeURIComponent(VAULT)}&file=${encodeURIComponent(it.note.path)}`;
    exec("xdg-open", [url]).catch(() => {});
  }

  key(e, cx) {
    if (this.adding) {
      if (e.keystroke === "escape") { this.adding = false; this.input.set_value(""); this.handle.focus(); cx.stop_propagation(); cx.notify(); }
      return;
    }
    const rows = this.rows().filter((r) => r.kind === "item");
    const cur = rows.find((r) => r.key === this.sel)?.it;
    switch (e.keystroke) {
      case "j": case "down": case "ctrl-j": this.move(1); break;
      case "k": case "up": case "ctrl-k": this.move(-1); break;
      case "g": this.select(rows[0]); break;
      case "shift-g": this.select(rows[rows.length - 1]); break;
      case "x": case "space": case "enter": this.tick(cur, cx); break;
      case "a": this.adding = true; this.input.focus(); break;
      case "tab": this.setView(this.view + 1, cx); break;
      case "shift-tab": this.setView(this.view - 1, cx); break;
      case "h": this.showDone = !this.showDone; try { localStorage.setItem("showDone", this.showDone ? "1" : "0"); } catch (_) {} break;
      case "1": case "2": case "3": this.setView(Number(e.keystroke) - 1, cx); break;
      case "o": this.openNote(cur); break;
      case "r": this.refresh(cx); break;
      default: return;
    }
    cx.stop_propagation();
    cx.notify();
  }

  render(cx) {
    const t = theme();
    const d = this.data[this.name];
    const rows = this.rows();
    const items = rows.filter((r) => r.kind === "item");
    if (this.sel && !items.some((r) => r.key === this.sel)) this.sel = items[0]?.key ?? null;
    const focused = this.handle.is_focused?.() ?? true;
    const c = this.counts();

    const tab = (i, label) => {
      const on = i === this.view;
      return h_flex().id("view-" + i).h(22).px(8).items_center().rounded(5).cursor_pointer().text_size(11.5)
        .bg(on ? t.selected : t.background).text_color(on ? t.foreground : t.muted).hover((s) => s.bg(on ? t.selected : t.hover))
        .on_click((_e, cx) => { this.setView(i, cx); this.handle.focus(); cx.notify(); }).child(label);
    };
    const header = h_flex().flex_none().h(42).px(10).gap(4).items_center().border_b(1).border_color(t.border)
      .children(VIEWS.map(([, label], i) => tab(i, label)))
      .child(div().flex_1())
      .when(this.loading, (e) => e.child(div().text_size(11).text_color(t.dim).child("refreshing…")))
      .when(Boolean(c) && !this.loading, (e) => e.child(div().text_size(11.5).text_color(c.overdue ? t.ansi1 : t.dim)
        .child(`${c.open} open` + (c.overdue ? ` · ${c.overdue} overdue` : "") + (c.done ? ` · ${c.done} done` : ""))));

    const addBar = h_flex().flex_none().px(10).py(6).border_b(1).border_color(t.border)
      .child(Input.new(this.input).h(26).px(8).rounded(6).border_1().border_color(this.adding ? t.accent : t.border).bg(t.background).text_size(12).text_color(t.foreground));

    const row = (r) => {
      if (r.kind === "head") {
        return h_flex().id(r.key).h(HEAD_H).px(8).pt(4).gap(7).items_center()
          .child(div().flex_none().font_semibold().text_color(r.tone ? t[r.tone] ?? t.foreground : t.foreground).child(r.label))
          .when(r.count > 0, (e) => e.child(div().flex_none().text_size(11.5).text_color(t.dim).child(String(r.count))));
      }
      if (r.kind === "event") {
        const ev = r.ev;
        return h_flex().id(r.key).h(ROW_H).pl(14).pr(10).gap(8).items_center()
          .child(div().w(3).h(14).flex_none().rounded(2).bg(t.ansi4))
          .child(div().flex_none().text_size(11.5).text_color(t.dim).child(ev.all_day ? "all day" : `${evTime(ev.start)}–${evTime(ev.end)}`))
          .child(div().flex_1().min_w(0).truncate().text_color(t.muted).child(ev.title ?? "(busy)"));
      }
      const it = r.it;
      const done = it.status === "done";
      const sel = r.key === this.sel;
      return h_flex().id(r.key).h(ROW_H).pl(10).pr(10).gap(8).items_center().rounded(5).cursor_pointer()
        .bg(sel && focused ? t.selected : t.background).hover((s) => s.bg(sel && focused ? t.selected : t.hover))
        // No on_click here: a virtual list's rows can't carry handlers (it throws and the
        // row isn't drawn). Clicks go through the list's on_item_click (clicked()).
        .child(div().size(14).flex_none().rounded(7).border_1()
          .border_color(done ? t.ansi2 : it.overdue ? t.ansi1 : t.muted).bg(done ? t.ansi2 : t.background)
          .text_size(9).text_color(t.background).flex().items_center().justify_center()
          .child(done ? "✓" : ""))
        .when(Boolean(it.time), (e) => e.child(div().flex_none().text_size(11.5).text_color(it.overdue ? t.ansi1 : t.ansi3).child(hhmm(it.time))))
        .child(div().flex_1().min_w(0).truncate().text_color(done ? t.dim : t.foreground).when(done, (x) => x.line_through()).child(it.title))
        .when(Boolean(it.repeat), (e) => e.child(div().flex_none().text_size(11).text_color(t.dim).child("↻")))
        .when(Boolean(it.note?.path), (e) => e.child(div().flex_none().text_size(11).text_color(t.dim).child("◆")))
        .when(Boolean(it.tag) && this.name !== "someday", (e) => e.child(div().flex_none().px(5).rounded(8).border_1().border_color(t.border).text_size(10.5).text_color(t.dim).child("#" + it.tag)));
    };

    let body;
    if (this.available === false) body = div().p(14).text_color(t.dim).child("The assistant isn't set up on this machine");
    else if (!d && this.error) body = div().p(14).text_color(t.muted).child(this.error);
    else if (!d) body = div().p(14).text_color(t.dim).child("Loading your list…");
    else if (!rows.length) body = div().p(14).text_color(t.dim).child(this.name === "today" ? "Nothing left for today" : "Nothing here");
    else body = div().flex_1().min_h(0).relative().px(4).py(2)
      .child(v_virtual_list("todos-list", rows.length, rows.map((r) => (r.kind === "head" ? HEAD_H : ROW_H)), (i) => rows[i].key,
        (range) => rows.slice(range.start, range.end).map(row))
        .on_item_click((key, cx) => this.clicked(key, cx)).track_scroll(this.scroll).size_full())
      .child(Scrollbar.vertical("todos-list").viewport_from_layout().absolute().inset_0());

    return v_flex().id("todos").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .on_mouse_down("left", () => { if (!this.adding) this.handle.focus(); })
      .size_full().min_h(0).rounded(10).overflow_hidden().bg(t.background).border_1().border_color(t.border).text_size(12.5).text_color(t.foreground)
      .child(header)
      .when(this.adding, (e) => e.child(addBar))
      .when(Boolean(d && this.error), (e) => e.child(div().flex_none().px(12).py(4).text_size(11).text_color(t.ansi1).child(this.error)))
      .child(body)
      .child(h_flex().flex_none().h(22).px(12).items_center().border_t(1).border_color(t.border).text_size(10.5).text_color(t.dim)
        .child(`j/k move · x tick · a add · tab view · h ${this.showDone ? "hide" : "show"} done · o note · r refresh`));
  }
}
