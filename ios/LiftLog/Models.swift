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

/// 体の写真。JPEG（長辺1080px）をそのまま持つ。バックアップには含めない
@Model
final class Photo {
  @Attribute(.unique) var id: String
  var date: String
  var memo: String
  @Attribute(.externalStorage) var jpeg: Data
  /// エポックミリ秒
  var createdAt: Double
  var isExample: Bool

  init(id: String, date: String, memo: String, jpeg: Data, createdAt: Double, isExample: Bool = false) {
    self.id = id
    self.date = date
    self.memo = memo
    self.jpeg = jpeg
    self.createdAt = createdAt
    self.isExample = isExample
  }
}

/// 記録タブで入力中の内容（下書き）。重量・回数は入力欄の文字のまま持つ
struct Draft: Codable, Equatable {
  struct SetRow: Codable, Equatable, Identifiable {
    var id = UUID()
    var w: String
    var r: String
    /// 「済」チェック。入力中の目印で、保存する中身には影響しない
    var done = false
  }
  struct Exercise: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var sets: [SetRow]
    var closed = false
  }
  /// 編集中の記録の id。新規は nil
  var id: String?
  var date: String
  var exercises: [Exercise] = []
  var memo = ""

  static func blank(_ today: String) -> Draft { Draft(id: nil, date: today) }

  var isEmpty: Bool { id == nil && exercises.isEmpty && memo.isEmpty }
}

/// 新しい id。Web 版と同じ "接頭辞-base36時刻+乱数4文字"
enum NewId {
  static func make(_ prefix: String, now: Date = .now) -> String {
    let ms = Int64(now.timeIntervalSince1970 * 1000)
    let rand = (0..<4).map { _ in String("0123456789abcdefghijklmnopqrstuvwxyz".randomElement()!) }.joined()
    return prefix + "-" + String(ms, radix: 36) + rand
  }
}

extension Workout {
  /// 記録の並び順：日付の新しい順 → 作成時刻の新しい順
  static let newestFirst = [SortDescriptor(\Workout.date, order: .reverse), SortDescriptor(\Workout.createdAt, order: .reverse)]
}

enum LiftLogSchema {
  static let models: [any PersistentModel.Type] = [Workout.self, Routine.self, BodyWeight.self, Photo.self]
}
