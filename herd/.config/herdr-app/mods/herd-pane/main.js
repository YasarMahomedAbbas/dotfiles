// Pane header that pins a herd's description above its terminal (herd: dotfiles docs/herd.md).
// A terminal started by `herd` carries labels: herd.name, herd.title, herd.desc, herd.stage,
// herd.state. Such a pane gets two lines (name + title, then the one-line description) with
// its stage on the right; any other pane gets herdr's usual one-line header.
// Layout: { "tab": "active", "pane": { "header": { "content": { "mod": "herd-pane" }, "height": 44 } } }

import { View, div, svg, image } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { panes, terminals, props, run, theme, home } from "herdr";

function icon(p, size, color) {
  if (!p?.icon) return null;
  return p.tint ? svg(p.icon).size(size).flex_none().text_color(color) : image(p.icon).w(size).h(size).flex_none();
}

function folder(cwd) {
  if (!cwd) return "";
  const h = home();
  return cwd === h ? "~" : cwd.startsWith(h + "/") ? "~" + cwd.slice(h.length) : cwd;
}

const STAGE_STATE = { blocked: "blocked", running: "working", done: "done" };

export default class HerdPane extends View {
  init() { this.hovered = false; }

  me() { return panes().find((p) => p.pane === props()?.pane); }

  labels(p) {
    if (!p?.terminal) return {};
    const t = terminals().find((x) => x.address === p.terminal);
    return t?.labels ?? {};
  }

  button(t, id, ic, command, args) {
    return div()
      .id(id)
      .p(3)
      .rounded(4)
      .text_color(t.dim)
      .hover((s) => s.bg(t.hover).text_color(t.foreground))
      .on_click((_e, cx) => { cx.stop_propagation(); run(command, args); })
      .child(svg(`my-icons/herd-pane/${ic}.svg`).size(14));
  }

  status(t, st) {
    if (st === "working") return svg("mods/workspace-chrome/spinner.svg").size(12).flex_none().text_color(t.working).spin(900);
    if (st === "blocked") return div().flex_none().px(6).h(18).flex().items_center().rounded(5).bg(t.blocked + "26").text_size(10.5).font_semibold().text_color(t.blocked).child("Needs you");
    if (st === "done") return div().size(7).flex_none().rounded(4).bg(t.done);
    return null;
  }

  buttons(t, p) {
    const pane = p.pane;
    return [
      this.button(t, `ph-r-${pane}`, "split-right", "pane.split", { direction: "right", pane }),
      this.button(t, `ph-d-${pane}`, "split-down", "pane.split", { direction: "down", pane }),
      this.button(t, `ph-z-${pane}`, p.zoomed ? "unzoom" : "zoom", "pane.zoom", { pane }),
      this.button(t, `ph-x-${pane}`, "close", "pane.close", { pane }),
    ];
  }

  render(cx) {
    const t = theme();
    const p = this.me();
    if (!p) return div();
    const pane = p.pane;
    const l = this.labels(p);
    const base = h_flex()
      .id(`pane-head-${pane}`)
      .size_full()
      .px(10)
      .gap(8)
      .items_center()
      .bg(t.background)
      .border_b(1)
      .border_color(t.border)
      .text_size(12)
      .on_hover((hovered, cx) => { this.hovered = hovered; cx.notify(); })
      .on_click(() => run("pane.focus", { pane }));

    if (l["herd.name"]) {
      // A ticket shows its ref before the full title; the tab already carries the short words.
      const ref = l["ticket.ref"] ? (/^\d+$/.test(l["ticket.ref"]) ? `#${l["ticket.ref"]}` : l["ticket.ref"]) : "";
      const lead = ref && l["herd.title"] ? ref : l["herd.name"];
      const title = l["herd.title"] && l["herd.title"] !== l["herd.name"] ? l["herd.title"] : "";
      const desc = l["herd.desc"] && l["herd.desc"] !== title ? l["herd.desc"] : "";
      const stage = l["herd.stage"] ?? "";
      const sst = STAGE_STATE[l["herd.state"]] ?? null;
      const st = p.status === "blocked" || sst === "blocked" ? "blocked" : p.status;
      const stColor = st === "blocked" ? t.blocked : st === "working" ? t.working : st === "done" ? t.done : t.dim;
      const chip = this.status(t, st);
      return base
        .child(v_flex().flex_1().min_w(0).gap(1)
          .child(h_flex().gap(8).min_w(0).items_center()
            .child(div().flex_none().font_semibold().text_color(t.foreground).child(lead))
            .when(Boolean(title), (el) => el.child(div().flex_1().min_w(0).truncate().text_color(t.foreground).child(title))))
          .when(Boolean(desc), (el) => el.child(div().truncate().text_size(11.5).text_color(t.dim).child(desc))))
        .when(Boolean(stage) && !this.hovered, (el) => el.child(div().flex_none().text_size(11).text_color(stColor).child(stage)))
        .when(!this.hovered && Boolean(chip), (el) => el.child(chip))
        .when(this.hovered, (el) => el.children(this.buttons(t, p)));
    }

    const name = ((p.program?.agent || p.program?.shell) && p.program.name) || p.title || p.program?.name || "shell";
    const pic = icon(p.program, 14, t.dim);
    const chip = this.status(t, p.status);
    return base
      .when(Boolean(pic), (el) => el.child(pic))
      .child(div().flex_none().truncate().max_w(260).font_medium().text_color(t.foreground).child(name))
      .child(div().flex_1().truncate().text_color(t.dim).child(folder(p.cwd)))
      .when(Boolean(chip), (el) => el.child(chip))
      .when(this.hovered, (el) => el.children(this.buttons(t, p)));
  }
}
