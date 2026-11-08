import SwiftData
import SwiftUI

// ガイドタブ（docs/spec.md 2.10）

struct GuideView: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin

  var body: some View {
    @Bindable var app = app
    let p = skin.palette
    let c = Catalog.shared
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        PartChips(selection: $app.guidePart)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
          ForEach(c.presets(app.guidePart).filter { c.guide[$0] != nil }, id: \.self) { n in
            let g = c.guide[n]!
            Button { app.guide = GuideRequest(name: n, fromLog: false) } label: {
              VStack(alignment: .leading, spacing: 6) {
                FigureView(figure: g.finish).aspectRatio(160 / 150, contentMode: .fit)
                  .overlay(alignment: .topLeading) { ViewTag(front: g.front) }
                Text(n).font(.subheadline.bold()).foregroundStyle(p.c(p.ink)).multilineTextAlignment(.leading)
                Text(g.main.map(c.muscleName).joined(separator: "・")).font(.caption2).foregroundStyle(p.c(p.muted)).multilineTextAlignment(.leading)
              }
              .padding(10)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
              .background(p.c(p.surface), in: RoundedRectangle(cornerRadius: p.radius))
              .overlay { if skin != .plate { RoundedRectangle(cornerRadius: p.radius).strokeBorder(p.c(p.line)) } }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(n)
          }
        }
      }
      .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
    }
    .background(p.c(p.bg))
  }
}

/// 図の左上の「前から／横から」
private struct ViewTag: View {
  @Environment(\.skin) private var skin
  var front: Bool
  var body: some View {
    Text(front ? "前から" : "横から").font(.system(size: 10, weight: .bold))
      .padding(.horizontal, 5).padding(.vertical, 2)
      .foregroundStyle(skin.palette.c(skin.palette.muted))
      .background(skin.palette.c(skin.palette.field), in: RoundedRectangle(cornerRadius: 4))
  }
}

struct GuideSheet: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  @Environment(\.dismiss) private var dismiss
  @Query(sort: Workout.newestFirst) private var workouts: [Workout]
  var request: GuideRequest

  var body: some View {
    let p = skin.palette
    let c = Catalog.shared
    if let g = c.guide[request.name] {
      SheetFrame(title: request.name) {
        Note("器具：\(g.gear)")
        HStack(spacing: 10) {
          pose("① スタート", g.start, g.front)
          pose("② フィニッシュ", g.finish, g.front)
        }
        Note((g.note.isEmpty ? "" : g.note + "。") + "薄い線がスタートの姿勢、矢印が動く向き")
        SectionTitle(text: "効く部位")
        HStack(alignment: .top, spacing: 14) {
          BodyMapView(level: { g.main.contains($0) ? 4 : g.sub.contains($0) ? 2 : 0 }).frame(width: 150)
          VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
              ForEach(g.main, id: \.self) { m in chip(c.muscleName(m), level: 4) }
              ForEach(g.sub, id: \.self) { m in chip(c.muscleName(m), level: 2) }
            }
            Note("濃い色：主に効く\n薄い色：補助で使う")
          }
        }
        SectionTitle(text: "やり方")
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(g.steps.enumerated()), id: \.offset) { i, s in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text("\(i + 1)").font(skin.num(17)).foregroundStyle(p.c(p.accent)).frame(width: 18)
              Text(s).fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        SectionTitle(text: "ポイント")
        VStack(alignment: .leading, spacing: 8) {
          ForEach(g.tips, id: \.self) { s in
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text("・").foregroundStyle(p.c(p.accent))
              Text(s).fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        if !request.fromLog {
          Button("記録に追加") {
            dismiss()
            app.setTab(.log)
            app.addExercise(request.name, workouts: workouts)
          }
          .skinButton(.primary)
        }
      }
      .foregroundStyle(p.c(p.ink))
    }
  }

  private func pose(_ label: String, _ f: Figure, _ front: Bool) -> some View {
    let p = skin.palette
    return VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.caption.bold()).foregroundStyle(p.c(p.muted))
      FigureView(figure: f).aspectRatio(160 / 150, contentMode: .fit)
        .overlay(alignment: .topLeading) { ViewTag(front: front) }
        .padding(6)
        .background(p.c(p.surface), in: RoundedRectangle(cornerRadius: min(p.radius, 12)))
        .accessibilityLabel(label.dropFirst(2) + "の姿勢")
    }
    .frame(maxWidth: .infinity)
  }

  private func chip(_ name: String, level: Int) -> some View {
    let p = skin.palette
    return Text(name).font(.caption.bold())
      .padding(.horizontal, 8).padding(.vertical, 4)
      .foregroundStyle(level == 4 ? p.c(p.accentInk) : p.c(p.ink))
      .background(p.level(level), in: Capsule())
  }
}
