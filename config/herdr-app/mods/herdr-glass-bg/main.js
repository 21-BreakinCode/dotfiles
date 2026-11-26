// Appearance dialog for personal layouts (the mod is named for the background pictures it
// holds), in the style of Herdr's Settings: no buttons, every click applies at once, Esc
// or a click outside closes it.
// - Glass: how see-through the cards are (Clear … Solid), for bright pictures.
// - Image: Default (Graphite) plus whatever is in ~/.config/herdr-app/backgrounds/.
//   People manage that folder themselves ("Open folder" shows it in the file manager); the list
//   rereads it while the dialog is open. The other presets are copied into it once, so
//   they can be deleted like any other picture. If the picture in use is gone, the
//   background goes back to Default.
// - Components: one switch puts every restyled block on the glass mod or on Herdr's own,
//   so people can take Herdr's versions (which update with Herdr) when they prefer them.
// Shipped layouts are replaced on every start, so they're refused.
import { View, div, image } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { props, closeOverlay, theme, exec, appHome, shared, readTextFile, writeTextFile, checking } from "herdr";

const SHIPPED = ["main", "terminals", "win98"];
const IMAGE = /\.(png|jpe?g|webp|gif)$/i;
const DEFAULT = "mods/herdr-glass-bg/presets/graphite.jpg";
// The other presets are copied into backgrounds/ the first time ($1 is this mod, $2 the
// folder); a marker file says it's done, so a deleted one stays deleted. A folder filled
// by the first version (Graphite copied, no Sunset; old marker) only gets Sunset, and
// loses its Graphite copy if untouched, since Graphite is Default now.
const SEED = `cd "$1" || exit 0
[ ! -e "$2/.glass-presets-2" ] || exit 0
mkdir -p "$2" || exit 0
if [ -e "$2/.glass-presets-copied" ]; then
  cmp -s presets/graphite.jpg "$2/Graphite.jpg" && rm -f "$2/Graphite.jpg"
  rm -f "$2/.glass-presets-copied"
else
  for n in Ocean Forest Violet Rose Aurora; do
    cp -n "presets/$(printf %s "$n" | tr A-Z a-z).jpg" "$2/$n.jpg"
  done
fi
cp -n default-bg.png "$2/Sunset.png"
touch "$2/.glass-presets-2"`;
// The image grid: three 170px tiles a row in the 580px dialog, each row 144px tall with
// its gap (measured). Past two rows it scrolls, with the scrollbar always shown.
const PER_ROW = 3, TILE_ROW = 144, GRID_ROWS = 2;
// A picture's name: its file name without the extension.
const label = (path) => path === DEFAULT ? "Default" : path.split("/").pop().replace(/\.[^.]+$/, "");

// Glass levels: alpha of the cards (sidebar, tab bar, status bar, side panel) and of the
// terminal frame. A brighter picture needs a more opaque glass to keep text readable.
const CARD = "#15171d", PANE = "#21252b", CARDS = ["sidebar", "tabs", "status", "panel"];
const LEVELS = [
  { id: "clear", label: "Clear", card: "40", pane: "bf" },
  { id: "light", label: "Light", card: "66", pane: "d9" },
  { id: "medium", label: "Medium", card: "99", pane: "e6" },
  { id: "tinted", label: "Tinted", card: "c2", pane: "f0" },
  { id: "solid", label: "Solid", card: "eb", pane: "fa" },
];

// Blocks the Components switch moves between the glass mod and Herdr's own. A block is
// the layout node `node`, the pane header of the tab block `header`, or the root's
// `toast` key. The tab bar, the status bar and the sidebar chrome stay glass: Herdr's
// versions draw divider lines and have no Appearance entry to get back to this dialog.
const PARTS = [
  { node: "spaces", glass: "herdr-glass-spaces", herdr: "spaces" },
  { node: "agents", glass: "herdr-glass-agents", herdr: "agents" },
  { header: "main", glass: "herdr-glass-pane", herdr: "pane" },
  { root: "toast", glass: "herdr-glass-toast", herdr: "toast" },
];
// A tab block's pane header, where its mod is named.
const headerOf = (d, id) => nodes(d)[id]?.content?.pane?.header?.content;

function nodes(root) {
  const out = {};
  const walk = (n) => { if (n?.id) out[n.id] = n; (n?.children ?? []).forEach(walk); };
  walk(root);
  return out;
}

