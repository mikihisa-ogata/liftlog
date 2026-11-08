import Foundation

// 集計・計算（docs/spec.md 5章）。画面から切り離して、テストで確かめられるようにする

enum Day {
  /// 端末の暦は月曜始まりかどうかに関係なく、週は月曜から数える
  static var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = .current
    c.locale = Locale(identifier: "ja_JP")
    return c
  }

  static func today(_ now: Date = .now) -> String { DateText.ymd(now, calendar: calendar) }

  static func date(_ ymd: String) -> Date? {
    let p = ymd.split(separator: "-").compactMap { Int($0) }
    guard p.count == 3 else { return nil }
    return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
  }

  static func add(_ ymd: String, days: Int) -> String {
    guard let d = date(ymd), let n = calendar.date(byAdding: .day, value: days, to: d) else { return ymd }
    return DateText.ymd(n, calendar: calendar)
  }

  static func add(_ ymd: String, months: Int) -> String {
    guard let d = date(ymd), let n = calendar.date(byAdding: .month, value: months, to: d) else { return ymd }
    return DateText.ymd(n, calendar: calendar)
  }

  /// その日を含む週の月曜
  static func weekStart(_ ymd: String) -> String {
    guard let d = date(ymd) else { return ymd }
    let wd = calendar.component(.weekday, from: d) // 日曜=1
    return add(ymd, days: -((wd + 5) % 7))
  }

  /// a から b までの日数
  static func between(_ a: String, _ b: String) -> Int {
    guard let x = date(a), let y = date(b) else { return 0 }
    return calendar.dateComponents([.day], from: x, to: y).day ?? 0
  }

  /// "M/D"
  static func short(_ ymd: String) -> String {
    let p = ymd.split(separator: "-").compactMap { Int($0) }
    return p.count == 3 ? "\(p[1])/\(p[2])" : ymd
  }

  /// "YYYY/M/D（曜）"
  static func long(_ ymd: String) -> String { String(ymd.prefix(4)) + "/" + DateText.short(ymd, calendar: calendar) }
}

enum Calc {
  /// 推定1RM（エプリー式）
  static func e1rm(_ w: Double, _ r: Int) -> Double {
    if w <= 0 || r <= 0 { return 0 }
    return r == 1 ? w : w * (1 + Double(r) / 30)
  }

  struct Summary: Equatable { var streak: Int; var week: Int; var total: Int }

  /// ヒーローのまとめ：連続 N 週・今週 N 回・累計 N 日
  static func summary(_ dates: [String], today: String) -> Summary {
    let mon = Day.weekStart(today)
    let days = Set(dates)
    let weeks = Set(days.map(Day.weekStart))
    var wk = weeks.contains(mon) ? mon : Day.add(mon, days: -7)
    var streak = 0
    while weeks.contains(wk) { streak += 1; wk = Day.add(wk, days: -7) }
    return Summary(streak: streak, week: days.filter { $0 >= mon }.count, total: days.count)
  }

  /// 週（月曜の日付）ごとの記録日数
  static func weekDays(_ dates: [String]) -> [String: Int] {
    var m: [String: Int] = [:]
    for d in Set(dates) { m[Day.weekStart(d), default: 0] += 1 }
    return m
  }

  /// 週 goal 回以上を何週続けているか。今週がまだ届いていなければ先週から数える
  static func goalStreak(_ dates: [String], goal: Int, today: String) -> Int {
    let m = weekDays(dates)
    var wk = Day.weekStart(today)
    if m[wk, default: 0] < goal { wk = Day.add(wk, days: -7) }
    var n = 0
    while m[wk, default: 0] >= goal { n += 1; wk = Day.add(wk, days: -7) }
    return n
  }

  struct PartTotal: Equatable { var sets = 0; var vol = 0.0 }

  /// 部位ごとのセット数とボリューム。回数 0 のセットは数えない。部位が決まっていない種目は「その他」
  static func partTotals(_ ws: [Workout], _ x: ExerciseSettings, catalog: Catalog = .shared) -> (t: [String: PartTotal], other: [String]) {
    var t: [String: PartTotal] = [:], other: [String] = []
    for w in ws {
      for e in w.exercises {
        let p = catalog.partOf(e.name, x) ?? "その他"
        if p == "その他", !other.contains(e.name) { other.append(e.name) }
        let sets = e.sets.filter { $0.r > 0 }
        t[p, default: .init()].sets += sets.count
        t[p, default: .init()].vol += sets.reduce(0) { $0 + $1.w * Double($1.r) }
      }
    }
    return (t, other)
  }

  /// 記録ごとに、その日に自己ベスト（推定1RM）を更新した種目。ws は新しい順
  static func prMap(_ ws: [Workout]) -> [String: Set<String>] {
    var best: [String: Double] = [:], out: [String: Set<String>] = [:]
    for w in ws.reversed() {
      var s = Set<String>()
      for e in w.exercises {
        let m = max(0, e.sets.map { e1rm($0.w, $0.r) }.max() ?? 0)
        if let b = best[e.name] {
          if m > 0, m > b { s.insert(e.name) }
          best[e.name] = max(m, b)
        } else {
          best[e.name] = m
        }
      }
      out[w.id] = s
    }
    return out
  }

  /// 筋肉ごとのセット数。主に効く筋肉は1セット、補助は0.5セット。ガイドの無い種目は unknown
  static func muscleSets(_ ws: [Workout], catalog: Catalog = .shared) -> (sets: [String: Double], unknown: [String]) {
    var sets: [String: Double] = [:], unknown: [String] = []
    for w in ws {
      for e in w.exercises {
        guard let g = catalog.guide[e.name] else {
          if !unknown.contains(e.name) { unknown.append(e.name) }
          continue
        }
        let n = Double(e.sets.count)
        for m in g.main { sets[m, default: 0] += n }
        for m in g.sub { sets[m, default: 0] += n / 2 }
      }
    }
    return (sets, unknown)
  }

