import Foundation
import SwiftData

// バックアップファイル（docs/spec.md 4.3）の読み書き。Web 版と同じ形式なので、どちらで書き出したファイルも読める

/// ファイルから取り出した中身。形の正しいものだけが入る
struct BackupContents: Equatable, Sendable {
  struct WorkoutEntry: Equatable, Sendable {
    var id: String
    var date: String
    var exercises: [ExerciseRecord]
    var memo: String
    var createdAt: Double
    var updatedAt: Double?
    var isExample: Bool
  }
  struct RoutineEntry: Equatable, Sendable {
    var id: String
    var name: String
    var exercises: [String]
  }

  var workouts: [WorkoutEntry] = []
  var bodyweight: [String: (w: Double, fat: Double?)] = [:]
  var routines: [RoutineEntry] = []
  /// nil ならファイルに無い（今の設定を残す）
  var exset: ExerciseSettings?

  static func == (a: BackupContents, b: BackupContents) -> Bool {
    a.workouts == b.workouts && a.routines == b.routines && a.exset == b.exset
      && a.bodyweight.keys == b.bodyweight.keys && a.bodyweight.allSatisfy { k, v in b.bodyweight[k]?.w == v.w && b.bodyweight[k]?.fat == v.fat }
  }

  /// 読み込み後のトースト。Web 版と同じ文言
  var summary: String {
    var s = "\(workouts.count)件の記録"
    if !bodyweight.isEmpty { s += "と\(bodyweight.count)日分の体重" }
    if !routines.isEmpty { s += "、\(routines.count)件のルーティン" }
    return s + "を読み込みました"
  }
}

enum BackupError: Error, Equatable {
  /// このアプリのバックアップではない、または壊れている
  case invalidFile
}

enum Backup {
  static let failureMessage = "読み込めませんでした。このアプリで書き出したファイルを選んでください"

  // MARK: 読み込み

  /// Web 版の読み込み（index.html の #f-import）と同じ基準で取り出す。
  /// app が "liftlog" で workouts がオブジェクトでなければ失敗。それ以外は形の正しいものだけを拾う
  static func parse(_ data: Data) throws -> BackupContents {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          root["app"] as? String == "liftlog",
          let incoming = root["workouts"] as? [String: Any]
    else { throw BackupError.invalidFile }

    var out = BackupContents()
    out.workouts = incoming.compactMap { id, v in
      guard let w = v as? [String: Any], let date = w["date"] as? String, let exs = w["exercises"] as? [Any] else { return nil }
      return .init(id: id, date: date, exercises: exs.compactMap(exercise), memo: w["memo"] as? String ?? "",
                   createdAt: number(w["createdAt"]) ?? 0, updatedAt: number(w["updatedAt"]), isExample: w["example"] as? Bool ?? false)
    }.sorted { $0.id < $1.id }

    if let bw = root["bodyweight"] as? [String: Any] {
      for (date, v) in bw {
        guard isYMD(date), let o = v as? [String: Any], let w = strictNumber(o["w"]), w > 0 else { continue }
        out.bodyweight[date] = (w, strictNumber(o["fat"]))
      }
    }

    if let rts = root["routines"] as? [Any] {
      out.routines = rts.compactMap { v in
        guard let r = v as? [String: Any], let id = r["id"] as? String, let name = r["name"] as? String,
              let exs = r["exercises"] as? [Any], let names = exs as? [String], names.count == exs.count else { return nil }
        return .init(id: id, name: name, exercises: names)
      }
    }

    if let x = root["exset"] as? [String: Any] {
      let own = (x["own"] as? [String: Any] ?? [:]).compactMapValues { $0 as? [String] }
      out.exset = ExerciseSettings(hidden: x["hidden"] as? [String] ?? [], own: own)
    }
    return out
  }

  /// セットの値は Web 版の保存時と同じく w = 数値 || 0、r = 四捨五入した整数 || 0 に直す
  private static func exercise(_ v: Any) -> ExerciseRecord? {
    guard let e = v as? [String: Any], let name = e["name"] as? String else { return nil }
    let sets = (e["sets"] as? [Any] ?? []).compactMap { s -> SetRecord? in
      guard let s = s as? [String: Any] else { return nil }
      return SetRecord(w: number(s["w"]) ?? 0, r: Int((number(s["r"]) ?? 0).rounded()))
    }
    return ExerciseRecord(name: name, sets: sets)
  }

