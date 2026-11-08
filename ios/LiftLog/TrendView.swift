import Charts
import SwiftData
import SwiftUI

// 推移タブ（docs/spec.md 2.8）。SwiftUI の ProgressView と名前がぶつからないよう TrendView と呼ぶ

struct TrendView: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  @Query(sort: Workout.newestFirst) private var workouts: [Workout]
  @Query(sort: \BodyWeight.date) private var weights: [BodyWeight]
  @State private var picking = false

  var body: some View {
    @Bindable var app = app
    let p = skin.palette
    let names = Calc.namesByCount(workouts)
    let counts = Calc.exCounts(workouts)
    let current = app.progressExercise.flatMap { names.contains($0) ? $0 : nil } ?? names.first
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text("種目").font(.caption.bold()).foregroundStyle(p.c(p.muted))
          Button { picking = true } label: {
            HStack {
              if app.showWeight {
                Text("体重").font(.headline)
                if !weights.isEmpty { Text("\(weights.count)日").font(.caption).foregroundStyle(p.c(p.muted)) }
              } else if let current {
                Text(current).font(.headline)
                Text("\(counts[current] ?? 0)回").font(.caption).foregroundStyle(p.c(p.muted))
              } else {
                Text("記録なし").font(.headline)
              }
              Spacer()
              Image(systemName: "chevron.up.chevron.down").foregroundStyle(p.c(p.muted))
            }
            .field(skin)
          }
          .buttonStyle(.plain)
        }
        if app.showWeight {
          Picker("期間", selection: $app.bwRange) {
            Text("1か月").tag("1m"); Text("3か月").tag("3m"); Text("すべて").tag("all")
          }
          .pickerStyle(.segmented)
          WeightSection(weights: weights)
        } else {
          Picker("指標", selection: $app.metric) {
            Text("推定1RM").tag("e1rm"); Text("最大重量").tag("max")
          }
          .pickerStyle(.segmented)
          if let current {
            ExerciseTrend(name: current, workouts: workouts)
          } else {
            Note("記録が2回以上たまると、種目ごとに重量の伸びがグラフで見られます。体重は上のボタンから記録できます。")
          }
        }
      }
      .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(p.c(p.bg))
    .sheet(isPresented: $picking) { ExercisePickSheet(names: names, counts: counts, current: current, weightDays: weights.count) }
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("完了") { hideKeyboard() }
      }
    }
  }
}

