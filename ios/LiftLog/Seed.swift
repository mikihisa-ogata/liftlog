import Foundation
import SwiftData

// 初回起動時だけ入れる見本（docs/spec.md 6章）。Web 版の seedSamples / seedRoutines と同じ中身

enum Seed {
  static let version = 2

  @MainActor
  static func run(_ context: ModelContext, defaults: UserDefaults = .standard, today: String = Day.today()) {
    workouts(context, defaults: defaults, today: today)
    routines(context, defaults: defaults)
    try? context.save()
  }

  /// 見本の記録。自分の記録がある端末と、一度入れた端末には入れない
  @MainActor
  static func workouts(_ context: ModelContext, defaults: UserDefaults, today: String) {
    let v = defaults.integer(forKey: "liftlog.seeded")
    guard v != version else { return }
    defaults.set(version, forKey: "liftlog.seeded")
    let cur = (try? context.fetch(FetchDescriptor<Workout>())) ?? []
    // 古いサンプルだけが残っている端末は入れ替え、自分の記録がある・サンプルを消した端末には入れない
    if v != 0 ? !(!cur.isEmpty && cur.allSatisfy(\.isExample)) : !cur.isEmpty { return }
    for w in cur { context.delete(w) }
    for (i, s) in sessions().enumerated() {
      context.insert(Workout(id: "sample-\(i)", date: Day.add(today, days: -s.daysAgo), exercises: s.exercises, memo: s.memo, createdAt: Double(i), isExample: true))
    }
  }

  struct Session { var daysAgo: Int; var exercises: [ExerciseRecord]; var memo: String }

  /// 12週ぶんの Push / Legs / Pull（7週目はデロード、2日は休み）。古い順
  static func sessions() -> [Session] {
    func S3(_ name: String, _ w: Double, _ r: Int, _ step: Double) -> ExerciseRecord {
      ExerciseRecord(name: name, sets: [SetRecord(w: w, r: r), SetRecord(w: w, r: max(r - 1, 1)), SetRecord(w: max(w - step, 0), r: r)])
    }
    let bench: [Double] = [55, 57.5, 57.5, 60, 60, 62.5, 55, 62.5, 62.5, 65, 65, 67.5], benchR = [8, 8, 7, 8, 6, 8, 10, 8, 7, 8, 6, 6]
    let squat: [Double] = [70, 72.5, 75, 75, 77.5, 80, 70, 80, 82.5, 82.5, 85, 87.5], squatR = [8, 8, 8, 7, 8, 6, 10, 8, 7, 8, 6, 6]
    let dead: [Double] = [90, 95, 95, 100, 97.5, 105, 90, 105, 110, 107.5, 115, 117.5], deadR = [6, 5, 6, 5, 5, 5, 8, 6, 5, 5, 4, 5]
    let memo = ["11-push": "3セット目はギリギリ", "6-push": "デロード週。軽めでフォームを確認", "9-legs": "腰に違和感なし", "8-pull": "握力が先に限界。ストラップを使う"]
    let skip: Set = ["3-legs", "6-pull"]
    var list: [Session] = []
    for i in 0..<12 {
      let base = (11 - i) * 7, up = Double(i / 3)
      let sessions: [(String, Int, [ExerciseRecord])] = [
        ("push", base + 5, [S3("ベンチプレス", bench[i], benchR[i], 5), i % 2 == 1 ? S3("サイドレイズ", 6 + up, 15, 1) : S3("ダンベルフライ", 10 + up * 2, 12, 2), S3("プレスダウン", 20 + up * 2.5, 12, 2.5)]),
        ("legs", base + 3, [S3("スクワット", squat[i], squatR[i], 5), S3("レッグカール", 30 + up * 2.5, 12, 5), S3("カーフレイズ", 30 + up * 5, 15, 5)]),
        ("pull", base + 1, [S3("デッドリフト", dead[i], deadR[i], 10), S3("懸垂", 0, 5 + i / 2, 0), S3("ベントオーバーロウ", 45 + up * 2.5, 10, 5)]),
      ]
      for (k, n, ex) in sessions where !skip.contains("\(i)-\(k)") {
        list.append(Session(daysAgo: n, exercises: ex, memo: memo["\(i)-\(k)"] ?? ""))
      }
    }
    return list.sorted { $0.daysAgo > $1.daysAgo }
  }

  /// 見本のルーティン。ルーティンを持っている端末には入れず、消しても入れ直さない
  @MainActor
  static func routines(_ context: ModelContext, defaults: UserDefaults) {
    guard !defaults.bool(forKey: "liftlog.rtSeeded") else { return }
    defaults.set(true, forKey: "liftlog.rtSeeded")
    guard ((try? context.fetchCount(FetchDescriptor<Routine>())) ?? 0) == 0 else { return }
    let list: [(String, [String])] = [
      ("胸トレ", ["ベンチプレス", "インクラインベンチプレス", "ダンベルフライ", "ディップス"]),
      ("肩トレ", ["ショルダープレス", "サイドレイズ", "リアレイズ", "フェイスプル"]),
      ("背中トレ", ["デッドリフト", "懸垂", "ラットプルダウン", "ベントオーバーロウ"]),
      ("脚トレ", ["スクワット", "レッグプレス", "ルーマニアンデッドリフト", "レッグカール", "カーフレイズ"]),
      ("腕トレ", ["バーベルカール", "ハンマーカール", "プレスダウン", "フレンチプレス"]),
      ("腹トレ", ["クランチ", "アブローラー", "ハンギングレッグレイズ"]),
    ]
    for (i, (name, ex)) in list.enumerated() {
      context.insert(Routine(id: "r-sample-\(i)", name: name, exercises: ex, order: i))
    }
  }
}
