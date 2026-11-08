import SwiftUI

// 種目ガイドの図・記録画面の種目アイコン・人体図。どれも Web 版の SVG と同じ座標で描く

/// 図の座標（viewBox）を、描く枠に縦横比を保って収める
private func fit(_ vb: [Double], in size: CGSize) -> CGAffineTransform {
  let k = min(size.width / vb[2], size.height / vb[3])
  let dx = (size.width - vb[2] * k) / 2 - vb[0] * k, dy = (size.height - vb[3] * k) / 2 - vb[1] * k
  return CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: dx, ty: dy)
}

/// ガイドの姿勢の図（スタート／フィニッシュ）と、記録画面のアイコン
struct FigureView: View {
  @Environment(\.skin) private var skin
  var figure: Figure
  /// アイコンとして描く（線を太く、器具をアクセント色に）
  var icon = false

  var body: some View {
    let p = skin.palette
    Canvas { ctx, size in
      let base = fit(figure.vb, in: size)
      // 床（y=146）を中心に拡大する
      let sc = figure.sc
      let inner = CGAffineTransform(translationX: 80, y: 146).scaledBy(x: sc, y: sc).translatedBy(x: -80, y: -146).concatenating(base)
      let gear = icon ? p.c(p.accent) : p.c(p.muted)
      for s in figure.items {
        let t = s.layer == "floor" ? base : inner
        let k = t.a
        var ink: Color
        var sw: Double
        switch s.layer {
        case "body", "ghost": ink = p.c(p.ink); sw = icon ? 13 : 5.5
        case "arrow": ink = p.c(p.accent); sw = 3
        case "floor": ink = p.c(p.line); sw = 2
        default: ink = gear; sw = s.sw ?? 1
        }
        if s.layer == "ghost" { ink = ink.opacity(0.2) }
        let style = StrokeStyle(lineWidth: sw * k, lineCap: .round, lineJoin: .round)
        switch s.k {
        case "line", "polyline":
          ctx.stroke(Path { $0.addLines(s.points.map { $0.applying(t) }) }, with: .color(ink), style: style)
        case "polygon":
          ctx.fill(Path { $0.addLines(s.points.map { $0.applying(t) }); $0.closeSubpath() }, with: .color(ink))
        case "circle":
          let r = (s.layer == "body" && icon ? 11 : s.r ?? 0)
          let c = CGPoint(x: s.cx ?? 0, y: s.cy ?? 0).applying(t)
          let path = Path(ellipseIn: CGRect(x: c.x - r * k, y: c.y - r * k, width: 2 * r * k, height: 2 * r * k))
          // 頭と器具の塗りの丸は塗る。それ以外（プレートなど）は輪郭だけ
          if s.layer == "body" || s.layer == "ghost" || s.solid == true { ctx.fill(path, with: .color(ink)) } else { ctx.stroke(path, with: .color(ink), style: style) }
        case "rect":
          let o = CGPoint(x: s.x ?? 0, y: s.y ?? 0).applying(t)
          let rect = CGRect(x: o.x, y: o.y, width: (s.w ?? 0) * k, height: (s.h ?? 0) * k)
          ctx.fill(Path(roundedRect: rect, cornerRadius: (s.rx ?? 0) * k), with: .color(ink))
        default: break
        }
      }
    }
    .accessibilityHidden(true)
  }
}

private extension FigureShape {
  var points: [CGPoint] { (p ?? []).map { CGPoint(x: $0[0], y: $0[1]) } }
}

/// 記録画面の種目名の前に出すアイコン。ガイドに無い種目はダンベルの絵
struct ExerciseIcon: View {
  @Environment(\.skin) private var skin
  var name: String
  var size: CGFloat = 30