/// 種目を選ぶ（先頭に体重、続いて部位ごとに記録のある種目）
private struct ExercisePickSheet: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  @Environment(\.dismiss) private var dismiss
  var names: [String]
  var counts: [String: Int]
  var current: String?
  var weightDays: Int

  var body: some View {
    let p = skin.palette
    let c = Catalog.shared
    let groups = Dictionary(grouping: names) { c.partOf($0, app.exset) ?? "その他" }
    SheetFrame(title: "種目を選ぶ") {
      ScrollViewReader { proxy in
        VStack(alignment: .leading, spacing: 4) {
          header("体")
          row("体重", weightDays > 0 ? "\(weightDays)日" : "", selected: app.showWeight) { app.showWeight = true }
          ForEach(c.partNames + ["その他"], id: \.self) { part in
            if let list = groups[part] {
              header(part)
              ForEach(list, id: \.self) { n in
                row(n, "\(counts[n] ?? 0)回", selected: !app.showWeight && n == current) {
                  app.showWeight = false
                  app.progressExercise = n
                }
                .id(n)
              }
            }
          }
        }
        .onAppear { if !app.showWeight, let current { proxy.scrollTo(current, anchor: .center) } }
      }
    }
    .foregroundStyle(p.c(p.ink))
  }

  private func header(_ t: String) -> some View {
    Text(t).font(.subheadline.bold()).foregroundStyle(skin.palette.c(skin.palette.muted)).padding(.top, 10)
  }

  private func row(_ name: String, _ n: String, selected: Bool, action: @escaping () -> Void) -> some View {
    let p = skin.palette
    return Button { action(); dismiss() } label: {
      HStack {
        Text(name).font(.body.bold())
        Spacer()
        Text(n).font(.caption).foregroundStyle(p.c(p.muted))
      }
      .padding(.horizontal, 12).padding(.vertical, 11)
      .background(selected ? p.c(p.accentSoft) : p.c(p.surface), in: RoundedRectangle(cornerRadius: min(p.radius, 12)))
      .overlay { if selected { RoundedRectangle(cornerRadius: min(p.radius, 12)).strokeBorder(p.c(p.accent)) } }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// 大きい数字のカード（ベスト・最新など）
private struct StatCard: View {
  @Environment(\.skin) private var skin
  var k: String
  var v: String
  var unit: String
  var d: String?

  var body: some View {
    let p = skin.palette
    VStack(alignment: .leading, spacing: 2) {
      Text(k).font(.caption.bold()).foregroundStyle(p.c(p.muted))
      HStack(alignment: .lastTextBaseline, spacing: 2) {
        Text(v).font(skin.num(28)).lineLimit(1).minimumScaleFactor(0.6)
        Text(unit).font(.caption2.bold()).foregroundStyle(p.c(p.muted))
      }
      if let d { Text(d).font(.caption2).foregroundStyle(p.c(p.muted)).lineLimit(1).minimumScaleFactor(0.7) }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(p.c(p.surface), in: RoundedRectangle(cornerRadius: p.radius))
    .overlay { if skin != .plate { RoundedRectangle(cornerRadius: p.radius).strokeBorder(p.c(p.line)) } }
    .accessibilityElement(children: .combine)
  }
}

private struct ExerciseTrend: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  var name: String
  var workouts: [Workout]

  var body: some View {
    let p = skin.palette
    let sessions = workouts.reversed().compactMap { w in w.exercises.first { $0.name == name }.map { (date: w.date, e: $0) } }
    let e1 = { (e: ExerciseRecord) in e.sets.map { Calc.e1rm($0.w, $0.r) }.max() ?? 0 }
    let mx = { (e: ExerciseRecord) in e.sets.map(\.w).max() ?? 0 }
    let metric = app.metric == "max" ? mx : e1
    let pts = sessions.map { ChartPoint(date: $0.date, v: metric($0.e)) }
    let bestE = sessions.reduce((v: 0.0, date: "")) { e1($1.e) > $0.v ? (e1($1.e), $1.date) : $0 }
    let bestW = sessions.reduce((v: 0.0, date: "")) { mx($1.e) > $0.v ? (mx($1.e), $1.date) : $0 }
    let bodyweight = bestW.v == 0
    let bestR = sessions.flatMap { $0.e.sets.map(\.r) }.max() ?? 0
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 8) {
        if bodyweight {
          StatCard(k: "最高回数", v: "\(bestR)", unit: "回")
        } else {
          StatCard(k: "推定1RM ベスト", v: Fmt.w(bestE.v), unit: "kg", d: DateText.short(bestE.date))
          StatCard(k: "最大重量", v: Fmt.w(bestW.v), unit: "kg", d: DateText.short(bestW.date))
        }
        StatCard(k: "記録した回数", v: "\(sessions.count)", unit: "回", d: sessions.first.map { "初回 \(DateText.short($0.date))" })
      }
      if bodyweight {
        Note("自重種目のため重量のグラフはありません。")
      } else {
        TrendChart(points: pts, unit: "kg", format: Fmt.n)
      }
      Note("推定1RM はエプリー式（重量 ×（1 + 回数 ÷ 30））で、その日いちばん高いセットの値です。赤い点がベスト。")
      SectionTitle(text: "最近のセッション")
      ForEach(Array(sessions.suffix(6).reversed().enumerated()), id: \.offset) { _, s in
        Card {
          HStack {
            Text(DateText.short(s.date)).font(.subheadline.bold())
            Spacer()
            Text("\(s.e.sets.count)セット").font(.caption).foregroundStyle(p.c(p.muted))
          }
          Text(SetText.summary(s.e.sets)).font(skin.num(16))
        }
      }
    }
  }
}

struct ChartPoint: Identifiable {
  var date: String
  var v: Double
  var id: String { date }
  var day: Date { Day.date(date) ?? .now }
}

/// 推移のグラフ。avg を渡すと点線で重ねる。best が false なら赤いベストの点を出さない
private struct TrendChart: View {
  @Environment(\.skin) private var skin
  var points: [ChartPoint]
  var avg: [ChartPoint]? = nil
  var best = true
  var unit: String
  var format: (Double) -> String