  static let weekSteps: [Double] = [4, 8, 12]
  static let daySteps: [Double] = [3, 5, 8]

  /// 色の濃さ（0〜4）
  static func level(_ n: Double, _ steps: [Double]) -> Int {
    n > 0 ? 1 + steps.filter { n >= $0 }.count : 0
  }

  /// その種目の前回の記録。編集中の記録自身と、下書きの日付より後の記録は除く。ws は新しい順
  static func lastSession(_ name: String, in ws: [Workout], draftId: String?, draftDate: String) -> (date: String, sets: [SetRecord])? {
    for w in ws where w.id != draftId && w.date <= draftDate {
      if let e = w.exercises.first(where: { $0.name == name }) { return (w.date, e.sets) }
    }
    return nil
  }

  /// ルーティンの名前の初期値：部位が1〜2種類なら「胸トレ」「胸・腕トレ」、それ以外は「ルーティン」。同名があれば番号を足す
  static func routineName(_ names: [String], used: Set<String>, _ x: ExerciseSettings, catalog: Catalog = .shared) -> String {
    var parts: [String] = []
    for p in names.compactMap({ catalog.partOf($0, x) }) where !parts.contains(p) { parts.append(p) }
    let base = !parts.isEmpty && parts.count <= 2 ? parts.joined(separator: "・") + "トレ" : "ルーティン"
    if !used.contains(base) { return base }
    var i = 2
    while used.contains("\(base) \(i)") { i += 1 }
    return "\(base) \(i)"
  }

  /// 種目ごとの記録回数
  static func exCounts(_ ws: [Workout]) -> [String: Int] {
    var c: [String: Int] = [:]
    for w in ws { for e in w.exercises { c[e.name, default: 0] += 1 } }
    return c
  }

  /// 記録回数の多い順（同数は先に出てきた順）
  static func namesByCount(_ ws: [Workout]) -> [String] {
    var order: [String] = []
    for w in ws { for e in w.exercises where !order.contains(e.name) { order.append(e.name) } }
    let c = exCounts(ws)
    return order.enumerated().sorted { c[$0.element]! != c[$1.element]! ? c[$0.element]! > c[$1.element]! : $0.offset < $1.offset }.map(\.element)
  }

  /// グラフの目盛りの刻み（1/2/5×10^n）
  static func niceStep(_ raw: Double) -> Double {
    guard raw > 0, raw.isFinite else { return 1 }
    let p = pow(10, floor(log10(raw)))
    let n = raw / p
    return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p
  }

  /// グラフの縦軸：値の範囲に上下 12% の余白を足し、約4本の目盛りを付ける
  static func chartScale(_ values: [Double]) -> (lo: Double, hi: Double, ticks: [Double]) {
    var lo = values.min() ?? 0, hi = values.max() ?? 1
    if lo == hi {
      lo *= 0.9
      hi = hi * 1.1 == 0 ? 1 : hi * 1.1
    }
    let pad = (hi - lo) * 0.12
    let y0 = max(0, lo - pad), y1 = hi + pad
    let step = niceStep((y1 - y0) / 4)
    return (y0, y1, Array(stride(from: ceil(y0 / step) * step, through: y1, by: step)))
  }

  struct WeightPoint: Equatable { var date: String; var w: Double; var fat: Double?; var avg: Double }

  /// 体重を古い順に並べ、7日移動平均（その日を含む直近7日に記録した体重の平均）を付ける
  static func bwSeries(_ list: [(date: String, w: Double, fat: Double?)]) -> [WeightPoint] {
    let l = list.filter { $0.w > 0 }.sorted { $0.date < $1.date }
    var j = 0, sum = 0.0, out: [WeightPoint] = []
    for (i, p) in l.enumerated() {
      sum += p.w
      let from = Day.add(p.date, days: -6)
      while l[j].date < from { sum -= l[j].w; j += 1 }
      out.append(.init(date: p.date, w: p.w, fat: p.fat, avg: sum / Double(i - j + 1)))
    }
    return out
  }

  static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
}

enum Fmt {
  /// 整数で桁区切り（ボリューム）
  static func n(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "ja_JP")
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: v.rounded())) ?? String(Int(v.rounded()))
  }

  /// 重量・体重は小数1桁まで、末尾の .0 は付けない
  static func w(_ v: Double) -> String { SetText.weight(v) }

  /// 先週との差：+N / −N / ±0
  static func diff(_ a: Double, _ b: Double, unit: String = "") -> String {
    if a == b { return "±0\(unit)" }
    return (a > b ? "+" : "−") + n(abs(a - b)) + unit
  }

  /// "m:ss"
  static func clock(_ s: Int) -> String { "\(s / 60):" + String(format: "%02d", s % 60) }
}

enum SetText {
  /// 重量は小数1桁まで、末尾の .0 は付けない（Web 版の fmtW）
  static func weight(_ w: Double) -> String {
    let v = (w * 10).rounded() / 10
    if v == v.rounded() { return String(Int(v)) }
    return String(format: "%.1f", v)
  }

  /// "60×8 · 自重×10"（Web 版の setsText）
  static func summary(_ sets: [SetRecord]) -> String {
    sets.map { ($0.w != 0 ? weight($0.w) + "×" : "自重×") + String($0.r) }.joined(separator: " · ")
  }
}
