import SwiftData
import XCTest
@testable import LiftLog

@MainActor
final class BackupTests: XCTestCase {
  private var container: ModelContainer!
  private var context: ModelContext { container.mainContext }
  private var defaults: UserDefaults!

  override func setUp() async throws {
    container = try ModelContainer(for: Schema(LiftLogSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    defaults = UserDefaults(suiteName: "BackupTests")!
    defaults.removePersistentDomain(forName: "BackupTests")
  }

  private func json(_ s: String) -> Data { Data(s.utf8) }

  /// Web 版で書き出したファイルと同じ形
  private let webFile = """
  {
    "app": "liftlog", "version": 1, "exportedAt": "2026-10-25T00:00:00.000Z",
    "workouts": {
      "w-1": { "date": "2026-10-20", "exercises": [{ "name": "ベンチプレス", "sets": [{ "w": 60, "r": 8 }, { "w": 57.5, "r": 7 }] }], "memo": "良い", "createdAt": 1000, "updatedAt": 2000 },
      "sample-0": { "example": true, "date": "2026-10-18", "exercises": [{ "name": "懸垂", "sets": [{ "w": 0, "r": 6 }] }], "memo": "", "createdAt": 0 },
      "bad-date": { "date": 20261019, "exercises": [] },
      "bad-ex": { "date": "2026-10-19", "exercises": "x" }
    },
    "bodyweight": { "2026-10-20": { "w": 70.2, "fat": 15.1 }, "2026-10-21": { "w": 70 }, "bad": { "w": 70 }, "2026-10-22": { "w": 0 }, "2026-10-23": { "w": "70" } },
    "routines": [
      { "id": "r-1", "name": "胸トレ", "exercises": ["ベンチプレス", "ディップス"] },
      { "id": "r-bad", "name": "壊れ", "exercises": ["ベンチプレス", 3] },
      { "name": "id なし", "exercises": [] }
    ],
    "exset": { "hidden": ["ディップス"], "own": { "胸": ["スミスマシンベンチ"] } }
  }
  """

  func testParseKeepsOnlyValidEntries() throws {
    let c = try Backup.parse(json(webFile))
    XCTAssertEqual(c.workouts.map(\.id), ["sample-0", "w-1"])
    let w = try XCTUnwrap(c.workouts.first { $0.id == "w-1" })
    XCTAssertEqual(w.date, "2026-10-20")
    XCTAssertEqual(w.exercises, [ExerciseRecord(name: "ベンチプレス", sets: [SetRecord(w: 60, r: 8), SetRecord(w: 57.5, r: 7)])])
    XCTAssertEqual(w.memo, "良い")
    XCTAssertEqual(w.createdAt, 1000)
    XCTAssertEqual(w.updatedAt, 2000)
    XCTAssertTrue(c.workouts.first { $0.id == "sample-0" }!.isExample)

    XCTAssertEqual(Set(c.bodyweight.keys), ["2026-10-20", "2026-10-21"])
    XCTAssertEqual(c.bodyweight["2026-10-20"]?.fat, 15.1)
    XCTAssertNil(c.bodyweight["2026-10-21"]?.fat)

    XCTAssertEqual(c.routines, [.init(id: "r-1", name: "胸トレ", exercises: ["ベンチプレス", "ディップス"])])
    XCTAssertEqual(c.exset, ExerciseSettings(hidden: ["ディップス"], own: ["胸": ["スミスマシンベンチ"]]))
    XCTAssertEqual(c.summary, "2件の記録と2日分の体重、1件のルーティンを読み込みました")
  }

  func testParseRejectsOtherFiles() {
    XCTAssertThrowsError(try Backup.parse(json("not json")))
    XCTAssertThrowsError(try Backup.parse(json(#"{"app":"other","workouts":{}}"#)))
    XCTAssertThrowsError(try Backup.parse(json(#"{"app":"liftlog"}"#)))
    XCTAssertThrowsError(try Backup.parse(json(#"{"app":"liftlog","workouts":[]}"#)))
  }

  func testParseNormalizesSetValues() throws {
    // 下書きの名残の文字列や、小数の回数は Web 版の保存時と同じく直す
    let c = try Backup.parse(json(#"{"app":"liftlog","workouts":{"a":{"date":"2026-01-01","exercises":[{"name":"x","sets":[{"w":"62.5","r":"8"},{"r":4.6},{"w":"abc","r":1}]}]}}}"#))
    XCTAssertEqual(c.workouts[0].exercises[0].sets, [SetRecord(w: 62.5, r: 8), SetRecord(w: 0, r: 5), SetRecord(w: 0, r: 1)])
    XCTAssertEqual(c.summary, "1件の記録を読み込みました")
  }

  func testApplyOverwritesSameIdsAndAddsTheRest() throws {
    context.insert(Workout(id: "w-1", date: "2026-10-01", exercises: [], memo: "古い", createdAt: 1))
    context.insert(Workout(id: "w-keep", date: "2026-10-02", exercises: [], createdAt: 2))
    context.insert(BodyWeight(date: "2026-10-20", w: 80))
    context.insert(Routine(id: "r-1", name: "旧", exercises: [], order: 0))
    context.insert(Routine(id: "r-0", name: "残す", exercises: ["スクワット"], order: 1))
    ExerciseSettings(hidden: ["ベンチプレス"]).save(defaults)

    try Backup.apply(try Backup.parse(json(webFile)), to: context, defaults: defaults)

    let ws = try context.fetch(FetchDescriptor<Workout>(sortBy: Workout.newestFirst))
    XCTAssertEqual(ws.map(\.id), ["w-1", "sample-0", "w-keep"])
    XCTAssertEqual(ws[0].memo, "良い")
    XCTAssertEqual(ws[0].date, "2026-10-20")

    let bws = try context.fetch(FetchDescriptor<BodyWeight>(sortBy: [SortDescriptor(\.date)]))
    XCTAssertEqual(bws.map(\.date), ["2026-10-20", "2026-10-21"])
    XCTAssertEqual(bws[0].w, 70.2)

    let rts = try context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)]))
    XCTAssertEqual(rts.map(\.name), ["胸トレ", "残す"])

    XCTAssertEqual(ExerciseSettings.load(defaults), ExerciseSettings(hidden: ["ディップス"], own: ["胸": ["スミスマシンベンチ"]]))
  }

  func testApplyAppendsNewRoutinesAfterExisting() throws {
    context.insert(Routine(id: "r-a", name: "A", exercises: [], order: 0))
    try Backup.apply(try Backup.parse(json(webFile)), to: context, defaults: defaults)
    let rts = try context.fetch(FetchDescriptor<Routine>(sortBy: [SortDescriptor(\.order)]))
    XCTAssertEqual(rts.map(\.id), ["r-a", "r-1"])
  }

  func testExportRoundTrips() throws {
    try Backup.apply(try Backup.parse(json(webFile)), to: context, defaults: defaults)
    let data = try Backup.export(from: context, defaults: defaults)

    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(root["app"] as? String, "liftlog")
    XCTAssertEqual(root["version"] as? Int, 1)
    let sample = try XCTUnwrap((root["workouts"] as? [String: Any])?["sample-0"] as? [String: Any])
    XCTAssertEqual(sample["example"] as? Bool, true)
    XCTAssertNil((root["workouts"] as? [String: Any])?["w-1"].flatMap { ($0 as? [String: Any])?["example"] })

    // 書き出したファイルを読み直すと同じ中身になる
    XCTAssertEqual(try Backup.parse(data), try Backup.parse(json(webFile)))
  }

  func testTextFormatting() {
    XCTAssertEqual(SetText.summary([SetRecord(w: 60, r: 8), SetRecord(w: 57.5, r: 7), SetRecord(w: 0, r: 10)]), "60×8 · 57.5×7 · 自重×10")
    XCTAssertEqual(DateText.short("2026-10-25"), "10/25（日）")
    XCTAssertEqual(Backup.fileName(now: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!), "liftlog-2026-01-05.json")
  }
}