  var body: some View {
    let p = skin.palette
    let (y0, y1, ticks) = Calc.chartScale(points.map(\.v) + (avg?.map(\.v) ?? []))
    let bestI = best ? points.indices.max { points[$0].v < points[$1].v || (points[$0].v == points[$1].v && $0 > $1) } : nil
    let xIdx = Array(Set([0, (points.count - 1) / 2, points.count - 1])).sorted()
    let last = points.last
    Chart {
      ForEach(points) { pt in
        if points.count > 1 {
          AreaMark(x: .value("日付", pt.day), yStart: .value("下", y0), yEnd: .value(unit, pt.v))
            .foregroundStyle(p.c(p.accent).opacity(0.12))
          LineMark(x: .value("日付", pt.day), y: .value(unit, pt.v), series: .value("系列", "値"))
            .foregroundStyle(p.c(p.accent))
            .lineStyle(StrokeStyle(lineWidth: 2.5))
        }
      }
      if let avg, avg.count > 1 {
        ForEach(avg) { pt in
          LineMark(x: .value("日付", pt.day), y: .value(unit, pt.v), series: .value("系列", "平均"))
            .foregroundStyle(p.c(p.ink).opacity(0.7))
            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
        }
      }
      ForEach(Array(points.enumerated()), id: \.offset) { i, pt in
        let isBest = i == bestI, isLast = i == points.count - 1
        PointMark(x: .value("日付", pt.day), y: .value(unit, pt.v))
          .symbolSize(isBest || isLast ? 100 : 50)
          .foregroundStyle(isBest ? Color(hex: 0xe5372c) : p.c(p.accent))
          .accessibilityLabel(DateText.short(pt.date))
          .accessibilityValue("\(Fmt.w(pt.v))\(unit)")
      }
      if let last {
        PointMark(x: .value("日付", last.day), y: .value(unit, last.v))
          .opacity(0)
          .annotation(position: .trailing, spacing: 6) {
            Text(format(last.v)).font(skin.num(15)).foregroundStyle(p.c(p.ink))
          }
      }
    }
    .chartYScale(domain: y0...y1)
    .chartYAxis {
      AxisMarks(position: .leading, values: ticks) { v in
        AxisGridLine().foregroundStyle(p.c(p.line))
        AxisValueLabel { if let d = v.as(Double.self) { Text(format(d)).foregroundStyle(p.c(p.muted)) } }
      }
    }
    .chartXAxis {
      AxisMarks(values: xIdx.map { points[$0].day }) { v in
        AxisValueLabel(anchor: .top) {
          if let d = v.as(Date.self) { Text(Day.short(DateText.ymd(d, calendar: Day.calendar))).foregroundStyle(p.c(p.muted)) }
        }
      }
    }
    .chartPlotStyle { $0.padding(.trailing, 40) }
    .frame(height: 220)
    .padding(12)
    .background(p.c(p.surface), in: RoundedRectangle(cornerRadius: p.radius))
    .overlay { if skin != .plate { RoundedRectangle(cornerRadius: p.radius).strokeBorder(p.c(p.line)) } }
  }
}

// MARK: 体重

