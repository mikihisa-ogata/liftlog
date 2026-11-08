import SwiftData
import XCTest
@testable import LiftLog

/// 集計・計算が Web 版（docs/spec.md 5章）と同じ結果になるか
@MainActor
final class CalcTests: XCTestCase {
  private func w(_ id: String, _ date: String, _ ex: [(String, [(Double, Int)])], createdAt: Double = 0) -> Workout {
    Workout(id: id, date: date, exercises: ex.map { ExerciseRecord(name: $0.0, sets: $0.1.map { SetRecord(w: $0.0, r: $0.1) }) }, createdAt: createdAt)
  }

  func testE1RM() {
    XCTAssertEqual(Calc.e1rm(0, 5), 0)
    XCTAssertEqual(Calc.e1rm(60, 0), 0)
    XCTAssertEqual(Calc.e1rm(100, 1), 100)
    XCTAssertEqual(Calc.e1rm(60, 10), 80, accuracy: 1e-9)
  }

  func testWeekStartIsMonday() {
    XCTAssertEqual(Day.weekStart("2026-11-08"), "2026-11-02") // 日曜
    XCTAssertEqual(Day.weekStart("2026-11-02"), "2026-11-02") // 月曜
    XCTAssertEqual(Day.weekStart("2026-11-07"), "2026-11-02") // 土曜
  }

  func testSummaryCountsDaysAndStreak() {
    // 今週（11/2〜）は2日、先週・先々週も記録あり、その前は空き
    let dates = ["2026-11-08", "2026-11-08", "2026-11-03", "2026-10-28", "2026-10-20", "2026-10-01"]
    XCTAssertEqual(Calc.summary(dates, today: "2026-11-08"), .init(streak: 3, week: 2, total: 5))
    // 今週まだ記録がなければ先週から数える
    XCTAssertEqual(Calc.summary(["2026-10-28", "2026-10-20"], today: "2026-11-08").streak, 2)
  }

  func testGoalStreak() {
    let dates = ["2026-11-03", "2026-10-27", "2026-10-28", "2026-10-20", "2026-10-21"]
    // 今週は1回なので目標2回に届かず、先週から数える
    XCTAssertEqual(Calc.goalStreak(dates, goal: 2, today: "2026-11-08"), 2)
    XCTAssertEqual(Calc.goalStreak(dates, goal: 1, today: "2026-11-08"), 3)
  }

  func testPRMapSkipsFirstSession() {
    let ws = [
      w("c", "2026-10-03", [("ベンチプレス", [(62.5, 8)]), ("懸垂", [(0, 10)])]),
      w("b", "2026-10-02", [("ベンチプレス", [(60, 8)])]),
      w("a", "2026-10-01", [("ベンチプレス", [(60, 8)]), ("懸垂", [(0, 8)])]),
    ]
    let m = Calc.prMap(ws)
    XCTAssertEqual(m["a"], [])
    XCTAssertEqual(m["b"], [])          // 同じ値は更新ではない
    XCTAssertEqual(m["c"], ["ベンチプレス"]) // 自重は推定1RMが0なので付かない
  }

  func testMuscleSetsAndLevel() {
    let ms = Calc.muscleSets([w("a", "2026-10-01", [("ベンチプレス", [(60, 8), (60, 8)]), ("謎の種目", [(1, 1)])])])
    XCTAssertEqual(ms.sets["chest"], 2)
    XCTAssertEqual(ms.sets["triceps"], 1)
    XCTAssertEqual(ms.unknown, ["謎の種目"])
    XCTAssertEqual(Calc.level(0, Calc.weekSteps), 0)
    XCTAssertEqual(Calc.level(0.5, Calc.weekSteps), 1)
    XCTAssertEqual(Calc.level(8, Calc.weekSteps), 3)
    XCTAssertEqual(Calc.level(12, Calc.weekSteps), 4)
  }

