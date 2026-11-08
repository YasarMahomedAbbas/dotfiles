// Session picker for C-f s (a simple herdr take on sesh).
// Three groups: Open (spaces already running), Projects (herd's projects.json plus this mod's, not yet
// open) and Recent (zoxide's folders, most used first). Picking an open space
// switches to it; picking a project or folder opens a space there with `claude`
// running. Type to filter, ↑/↓, ctrl-j/ctrl-k or ctrl-n/ctrl-p to move, Enter to go, Esc to close.

import { View, div } from "gpui-kit";
import { v_flex, h_flex, InputState, Input } from "gpui-base";
import { run, props, closeOverlay, spaces, theme, home, appHome, readTextFile, exec, notify } from "herdr";

const VISIBLE = 14;      // rows shown at once; the window follows the selection
const RECENT_IDLE = 12;  // recent folders shown before you type (all of them match once you do)
const ROW_H = 30;
const HEAD_H = 24;

const expand = (p) => (p.startsWith("~/") ? home() + p.slice(1) : p);
const short = (p) => (p && p.startsWith(home()) ? "~" + p.slice(home().length) : p || "");
const base = (p) => p.replace(/\/+$/, "").split("/").pop() || p;
const norm = (p) => (p || "").replace(/\/+$/, "");

export default class Sessions extends View {
  init(_props, cx) {
    this.projects = [];
    this.recent = [];
    this.roots = [];
    this.filter = "";
    this.at = 0;
    this.top = 0;
    this.input = InputState.new({ placeholder: "Session, project or folder…" });
    this.input.on("change", (_e, cx) => { this.filter = this.input.value(); this.at = 0; this.top = 0; cx.notify(); });
    this.input.on("submit", () => this.go(this.rows()[this.at]));
    this.input.focus();
    cx.timer.after(50, () => this.input.focus());
    this.handle = cx.focus_handle();
    cx.spawn(async (cx) => {
      try {
        // herd's projects (~/.config/herd/projects.json: root + workdir) first, then this
        // mod's projects.json for folders that aren't herd projects (dotfiles, vault…).
        // A name in both: this file's path wins.
        const herdText = await readTextFile(home() + "/.config/herd/projects.json").catch(() => null);
        const fromHerd = Object.entries(JSON.parse(herdText ?? "{}"))
          .filter(([name, p]) => !name.startsWith("//") && p?.root)
          .map(([name, p]) => ({ name, path: norm(expand(p.workdir ? `${norm(p.root)}/${p.workdir}` : p.root)) }));
        const text = await readTextFile(appHome() + "/mods/sessions/projects.json");
        const own = (JSON.parse(text ?? "{}").projects ?? []).map((p) => ({ name: p.name, path: norm(expand(p.path)) }));
        const ownNames = new Set(own.map((p) => p.name.toLowerCase()));
        this.projects = [...fromHerd.filter((p) => !ownNames.has(p.name.toLowerCase())), ...own];
        // Each project's repo root (travelsmart's Frontend -> travel-smart): Recent hides
        // anything at or under it. Not a git repo: the project folder itself.
        this.roots = this.projects.map((p) => p.path);
        cx.notify();
        this.roots = await Promise.all(this.projects.map(async (p) => {
          try {
            const r = await exec("git", ["-C", p.path, "rev-parse", "--show-toplevel"]);
            return r.code === 0 && r.stdout.trim() ? norm(r.stdout.trim()) : p.path;
          } catch (_) { return p.path; }
        }));
      } catch (e) {
        notify({ title: "Sessions", body: "projects.json: " + e, level: "error" });
      }
      cx.notify();
    });
    cx.spawn(async (cx) => {
      try {
        const r = await exec("zoxide", ["query", "--list"]);
        if (r.code === 0) this.recent = r.stdout.split("\n").map(norm).filter(Boolean);
      } catch (_) { /* no zoxide: no Recent group */ }
      cx.notify();
    });
  }