private struct WeightSection: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  @Environment(\.modelContext) private var context
  var weights: [BodyWeight]
  @State private var date = Day.today()
  @State private var w = ""
  @State private var fat = ""
  @FocusState private var weightFocus: Bool

  var body: some View {
    let p = skin.palette
    let all = Calc.bwSeries(weights.map { ($0.date, $0.w, $0.fat) })
    let from = Day.add(Day.today(), months: app.bwRange == "1m" ? -1 : -3)
    let pts = app.bwRange == "all" ? all : all.filter { $0.date >= from }
    let thisYear = Day.today().prefix(4)
    VStack(alignment: .leading, spacing: 14) {
      Card {
        HStack {
          Text("日付").font(.caption.bold()).foregroundStyle(p.c(p.muted))
          Spacer()
          DatePicker("日付", selection: Binding(get: { Day.date(date) ?? .now }, set: { date = DateText.ymd($0, calendar: Day.calendar) }),
                     in: ...Date.now, displayedComponents: .date)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "ja_JP"))
        }
        HStack(spacing: 8) {
          VStack(alignment: .leading, spacing: 4) {
            Text("体重（kg）").font(.caption.bold()).foregroundStyle(p.c(p.muted))
            TextField("", text: $w).keyboardType(.decimalPad).focused($weightFocus).field(skin)
          }
          VStack(alignment: .leading, spacing: 4) {
            Text("体脂肪率（%・任意）").font(.caption.bold()).foregroundStyle(p.c(p.muted))
            TextField("", text: $fat).keyboardType(.decimalPad).field(skin)
          }
        }
        Button("保存", action: save).skinButton(.primary)
      }
      .id("bw-form")
      if all.isEmpty {
        Note("毎日同じ条件（朝起きてトイレのあと・食事の前など）で量ると、増減の傾向がつかみやすくなります。")
      } else {
        let last = all.last!
        let dAvg = pts.count > 1 ? pts.last!.avg - pts.first!.avg : nil
        HStack(spacing: 8) {
          StatCard(k: "最新", v: Fmt.w(last.w), unit: "kg", d: DateText.short(last.date) + (last.fat.map { "・体脂肪 \(Fmt.w($0))%" } ?? ""))
          StatCard(k: "期間の増減", v: dAvg.map { ($0 > 0 ? "+" : "") + Fmt.w($0) } ?? "—", unit: dAvg == nil ? "" : "kg", d: "7日平均で比べた値")
          StatCard(k: "記録した日数", v: "\(pts.count)", unit: "日", d: "初回 \(DateText.short(all[0].date))")
        }
        if pts.isEmpty {
          Note("この期間の記録はありません。")
        } else {
          TrendChart(points: pts.map { ChartPoint(date: $0.date, v: $0.w) }, avg: pts.map { ChartPoint(date: $0.date, v: $0.avg) }, best: false, unit: "kg", format: Fmt.w)
          Note("点線は7日間の移動平均（その日までの7日間に記録した体重の平均）です。毎日の増減より、こちらの傾きを見てください。")
        }
        SectionTitle(text: "記録")
        if pts.isEmpty {
          Note("この期間の記録はありません。")
        } else {
          VStack(spacing: 0) {
            ForEach(pts.reversed(), id: \.date) { pt in
              HStack(spacing: 8) {
                Text((pt.date.prefix(4) == thisYear ? "" : pt.date.dropFirst(2).prefix(2) + "/") + Day.short(pt.date))
                  .font(.footnote).foregroundStyle(p.c(p.muted)).frame(width: 64, alignment: .leading)
                (Text(Fmt.w(pt.w)).font(skin.num(18)) + Text(" kg").font(.caption))
                Text(pt.fat.map { Fmt.w($0) + "%" } ?? "").font(skin.num(15)).foregroundStyle(p.c(p.muted))
                Spacer()
                Button("修正") { date = pt.date; weightFocus = true }.skinButton(small: true)
                Button("削除") { delete(pt.date) }.skinButton(.danger, small: true)
              }
              .padding(.vertical, 8).padding(.horizontal, 12)
              Divider().overlay(p.c(p.line))
            }
          }
          .background(p.c(p.surface), in: RoundedRectangle(cornerRadius: p.radius))
        }
      }
    }
    .onAppear(perform: fill)
    .onChange(of: date) { fill() }
    .onChange(of: weights.count) { fill() }
  }

  /// 日付を変えたら、その日の記録を入れておく
  private func fill() {
    let v = weights.first { $0.date == date }
    w = v.map { Fmt.w($0.w) } ?? ""
    fat = v?.fat.map { Fmt.w($0) } ?? ""
  }

  private func save() {
    let wv = Calc.round1(AppState.number(w)), fv = Calc.round1(AppState.number(fat))
    guard wv > 0 else { app.toast("体重を入れてください"); return }
    let had = weights.first { $0.date == date }
    if let had { had.w = wv; had.fat = fv > 0 ? fv : nil } else { context.insert(BodyWeight(date: date, w: wv, fat: fv > 0 ? fv : nil)) }
    try? context.save()
    weightFocus = false
    app.toast("\(DateText.short(date))の体重を\(had != nil ? "上書き" : "保存")しました")
    date = Day.today()
    fill()
  }

  private func delete(_ d: String) {
    app.ask("\(DateText.short(d))の体重を削除しますか？", "削除した記録は元に戻せません。同じ日の体の写真に表示される体重も消えます。", ok: "削除") {
      for b in weights where b.date == d { context.delete(b) }
      try? context.save()
      app.toast("体重の記録を削除しました")
    }
  }
}