// The level whose card alpha is closest to the sidebar's, so hand edits still pick one.
function levelOf(d) {
  const bg = nodes(d).sidebar?.background;
  const alpha = typeof bg === "string" && /^#[0-9a-f]{8}$/i.test(bg) ? parseInt(bg.slice(7), 16) : null;
  if (alpha === null) return null;
  return LEVELS.reduce((best, l) => Math.abs(parseInt(l.card, 16) - alpha) < Math.abs(parseInt(best.card, 16) - alpha) ? l : best).id;
}

// Which mod a part uses now: "glass", "herdr", or null when the layout has neither.
function partOf(d, p) {
  const mod = p.root ? (d[p.root] ?? "toast") : p.header ? headerOf(d, p.header)?.mod : nodes(d)[p.node]?.content?.mod;
  return mod === p.glass ? "glass" : mod === p.herdr ? "herdr" : null;
}

// The switch's state: "glass" or "herdr" when every part agrees, else null (mixed by hand;
// either choice makes them agree again).
function componentsOf(d) {
  const all = new Set(PARTS.map(p => partOf(d, p)));
  return all.size === 1 ? [...all][0] : null;
}

export default class Background extends View {
  init(_props, cx) {
    this.images = [];
    this.current = null;
    this.level = null;
    this.components = null;
    this.message = null;
    this.handle = cx.focus_handle();
    this.handle.focus();
    if (checking()) return;
    this.load(cx);
    // The folder is edited in Finder, maybe with this open: keep the list in step.
    cx.timer.every(3000, (cx) => this.scan(cx));
  }

  dir() { return `${appHome()}/backgrounds`; }
  file() { return `${appHome()}/layouts/${shared("layout")}.json`; }

  load(cx) {
    cx.spawn(async (cx) => {
      await exec("sh", ["-c", SEED, "seed", `${appHome()}/mods/herdr-glass-bg`, this.dir()]);
      try {
        const d = JSON.parse((await readTextFile(this.file())) ?? "{}");
        this.read(d);
      } catch { this.current = null; this.level = null; this.components = null; }
      await this.scan(cx);
    });
  }

  // Rereads backgrounds/. A picture from there that's in use but gone puts Default back.
  async scan(cx) {
    const r = await exec("ls", ["-1", this.dir()]);
    const files = r.code === 0 ? r.stdout.split("\n").filter(n => IMAGE.test(n)).sort().map(n => `backgrounds/${n}`) : [];
    const images = [DEFAULT, ...files];
    if (images.join("\n") !== this.images.join("\n")) {
      this.images = images;
      cx.notify();
    }
    if (this.current?.startsWith("backgrounds/") && !files.includes(this.current) && !SHIPPED.includes(shared("layout"))) {
      this.apply(DEFAULT, cx);
    }
  }

  read(d) {
    this.current = typeof d.background?.image === "string" ? d.background.image : null;
    this.level = levelOf(d);
    this.components = componentsOf(d);
  }

  // Read the shown layout, change it, write it back only if nobody changed it meanwhile.
  edit(cx, change) {
    const layout = shared("layout");
    if (SHIPPED.includes(layout)) {
      this.message = `“${layout}” is Herdr's own layout and is reset on start. Switch to your own layout first.`;
      cx.notify();
      return;
    }
    cx.spawn(async (cx) => {
      try {
        const text = await readTextFile(this.file());
        const d = JSON.parse(text);
        change(d);
        await writeTextFile(this.file(), JSON.stringify(d, null, 2) + "\n", text);
        this.read(d);
        this.message = null;
      } catch (e) {
        this.message = `Couldn't save the layout: ${e}`;
      }
      cx.notify();
    });
  }

  apply(name, cx) {
    this.edit(cx, (d) => { d.background = { image: name, fit: "cover" }; });
  }

  glass(level, cx) {
    this.edit(cx, (d) => {
      const n = nodes(d);
      for (const id of CARDS) if (n[id]) n[id].background = CARD + level.card;
      if (n.main?.content?.pane) n.main.content.pane.background = PANE + level.pane;
    });
  }

