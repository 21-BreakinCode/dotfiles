// glass: a clone of Herdr's `workspace-chrome` mod 0.1.18 (Apache-2.0, see NOTICE), changed
// for Herdr Glass: an Appearance row in the footer, and on the macOS rail a taller brand block
// with the fold button under the traffic lights.
import { View, div, image, svg } from "gpui-kit";
import { h_flex, v_flex } from "gpui-base";
import { theme, run, props, window, shared, setShared, updates, layout, checking } from "herdr";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The sidebar's rail goes by its width, not a flag: dragging its edge narrows it too.
const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;

// To the rail (on macOS wide enough for the traffic lights), or back to the width it had.
function toggleSidebar() {
  const width = find(layout(), "sidebar")?.size?.px;
  if (!narrow()) setShared("sidebar.width", width);
  // Mods edited before the rail went by width still read the flag.
  setShared("sidebar.collapsed", !narrow());
  const folding = !narrow();
  run("layout.resize", { id: "sidebar", px: folding ? (window()?.platform === "macos" ? 76 : 44) : (shared("sidebar.width") ?? 268) });
  fitBrand(folding);
}

// glass: on the macOS rail the traffic lights fill the top row, so the brand block grows
// a second row and the unfold button sits under the lights, where the fold button was.
const BRAND = 46, BRAND_RAIL = 84;
function fitBrand(collapsed) {
  if (checking()) return;
  const want = collapsed && window()?.platform === "macos" && !window()?.fullscreen ? BRAND_RAIL : BRAND;
  if (find(layout(), "brand")?.size?.px !== want) run("layout.resize", { id: "brand", px: want });
}

export default class WorkspaceChrome extends View {
  button(id, label, action) {
    const t = theme();
    return div().id(id).size(26).flex_none().flex().items_center().justify_center().rounded(6).text_color(t.muted).hover(s => s.bg(t.hover).text_color(t.foreground))
      .on_mouse_down("left", (_e, cx) => cx.stop_propagation()).on_click(action).child(label);
  }
  render() {
    const t = theme();
    const collapsed = narrow();
    if (props()?.footer) {
      const row = (id, icon, label, dim, action) => h_flex().id(id).h(28).px(8).gap(9).items_center().rounded(8)
        .when(collapsed, el => el.relative().w(32).px(0).justify_center().tooltip(label))
        .text_color(dim ? t.dim : t.muted).hover(s => s.bg(t.hover).text_color(t.foreground)).cursor_pointer()
        .on_click(action).child(svg(`mods/herdr-glass-chrome/${icon}.svg`).size(14))
        .when(!collapsed, el => el.child(label));
      const ready = div().size(6).rounded_full().bg(t.accent);
      return v_flex().size_full().bg(t.chrome).border_t(1).border_color(t.border).px(8).pt(4).pb(8).text_size(13)
        .when(collapsed, el => el.px(0).items_center())
        .child(row("settings", "settings", "Settings", false, () => run("app.settings"))
          .when(Boolean(updates().app.ready), el => el.child(collapsed ? ready.absolute().top(5).right(6) : ready)))
        .child(row("appearance", "palette", "Appearance", false, () => run("mod.open", { name: "herdr-glass-bg" })))
        .child(row("machine", "plus", "Add machine", true, () => run("mod.open", { name: "machine-add" })));
    }
    // A rail made by dragging the edge, not the button, still needs the second row.
    fitBrand(collapsed);
    const toggle = this.button("sidebar-toggle", svg("mods/herdr-glass-chrome/sidebar.svg").size(15), toggleSidebar);
    if (collapsed && window()?.platform === "macos" && !window()?.fullscreen) {
      return v_flex().size_full().bg(t.chrome).items_center().justify_end().pb(10).child(toggle.tooltip("Show sidebar"));
    }
    return h_flex().size_full().bg(t.chrome).pl(collapsed ? 6 : 14).pr(10).gap(4).items_center().text_size(13.5)
      .when(window()?.platform === "macos" && !window()?.fullscreen && !collapsed, el => el.pl(76))
      .when(!collapsed, el => el.child(h_flex().flex_1().gap(8).items_center().child(image("frame/welcome/herdr.png").size(20).rounded(5)).child(div().font_semibold().text_color(t.foreground).child("Herdr"))))
      .when(!collapsed, el => el.child(this.button("search", svg("mods/herdr-glass-chrome/search.svg").size(15), () => run("mod.open", { name: "picker" }))))
      .child(toggle.tooltip(collapsed ? "Show sidebar" : "Hide sidebar"));
  }
}
