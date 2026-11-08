// tmux-style prefix for herdr, mirroring ~/.tmux.conf (prefix C-f).
// Ctrl+F opens this popup; the next key runs the matching tmux binding and
// closes it. Ctrl+F again sends Ctrl+F to the program (tmux `send-prefix`).
// Esc or any unbound key just closes it.

import { View, div } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, hc, props, closeOverlay, focused, theme, nextCommand, notify, openOverlay, spaces, panes, layout } from "herdr";

// tmux's `,` / `$`: herdr's own rename dialog (the shipped `prompt` mod), pre-filled.
function rename(kind, f) {
  const space = spaces().find((x) => x.id === f?.space);
  const item = kind === "tab" ? space?.tabs.find((x) => x.id === f?.tab) : space;
  if (!item) return;
  openOverlay({ mod: "prompt", kind: "dialog", width: 420, props: {
    title: `rename ${kind === "tab" ? "window" : "session"}`, value: item.name,
    hint: "Empty: back to herdr's own name",
    command: { name: `${kind}.rename`, args: { id: item.id } } } });
}

// A view in the right-hand sidebar (where Files and Changes live): show it, or hide the
// sidebar when it's already showing.
function togglePanel(child, title) {
  const find = (n, id) => (!n ? null : n.id === id ? n : (n.children ?? []).map((c) => find(c, id)).find(Boolean) ?? null);
  const root = layout(), panel = find(root, "panel"), body = find(root, "panel-body");
  if (!panel || !(body?.children ?? []).some((c) => c.id === child)) {
    notify({ title, body: `This layout has no ${child} view; switch to the herd layout`, level: "warning" });
    return;
  }
  if (!panel.hidden && body.active === child) run("layout.hide", { id: "panel" });
  else { run("layout.select", { stack: "panel-body", child }); run("layout.show", { id: "panel" }); }
}

// Every binding here comes from ~/.tmux.conf, except t and d (my sidebar views).
const BINDINGS = {
  c: ["new window (here)", (f) => run("terminal.open", { place: "tab", ...(f?.cwd ? { folder: f.cwd } : {}) })],
  V: ["split side by side", (f) => run("terminal.open", { place: "right", ...(f?.cwd ? { folder: f.cwd } : {}) })],
  H: ["split stacked", (f) => run("terminal.open", { place: "down", ...(f?.cwd ? { folder: f.cwd } : {}) })],
  h: ["pane left", () => run("pane.go", { direction: "left" })],
  j: ["pane down", () => run("pane.go", { direction: "down" })],
  k: ["pane up", () => run("pane.go", { direction: "up" })],
  l: ["pane right", () => run("pane.go", { direction: "right" })],
  x: ["close pane", () => run("pane.close", {})],
  t: ["tickets panel", () => togglePanel("tickets", "Tickets")],
  d: ["todos panel", () => togglePanel("todos", "Todos")],
  s: ["session picker", () => run("mod.open", { name: "sessions" })],
  ",": ["rename window", (f) => rename("tab", f)],
  "$": ["rename session", (f) => rename("space", f)],
  b: ["toggle sidebar", () => run("layout.toggle", { id: "sidebar" })],
  r: ["reload", () => notify({ title: "Reloaded!", body: "herdr reloads keys.json by itself", timeout: 1500 })],
};
BINDINGS.B = BINDINGS.b;
for (let i = 1; i <= 9; i++) BINDINGS[String(i)] = [`window ${i}`, () => run("tab.select", { index: i })];

export default class TmuxPrefix extends View {
  init(_props, cx) {
    this.target = focused(); // the pane/terminal you were in when you pressed the prefix
    this.done = false;
    this.handle = cx.focus_handle();
    this.handle.focus();
    cx.timer.after(50, () => this.handle.focus());
    // Ctrl+F while open arrives as a key command from keys.json's "mod:tmux-prefix" section.
    cx.spawn(async () => { for (;;) { const c = await nextCommand(); if (c === "send_prefix") this.sendPrefix(); } });
  }

  finish(fn) {
    if (this.done) return;
    this.done = true;
    closeOverlay(props().overlay);
    try { fn?.(this.target); } catch (e) { notify({ title: "tmux prefix", body: String(e), level: "error" }); }
  }

  sendPrefix() {
    this.finish((f) => { if (f?.terminal) hc(["keys", f.terminal, "ctrl+f"]); });
  }

  key(e, cx) {
    cx.stop_propagation();
    if (e.keystroke === "ctrl-f") return this.sendPrefix();
    if (e.modifiers?.control || e.modifiers?.alt || e.modifiers?.platform) return this.finish();
    const ch = e.key_char ?? (e.modifiers?.shift ? e.key.toUpperCase() : e.key);
    this.finish(BINDINGS[ch]?.[1]);
  }

  render() {
    const t = theme();
    const chip = (k, label) => h_flex().gap(6).items_center()
      .child(div().px(6).rounded(4).bg(t.raised).text_color(t.foreground).font_semibold().child(k))
      .child(div().text_color(t.muted).child(label));
    return v_flex().id("tmux-prefix").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .size_full().p(12).gap(8).bg(t.popover).text_size(12)
      .child(h_flex().child(div().flex_1().font_semibold().text_color(t.accent).child("C-f"))
        .child(div().text_size(11).text_color(t.dim).child("Esc")))
      .child(h_flex().flex_wrap().gap_x(14).gap_y(6)
        .child(chip("c", "new"))
        .child(chip("V", "split │"))
        .child(chip("H", "split ─"))
        .child(chip("hjkl", "move"))
        .child(chip("1-9", "window"))
        .child(chip("x", "close pane"))
        .child(chip("s", "sessions"))
        .child(chip("t", "tickets"))
        .child(chip("d", "todos"))
        .child(chip(",", "rename"))
        .child(chip("$", "rename session"))
        .child(chip("C-f", "send C-f")));
  }
}