  setComponents(which, cx) {
    this.edit(cx, (d) => {
      for (const p of PARTS) {
        if (p.root) {
          if (which === "glass") d[p.root] = p.glass;
          else delete d[p.root];   // no key means Herdr's own
        } else if (p.header) {
          const h = headerOf(d, p.header);
          if (h) h.mod = which === "glass" ? p.glass : p.herdr;
        } else {
          const n = nodes(d)[p.node];
          if (n?.content) n.content.mod = which === "glass" ? p.glass : p.herdr;
        }
      }
    });
  }

  // Finder on macOS, the file manager elsewhere.
  openFolder() {
    exec("sh", ["-c", 'mkdir -p "$1" && { open "$1" 2>/dev/null || xdg-open "$1"; }', "open", this.dir()]);
  }

  key(e, cx) {
    if (e.key === "escape") { closeOverlay(props().overlay); cx.stop_propagation(); }
  }

  render() {
    const t = theme();
    const heading = (text, extra) => h_flex().items_center()
      .child(div().flex_1().text_size(12.5).font_semibold().child(text))
      .when(Boolean(extra), el => el.child(extra));
    const segmented = (id, items, on, pick) => h_flex().id(id).p(3).gap(3).rounded(9).bg(t.raised).border_1().border_color(t.border)
      .children(items.map(([key, label]) => div().id(`${id}-${key}`).flex_1().h(26).flex().items_center().justify_center().rounded(7)
        .text_size(12).cursor_pointer().bg(key === on ? t.selected : "#00000000")
        .text_color(key === on ? t.foreground : t.muted).hover(s => s.bg(t.hover).text_color(t.foreground))
        .on_click((_e, cx) => pick(key, cx)).child(label)));
    const tile = (name) => {
      const on = name === this.current;
      return v_flex().id(`bg-${name}`).w(170).gap(6).p(5).rounded(10).cursor_pointer()
        .border_1().border_color(on ? t.accent : "#00000000").hover(s => s.bg(t.hover))
        .on_click((_e, cx) => this.apply(name, cx))
        .child(image(name).w(158).h(96).rounded(7))
        .child(div().px(2).truncate().text_size(11.5).text_color(on ? t.foreground : t.muted).child(label(name)));
    };
    const open = div().id("bg-open").px(8).py(3).rounded(6).text_size(12).text_color(t.muted).cursor_pointer()
      .hover(s => s.bg(t.hover).text_color(t.foreground)).tooltip("~/.config/herdr-app/backgrounds")
      .on_click(() => this.openFolder()).child("Open folder");
    const shown = this.images.length ? this.images : [DEFAULT];

    return v_flex().id("herdr-glass-bg").track_focus(this.handle).on_key_down((e, cx) => this.key(e, cx))
      .w_full().p(18).gap(14).bg(t.popover).text_color(t.foreground)
      .child(div().text_size(15).font_semibold().child("Appearance"))
      .child(v_flex().gap(6)
        .child(heading("Glass"))
        .child(segmented("glass", LEVELS.map(l => [l.id, l.label]), this.level, (id, cx) => this.glass(LEVELS.find(l => l.id === id), cx))))
      .child(v_flex().gap(6)
        .child(heading("Image", open))
        // A scrollbar wraps its list, so a max_h on it never reaches the layout. Give an outer
        // column the height and let the list fill it (flex_1 + min_h 0), as Herdr's lists do.
        .child(v_flex().h(Math.min(Math.ceil(shown.length / PER_ROW), GRID_ROWS) * TILE_ROW - 6)
          .child(v_flex().id("bg-grid").flex_1().min_h(0).overflow_y_scrollbar().mode("always")
            .child(h_flex().flex_wrap().gap(6).children(shown.map(tile))))))
      .child(v_flex().gap(6)
        .child(heading("Components"))
        .child(segmented("components", [["glass", "Glass"], ["herdr", "Herdr"]], this.components, (w, cx) => this.setComponents(w, cx)))
        .child(div().truncate().text_size(11.5).text_color(t.dim).child(
          this.components === "herdr"
            ? "Herdr's own Spaces, Agents, pane headers and notifications, updated with Herdr."
            : this.components === "glass"
              ? "Restyled Spaces, Agents, pane headers and notifications."
              : "Mixed: pick one to make them all match.")))
      .when(Boolean(this.message), el => el.child(div().text_size(12).text_color(t.blocked).child(this.message)));
  }
}
