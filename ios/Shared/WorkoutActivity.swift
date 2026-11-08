import ActivityKit
import AppIntents
import Foundation

// ロック画面・Dynamic Island のライブアクティビティ（アプリとウィジェットの両方に入れる）

struct WorkoutAttributes: ActivityAttributes {
  /// ロック画面に出す中身。次にやるセットと休憩タイマー
  struct ContentState: Codable, Hashable {
    /// 次のセット。すべて済なら nil
    var next: NextSet?
    var doneSets: Int
    var totalSets: Int
    /// 休憩の終了時刻。休憩していなければ nil
    var restEnd: Date?
    var restTotal: Double
    /// テーマのアクセント色と、その上に載せる文字の色
    var accent: UInt32
    var accentInk: UInt32
  }

  struct NextSet: Codable, Hashable {
    var exID: String
    var setID: String
    var name: String
    /// 何セット目か（1から）と、その種目のセット数
    var number: Int
    var count: Int
    var w: String
    var r: String
  }
}

// ボタンの処理はアプリの側で動かす。ウィジェットの側は形だけ持ち、perform は何もしない
// （LiveActivityIntent はアプリとウィジェットの両方に入っていると、アプリのプロセスで実行される）

/// 「済」：次のセットを済にして休憩タイマーを始める
struct CompleteSetIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "セットを済にする"
  static let isDiscoverable = false

  @Parameter(title: "種目") var exID: String
  @Parameter(title: "セット") var setID: String

  init() {}
  init(exID: String, setID: String) {
    self.exID = exID
    self.setID = setID
  }

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    await LiveWorkout.complete(exID: exID, setID: setID)
    #endif
    return .result()
  }
}

/// 休憩を ±15秒
struct AdjustRestIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "休憩の時間を変える"
  static let isDiscoverable = false

  @Parameter(title: "秒") var seconds: Int

  init() {}
  init(seconds: Int) { self.seconds = seconds }

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    await LiveWorkout.adjustRest(seconds)
    #endif
    return .result()
  }
}

/// 休憩を終える
struct StopRestIntent: LiveActivityIntent {
  static let title: LocalizedStringResource = "休憩を終える"
  static let isDiscoverable = false

  init() {}

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    await LiveWorkout.stopRest()
    #endif
    return .result()
  }
}
