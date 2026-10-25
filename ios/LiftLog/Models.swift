import Foundation
import SwiftData

// 保存データは Web 版（docs/spec.md 4章）と同じ形で持つ。日付は "YYYY-MM-DD" の文字列のまま扱う
// （タイムゾーンで日がずれないように、また Web 版と並び順・比較を揃えるため）

/// 1セット。w=0 は自重、r は 1 以上の整数
struct SetRecord: Codable, Hashable, Sendable {
  var w: Double
  var r: Int
}

/// 1つの記録の中の1種目。種目の並び順を保つため、記録の中に配列で持つ
struct ExerciseRecord: Codable, Hashable, Sendable {
  var name: String
  var sets: [SetRecord]
}

@Model
final class Workout {
  /// Web 版の id（"w-…"、見本は "sample-N"）。バックアップの読み込みで同じ記録を上書きするのに使う
  @Attribute(.unique) var id: String
  var date: String
  var exercises: [ExerciseRecord]
  var memo: String
  /// エポックミリ秒（Web 版と同じ単位）
  var createdAt: Double
  var updatedAt: Double?
  var isExample: Bool

  init(id: String, date: String, exercises: [ExerciseRecord], memo: String = "", createdAt: Double, updatedAt: Double? = nil, isExample: Bool = false) {
    self.id = id
    self.date = date
    self.exercises = exercises
    self.memo = memo
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.isExample = isExample
  }
}

@Model
final class Routine {
  @Attribute(.unique) var id: String
  var name: String
  var exercises: [String]
  /// 一覧での並び順（Web 版の配列の位置）
  var order: Int

  init(id: String, name: String, exercises: [String], order: Int) {
    self.id = id
    self.name = name
    self.exercises = exercises
    self.order = order
  }
}

/// 1日1件の体重の記録
@Model
final class BodyWeight {
  @Attribute(.unique) var date: String
  var w: Double
  var fat: Double?

  init(date: String, w: Double, fat: Double? = nil) {
    self.date = date
    self.w = w
    self.fat = fat
  }
}

/// 記録画面に出す種目の設定。hidden は出さない既定の種目、own は部位ごとに自分で足した種目
struct ExerciseSettings: Codable, Equatable, Sendable {
  var hidden: [String] = []
  var own: [String: [String]] = [:]

  private static let key = "liftlog.exset"

  static func load(_ defaults: UserDefaults = .standard) -> ExerciseSettings {
    guard let data = defaults.data(forKey: key), let v = try? JSONDecoder().decode(ExerciseSettings.self, from: data) else { return .init() }
    return v
  }

  func save(_ defaults: UserDefaults = .standard) {
    if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
  }
}

extension Workout {
  /// 記録の並び順：日付の新しい順 → 作成時刻の新しい順
  static let newestFirst = [SortDescriptor(\Workout.date, order: .reverse), SortDescriptor(\Workout.createdAt, order: .reverse)]
}

enum LiftLogSchema {
  static let models: [any PersistentModel.Type] = [Workout.self, Routine.self, BodyWeight.self]
}
