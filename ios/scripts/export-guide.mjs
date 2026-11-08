// Web 版（index.html）の種目データと図を、SwiftUI 版が読む JSON に書き出す。
// 図は Web 版の poseSvg / exIcon / bodyMap が作る SVG をそのまま図形の並びに直すので、見た目は Web 版と同じになる。
// 使い方：node ios/scripts/export-guide.mjs  （index.html の種目・ガイドを変えたら実行し直す）
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const root = join(dirname(fileURLToPath(import.meta.url)), "../..");
const html = readFileSync(join(root, "index.html"), "utf8");
const cut = (from, to) => {
  const a = html.indexOf(from), b = html.indexOf(to, a);
  if (a < 0 || b < 0) throw new Error(`index.html に ${from} 〜 ${to} が見つかりません`);
  return html.slice(a, b);
};
const src = cut("const PRESETS = {", "const $ = s =>")
  + cut("const BONE = {", "// 図の左上に出す")
  + "\n;({ PRESETS, MUSCLE, MUSCLE_SHORT, GUIDE, BODY, BODY_SIL, poseSvg, exIcon })";
const ctx = vm.runInNewContext(src, {});
const { PRESETS, MUSCLE, MUSCLE_SHORT, GUIDE, BODY, BODY_SIL, poseSvg, exIcon } = ctx;

// SVG の文字列を図形の並びにする。layer は一番内側の fig-* の class
const LAYERS = ["fig-ghost", "fig-body", "fig-gear", "fig-arrow", "fig-floor"];
function shapes(svg) {
  const out = [], stack = [];
  const num = (a, k) => a[k] === undefined ? undefined : +a[k];
  for (const m of svg.matchAll(/<(\/?)(\w+)([^>]*?)(\/?)>/g)) {
    const [, close, tag, attrStr, self] = m;
    if (tag === "svg" || tag === "title") continue;
    if (tag === "g") { if (close) stack.pop(); else stack.push(/class="([^"]*)"/.exec(attrStr)?.[1] || ""); continue; }
    if (close) continue;
    const a = Object.fromEntries([...attrStr.matchAll(/([\w-]+)="([^"]*)"/g)].map(x => [x[1], x[2]]));
    const cls = [...stack, a.class || ""].reverse().flatMap(c => c.split(" ")).find(c => LAYERS.includes(c));
    const s = { k: tag, layer: cls ? cls.slice(4) : "gear" };
    if ((a.class || "").includes("solid")) s.solid = true;
    if (a["stroke-width"]) s.sw = +a["stroke-width"];
    if (tag === "line") s.p = [[+a.x1, +a.y1], [+a.x2, +a.y2]];
    else if (tag === "polyline" || tag === "polygon") s.p = a.points.trim().split(/\s+/).map(p => p.split(",").map(Number));
    else if (tag === "circle") Object.assign(s, { cx: +a.cx, cy: +a.cy, r: +a.r });
    else if (tag === "rect") Object.assign(s, { x: +a.x, y: +a.y, w: +a.width, h: +a.height, rx: num(a, "rx") ?? 0 });
    else continue;
    out.push(s);
    void self;
  }
  return out;
}
const viewBox = svg => /viewBox="([^"]*)"/.exec(svg)[1].split(" ").map(Number);
function pose(g, i) {
  const svg = poseSvg(g, i);
  return { vb: viewBox(svg), sc: g.scale || 1, items: shapes(svg) };
}
function icon(name) {
  const svg = exIcon(name);
  return { vb: viewBox(svg), sc: 1, items: shapes(svg) };
}

const guide = {};
for (const [name, g] of Object.entries(GUIDE)) {
  guide[name] = {
    gear: g.gear, main: g.main, sub: g.sub, front: g.view === "front",
    note: g.note || "", steps: g.steps, tips: g.tips,
    start: pose(g, 0), finish: pose(g, 1), icon: icon(name)
  };
}

// 人体図。BODY_SIL は楕円1つとパス1つ
const sil = {
  ellipse: /<ellipse cx="([\d.]+)" cy="([\d.]+)" rx="([\d.]+)" ry="([\d.]+)"/.exec(BODY_SIL).slice(1).map(Number),
  path: /<path d="([^"]*)"/.exec(BODY_SIL)[1]
};
const body = Object.fromEntries(Object.entries(BODY).map(([v, b]) => [v, { mid: b.mid || [], parts: Object.entries(b.parts).map(([m, d]) => ({ m, d })) }]));

const out = {
  parts: Object.keys(PRESETS).map(p => ({ name: p, exercises: PRESETS[p] })),
  muscles: Object.keys(MUSCLE).map(k => ({ key: k, name: MUSCLE[k], short: MUSCLE_SHORT[k] })),
  guide, sil, body
};
const dest = join(root, "ios/LiftLog/Resources/guide.json");
writeFileSync(dest, JSON.stringify(out) + "\n");
console.log(`${Object.keys(guide).length} 種目を ${dest} に書き出しました`);