  func testPartTotals() {
    let x = ExerciseSettings(hidden: [], own: ["胸": ["スミスマシンベンチ"]])
    let r = Calc.partTotals([w("a", "2026-10-01", [("ベンチプレス", [(60, 8), (60, 0)]), ("スミスマシンベンチ", [(40, 10)]), ("謎", [(10, 1)])])], x)
    XCTAssertEqual(r.t["胸"], .init(sets: 2, vol: 880))
    XCTAssertEqual(r.t["その他"], .init(sets: 1, vol: 10))
    XCTAssertEqual(r.other, ["謎"])
  }

  func testLastSessionSkipsEditedAndFuture() {
    let ws = [w("new", "2026-10-10", [("スクワット", [(100, 5)])]), w("old", "2026-10-01", [("スクワット", [(80, 5)])])]
    XCTAssertEqual(Calc.lastSession("スクワット", in: ws, draftId: nil, draftDate: "2026-10-11")?.sets.first?.w, 100)
    XCTAssertEqual(Calc.lastSession("スクワット", in: ws, draftId: "new", draftDate: "2026-10-11")?.sets.first?.w, 80)
    XCTAssertEqual(Calc.lastSession("スクワット", in: ws, draftId: nil, draftDate: "2026-10-05")?.sets.first?.w, 80)
    XCTAssertNil(Calc.lastSession("ベンチプレス", in: ws, draftId: nil, draftDate: "2026-10-11"))
  }

  func testRoutineName() {
    let x = ExerciseSettings()
    XCTAssertEqual(Calc.routineName(["ベンチプレス", "ディップス"], used: [], x), "胸トレ")
    XCTAssertEqual(Calc.routineName(["ベンチプレス", "バーベルカール"], used: [], x), "胸・腕トレ")
    XCTAssertEqual(Calc.routineName(["ベンチプレス", "バーベルカール", "スクワット"], used: [], x), "ルーティン")
    XCTAssertEqual(Calc.routineName([], used: [], x), "ルーティン")
    XCTAssertEqual(Calc.routineName(["ベンチプレス"], used: ["胸トレ", "胸トレ 2"], x), "胸トレ 3")
  }

  func testBodyweightMovingAverage() {
    let s = Calc.bwSeries([("2026-10-01", 70, nil), ("2026-10-05", 72, 15), ("2026-10-08", 74, nil), ("2026-10-02", 0, nil)])
    XCTAssertEqual(s.map(\.date), ["2026-10-01", "2026-10-05", "2026-10-08"])
    XCTAssertEqual(s[1].avg, 71)
    XCTAssertEqual(s[2].avg, 73) // 10/1 は7日の外
  }

  func testChartScaleAndFormat() {
    XCTAssertEqual(Calc.niceStep(3.2), 5)
    XCTAssertEqual(Calc.niceStep(0.15), 0.2)
    let s = Calc.chartScale([60, 80])
    XCTAssertEqual(s.lo, 57.6, accuracy: 1e-9)
    XCTAssertEqual(s.ticks, [60, 70, 80])
    XCTAssertEqual(Fmt.diff(5, 3), "+2")
    XCTAssertEqual(Fmt.diff(3, 5, unit: "kg"), "−2kg")
    XCTAssertEqual(Fmt.diff(3, 3), "±0")
    XCTAssertEqual(Fmt.n(12345.4), "12,345")
    XCTAssertEqual(Fmt.w(-1.25), "-1.3")
    XCTAssertEqual(Fmt.clock(95), "1:35")
  }

  func testCatalogMatchesWeb() {
    let c = Catalog.shared
    XCTAssertEqual(c.partNames, ["胸", "肩", "背中", "腕", "腹", "脚"])
    XCTAssertEqual(c.parts.flatMap(\.exercises).count, 50)
    XCTAssertEqual(c.guide.count, 50)
    XCTAssertEqual(c.muscles.count, 15)
    let x = ExerciseSettings(hidden: ["ディップス"], own: ["胸": ["スミスマシンベンチ"]])
    XCTAssertEqual(c.shownOf("胸", x).last, "スミスマシンベンチ")
    XCTAssertFalse(c.shownOf("胸", x).contains("ディップス"))
    XCTAssertEqual(c.partOf("スミスマシンベンチ", x), "胸")
  }

  func testSeedSessions() {
    let s = Seed.sessions()
    XCTAssertEqual(s.count, 34) // 12週 × 3 − 休み2日
    XCTAssertEqual(s.first?.exercises.first?.name, "デッドリフト")
    XCTAssertEqual(s.last?.daysAgo, 5)
  }
}