  rows() {
    const f = this.filter.toLowerCase();
    const match = (r) => !f || (r.name + " " + r.detail).toLowerCase().includes(f);
    const open = spaces();
    const openNames = new Set(open.map((s) => s.name.toLowerCase()));
    const openFolders = new Set(open.map((s) => norm(s.folder)).filter(Boolean));
    const openRows = open.map((s) => ({ kind: "open", id: s.id, name: s.name, detail: short(s.folder), active: s.active, status: s.status }));
    const projects = this.projects.filter((p) => !openNames.has(p.name.toLowerCase()) && !openFolders.has(p.path));
    const projectRows = projects.map((p) => ({ kind: "project", name: p.name, path: p.path, detail: short(p.path) }));
    const taken = new Set([...openFolders, ...this.projects.map((p) => p.path), home()]);
    const inProject = (p) => this.roots.some((r) => p === r || p.startsWith(r + "/"));
    let recentRows = this.recent.filter((p) => !taken.has(p) && !inProject(p))
      .map((p) => ({ kind: "recent", name: base(p), path: p, detail: short(p) })).filter(match);
    if (!f) recentRows = recentRows.slice(0, RECENT_IDLE);
    return [...openRows.filter(match), ...projectRows.filter(match), ...recentRows];
  }

  go(r) {
    if (!r) return;
    closeOverlay(props().overlay);
    if (r.kind === "open") run("space.select", { id: r.id });
    else run("space.new", { name: r.name, folder: r.path, argv: ["claude"], machine: "" });
  }

  key(e, cx) {
    const n = this.rows().length;
    if (["down", "ctrl-n", "ctrl-j"].includes(e.keystroke)) this.at = n ? (this.at + 1) % n : 0;
    else if (["up", "ctrl-p", "ctrl-k"].includes(e.keystroke)) this.at = n ? (this.at + n - 1) % n : 0;
    else if (e.keystroke === "escape") return closeOverlay(props().overlay);
    else return;
    cx.stop_propagation();
    cx.notify();
  }

  render() {
    const t = theme();
    const rows = this.rows();
    this.at = Math.max(0, Math.min(this.at, rows.length - 1));
    if (this.at < this.top) this.top = this.at;
    if (this.at >= this.top + VISIBLE) this.top = this.at - VISIBLE + 1;
    this.top = Math.max(0, Math.min(this.top, Math.max(0, rows.length - VISIBLE)));

    const TITLES = { open: "Open", project: "Projects", recent: "Recent folders" };
    const ACTION = { open: "", project: "start claude", recent: "start claude" };
    const dot = (r) => (r.kind === "open" ? (t[r.status] ?? t.idle) : t.border);
    const head = (kind) => div().h(HEAD_H).flex_none().px(10).pt(6).text_size(11).text_color(t.dim).child(TITLES[kind]);
    const row = (r, i) => h_flex().id("row-" + i).h(ROW_H).flex_none().px(10).gap(10).items_center().rounded(6).cursor_pointer()
      .bg(i === this.at ? t.selected : t.popover).hover((s) => s.bg(t.hover)).on_click(() => this.go(r))
      .child(div().size(7).flex_none().rounded(4).bg(dot(r)))
      .child(div().flex_none().text_color(t.foreground).font_medium().child(r.name + (r.active ? "  · here" : "")))
      .child(div().flex_1().min_w(0).text_size(11.5).text_color(t.dim).truncate().child(r.detail))
      .child(div().flex_none().text_size(11).text_color(t.muted).child(i === this.at ? ACTION[r.kind] : ""));

    const children = [];
    rows.slice(this.top, this.top + VISIBLE).forEach((r, k) => {
      const i = this.top + k;
      if (i === 0 || rows[i - 1].kind !== r.kind) children.push(head(r.kind));
      children.push(row(r, i));
    });
    if (!rows.length) children.push(div().p(12).text_color(t.dim).child("Nothing matches"));

    const more = rows.length - (this.top + VISIBLE);
    return v_flex().id("sessions").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .w_full().p(12).gap(6).bg(t.popover).text_size(13)
      .child(h_flex().items_center()
        .child(div().flex_1().text_size(15).font_semibold().text_color(t.foreground).child("Sessions"))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(h_flex().h(36).flex_none().px(10).items_center().rounded(8).border_1().border_color(t.accent).bg(t.background)
        .child(Input.new(this.input).flex_1().h_full().text_size(13).text_color(t.foreground)))
      .child(v_flex().children(children))
      .child(div().h(16).px(10).text_size(11).text_color(t.dim)
        .child(more > 0 ? `${more} more ↓` : `${rows.length} ${rows.length === 1 ? "item" : "items"}`));
  }
}