  var body: some View {
    Group {
      if let g = Catalog.shared.guide[name] {
        FigureView(figure: g.icon, icon: true)
      } else {
        Canvas { ctx, sz in
          let k = sz.width / 24
          var p = Path()
          for (a, b) in [((6.5, 7.0), (6.5, 17.0)), ((17.5, 7.0), (17.5, 17.0)), ((3.5, 9.5), (3.5, 14.5)), ((20.5, 9.5), (20.5, 14.5)), ((6.5, 12.0), (17.5, 12.0))] {
            p.move(to: CGPoint(x: a.0 * k, y: a.1 * k)); p.addLine(to: CGPoint(x: b.0 * k, y: b.1 * k))
          }
          ctx.stroke(p, with: .color(skin.palette.c(skin.palette.accent)), style: StrokeStyle(lineWidth: 2.4 * k, lineCap: .round))
        }
        .padding(2)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

// MARK: 人体図

/// SVG のパス（M / L / Q / Z だけ）を Path にする
enum SVGPath {
  static func parse(_ d: String) -> Path {
    var path = Path()
    var nums: [Double] = [], cmd: Character = "M"
    func flush() {
      switch cmd {
      case "M": if nums.count >= 2 { path.move(to: CGPoint(x: nums[0], y: nums[1])) }
      case "L": if nums.count >= 2 { path.addLine(to: CGPoint(x: nums[0], y: nums[1])) }
      case "Q": if nums.count >= 4 { path.addQuadCurve(to: CGPoint(x: nums[2], y: nums[3]), control: CGPoint(x: nums[0], y: nums[1])) }
      default: break
      }
      nums = []
    }
    var token = ""
    func push() { if let v = Double(token) { nums.append(v) }; token = "" }
    for ch in d {
      if "MLQZ".contains(ch) {
        push(); flush()
        if ch == "Z" { path.closeSubpath() }
        cmd = ch
      } else if ch == " " || ch == "," {
        push()
      } else {
        token.append(ch)
      }
    }
    push(); flush()
    return path
  }
}

/// 前・後の2体の人体図。level は筋肉ごとの色の濃さ（0〜4）。onTap を渡すと部位を押せる
struct BodyMapView: View {
  @Environment(\.skin) private var skin
  var level: (String) -> Int
  var selected: String?
  var labels = true
  var onTap: ((String?) -> Void)?

  private struct Part { var m: String; var path: Path }

  /// 左半身を x=50 で鏡写しにした、1体ぶんのパス（100×210）
  private static let figures: [(sil: Path, mid: Path, parts: [Part])] = {
    let c = Catalog.shared
    let mirror = CGAffineTransform(translationX: 100, y: 0).scaledBy(x: -1, y: 1)
    func both(_ p: Path) -> Path { var q = p; q.addPath(p, transform: mirror); return q }
    var sil = Path(ellipseIn: CGRect(x: c.sil.ellipse[0] - c.sil.ellipse[2], y: c.sil.ellipse[1] - c.sil.ellipse[3], width: c.sil.ellipse[2] * 2, height: c.sil.ellipse[3] * 2))
    sil.addPath(both(SVGPath.parse(c.sil.path)))
    return ["front", "back"].map { v in
      let b = c.body[v]!
      var mid = Path()
      for d in b.mid { mid.addPath(SVGPath.parse(d)) }
      return (sil, mid, b.parts.map { part in
        var p = Path()
        for d in part.d { p.addPath(SVGPath.parse(d)) }
        return Part(m: part.m, path: both(p))
      })
    }
  }()

  var body: some View {
    let p = skin.palette
    let h: Double = labels ? 224 : 210
    Canvas { ctx, size in
      let k = min(size.width / 210, size.height / h)
      let ox = (size.width - 210 * k) / 2
      for (i, f) in Self.figures.enumerated() {
        let t = CGAffineTransform(translationX: ox + Double(i) * 110 * k, y: 0).scaledBy(x: k, y: k)
        ctx.fill(f.sil.applying(t), with: .color(p.c(p.mapSkin)))
        for part in f.parts {
          var path = part.path
          if part.m == "traps" { path.addPath(f.mid) }
          let shape = path.applying(t)
          ctx.fill(shape, with: .color(p.level(level(part.m))))
          let sel = part.m == selected
          ctx.stroke(shape, with: .color(sel ? p.c(p.ink) : p.c(p.surface)), style: StrokeStyle(lineWidth: (sel ? 1.6 : 0.8) * k, lineJoin: .round))
        }
        if labels {
          ctx.draw(Text(i == 0 ? "前" : "後").font(.system(size: 12 * k, weight: .bold)).foregroundStyle(p.c(p.muted)),
                   at: CGPoint(x: ox + (Double(i) * 110 + 50) * k, y: 215 * k))
        }
      }
    }
    .aspectRatio(210 / h, contentMode: .fit)
    .contentShape(Rectangle())
    .onTapGesture(coordinateSpace: .local) { pt in hit(pt) }
    .allowsHitTesting(onTap != nil)
    .background(GeometryReader { g in Color.clear.preference(key: SizeKey.self, value: g.size) })
    .onPreferenceChange(SizeKey.self) { size = $0 }
    .accessibilityElement()
    .accessibilityLabel("鍛えた部位")
  }

  @State private var size: CGSize = .zero

  private func hit(_ pt: CGPoint) {
    guard let onTap else { return }
    let h: Double = labels ? 224 : 210
    let k = min(size.width / 210, size.height / h)
    guard k > 0 else { return }
    let ox = (size.width - 210 * k) / 2
    for (i, f) in Self.figures.enumerated() {
      let local = CGPoint(x: (pt.x - ox) / k - Double(i) * 110, y: pt.y / k)
      for part in f.parts {
        var path = part.path
        if part.m == "traps" { path.addPath(f.mid) }
        if path.contains(local) { onTap(part.m); return }
      }
    }
    onTap(nil)
  }
}

private struct SizeKey: PreferenceKey {
  static let defaultValue: CGSize = .zero
  static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