  /// 数値か数値の文字列（下書きの名残）を読む。JS の +v に合わせる
  private static func number(_ v: Any?) -> Double? {
    if let n = strictNumber(v) { return n }
    if let s = v as? String, let n = Double(s.trimmingCharacters(in: .whitespaces)) { return n }
    return nil
  }

  /// JSON の数値だけを読む（true/false は数値にしない）
  private static func strictNumber(_ v: Any?) -> Double? {
    guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    return n.doubleValue
  }

  private static func isYMD(_ s: String) -> Bool {
    s.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil
  }

  /// 取り出した中身を保存先に入れる。
  /// 記録・体重は同じ id／日付を上書きして残りは追加、ルーティンは同じ id を置き換えて無いものを後ろに足す、種目の表示設定はファイルの側で置き換える
  @MainActor
  static func apply(_ c: BackupContents, to context: ModelContext, defaults: UserDefaults = .standard) throws {
    let workouts = try context.fetch(FetchDescriptor<Workout>())
    let byId = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    for e in c.workouts {
      if let w = byId[e.id] {
        w.date = e.date; w.exercises = e.exercises; w.memo = e.memo
        w.createdAt = e.createdAt; w.updatedAt = e.updatedAt; w.isExample = e.isExample
      } else {
        context.insert(Workout(id: e.id, date: e.date, exercises: e.exercises, memo: e.memo, createdAt: e.createdAt, updatedAt: e.updatedAt, isExample: e.isExample))
      }
    }

    let weights = Dictionary(try context.fetch(FetchDescriptor<BodyWeight>()).map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
    for (date, v) in c.bodyweight {
      if let b = weights[date] { b.w = v.w; b.fat = v.fat } else { context.insert(BodyWeight(date: date, w: v.w, fat: v.fat)) }
    }

    let routines = try context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)]))
    var next = (routines.last?.order ?? -1) + 1
    for r in c.routines {
      if let cur = routines.first(where: { $0.id == r.id }) {
        cur.name = r.name; cur.exercises = r.exercises
      } else {
        context.insert(Routine(id: r.id, name: r.name, exercises: r.exercises, order: next)); next += 1
      }
    }

    c.exset?.save(defaults)
    try context.save()
  }

  // MARK: 書き出し

  private struct File: Encodable {
    struct W: Encodable {
      var date: String
      var exercises: [ExerciseRecord]
      var memo: String
      var createdAt: Double
      var updatedAt: Double?
      var example: Bool?
    }
    struct BW: Encodable { var w: Double; var fat: Double? }
    struct R: Encodable { var id: String; var name: String; var exercises: [String] }
    var app = "liftlog"
    var version = 1
    var exportedAt: String
    var workouts: [String: W]
    var bodyweight: [String: BW]
    var routines: [R]
    var exset: ExerciseSettings
  }

  /// Web 版の「ファイルに書き出す」と同じ形式の JSON
  @MainActor
  static func export(from context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now) throws -> Data {
    let ws = try context.fetch(FetchDescriptor<Workout>())
    let bws = try context.fetch(FetchDescriptor<BodyWeight>())
    let rts = try context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)]))
    let file = File(
      exportedAt: now.formatted(.iso8601),
      workouts: Dictionary(ws.map { ($0.id, File.W(date: $0.date, exercises: $0.exercises, memo: $0.memo, createdAt: $0.createdAt, updatedAt: $0.updatedAt, example: $0.isExample ? true : nil)) }, uniquingKeysWith: { a, _ in a }),
      bodyweight: Dictionary(bws.map { ($0.date, File.BW(w: $0.w, fat: $0.fat)) }, uniquingKeysWith: { a, _ in a }),
      routines: rts.map { File.R(id: $0.id, name: $0.name, exercises: $0.exercises) },
      exset: ExerciseSettings.load(defaults))
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try enc.encode(file)
  }

  /// 書き出すファイル名（liftlog-YYYY-MM-DD.json）
  static func fileName(now: Date = .now) -> String {
    "liftlog-\(DateText.ymd(now)).json"
  }
}

enum DateText {
  /// 端末の暦・タイムゾーンでの "YYYY-MM-DD"（Web 版の ymd と同じ）
  static func ymd(_ d: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
  }

  /// "M/D（曜）"（Web 版の fmtDate）
  static func short(_ ymd: String, calendar: Calendar = .current) -> String {
    let p = ymd.split(separator: "-").compactMap { Int($0) }
    guard p.count == 3, let d = calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return ymd }
    let wd = Array("日月火水木金土")[calendar.component(.weekday, from: d) - 1]
    return "\(p[1])/\(p[2])（\(wd)）"
  }
}