/// 下書きの操作（docs/spec.md 2.2）
@MainActor
final class DraftTests: XCTestCase {
  private var container: ModelContainer!
  private var defaults: UserDefaults!

  override func setUp() async throws {
    container = try ModelContainer(for: Schema(LiftLogSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    defaults = UserDefaults(suiteName: "DraftTests")!
    defaults.removePersistentDomain(forName: "DraftTests")
  }

  func testAddExerciseCopiesLastSessionAndSaveFiltersEmptySets() throws {
    let ctx = container.mainContext
    let prev = Workout(id: "w-1", date: "2026-10-01", exercises: [ExerciseRecord(name: "ベンチプレス", sets: [SetRecord(w: 57.5, r: 8)])], createdAt: 1)
    ctx.insert(prev)
    let app = AppState(defaults: defaults)
    app.draft = Draft(id: nil, date: "2026-10-05")
    app.addExercise("ベンチプレス", workouts: [prev])
    XCTAssertEqual(app.draft.exercises[0].sets.map(\.w), ["57.5"])
    XCTAssertEqual(app.toastText, "ベンチプレスを追加（前回の内容を入力済み）")

    app.addExercise(" 懸垂 ", workouts: [prev])
    XCTAssertEqual(app.draft.exercises.map(\.name), ["ベンチプレス", "懸垂"])
    XCTAssertTrue(app.draft.exercises[0].closed)
    XCTAssertEqual(app.draft.exercises[1].sets.count, 1)

    // セット追加は直前の行をコピー
    let ex = app.draft.exercises[0].id
    app.addSet(ex)
    app.draft.exercises[0].sets[1].r = "6.6"
    XCTAssertEqual(app.draft.exercises[0].sets[1].w, "57.5")

    XCTAssertTrue(app.saveDraft(context: ctx, workouts: [prev]))
    let all = try ctx.fetch(FetchDescriptor<Workout>(sortBy: Workout.newestFirst))
    XCTAssertEqual(all.count, 2)
    // 回数の入っていない懸垂は捨て、6.6 回は 7 回に丸める
    XCTAssertEqual(all[0].exercises, [ExerciseRecord(name: "ベンチプレス", sets: [SetRecord(w: 57.5, r: 8), SetRecord(w: 57.5, r: 7)])])
    XCTAssertTrue(app.draft.exercises.isEmpty)
    XCTAssertEqual(app.tab, .history)
  }

  func testSaveWithoutRepsIsRejected() {
    let app = AppState(defaults: defaults)
    app.draft = Draft(id: nil, date: "2026-10-05", exercises: [.init(name: "スクワット", sets: [.init(w: "100", r: "")])])
    XCTAssertFalse(app.saveDraft(context: container.mainContext, workouts: []))
    XCTAssertEqual(app.toastText, "回数が入ったセットがありません。回数を入れてから保存してください")
  }

  func testDraftPersistsAndEmptyDraftMovesToToday() {
    let app = AppState(defaults: defaults)
    app.draft = Draft(id: nil, date: "2020-01-01")
    let again = AppState(defaults: defaults)
    XCTAssertEqual(again.draft.date, Day.today())
    again.draft.memo = "眠い"
    again.draft.date = "2020-01-01"
    XCTAssertEqual(AppState(defaults: defaults).draft.date, "2020-01-01")
  }

  func testRestAdjust() {
    let app = AppState(defaults: defaults)
    let t0 = Date(timeIntervalSince1970: 1000)
    app.clock = { t0 }
    app.restSec = 60
    app.startRest()
    app.adjustRest(15)
    XCTAssertEqual(app.rest?.end, t0.addingTimeInterval(75))
    XCTAssertEqual(app.rest?.total, 75)
    app.adjustRest(-30)
    XCTAssertEqual(app.rest?.total, 75)
    app.clock = { t0.addingTimeInterval(200) }
    app.checkRest()
    XCTAssertNil(app.rest)
    XCTAssertEqual(app.toastText, "休憩は終わっています")
  }
}
