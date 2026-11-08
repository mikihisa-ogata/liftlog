import ActivityKit
import Foundation

/// ロック画面・Dynamic Island のライブアクティビティを、下書きと休憩タイマーに合わせて出し入れする。
/// 今日の下書きにセットがある間だけ出し、保存・クリアしたら消す
@MainActor
enum LiveWorkout {
  private static var activityID: String?
  private static var last: WorkoutAttributes.ContentState?
  private static var scheduled = false

  // MARK: 中身

  /// 次にやるセット（種目・セットの位置）。最後に済にしたセットより後ろで、まだ済でない最初のセット。
  /// 後ろになければ先頭から探す
  static func nextSet(_ d: Draft) -> (ex: Int, set: Int)? {
    let all = d.exercises.indices.flatMap { i in d.exercises[i].sets.indices.map { (ex: i, set: $0) } }
    let isDone = { (p: (ex: Int, set: Int)) in d.exercises[p.ex].sets[p.set].done }
    let lastDone = all.lastIndex(where: isDone) ?? -1
    return all[(lastDone + 1)...].first { !isDone($0) } ?? all.first { !isDone($0) }
  }

  static func state(_ app: AppState) -> WorkoutAttributes.ContentState? {
    let d = app.draft
    let sets = d.exercises.flatMap(\.sets)
    guard !sets.isEmpty, d.date == Day.today(app.clock()) else { return nil }
    let next = nextSet(d).map { p in
      let e = d.exercises[p.ex], s = e.sets[p.set]
      return WorkoutAttributes.NextSet(exID: e.id.uuidString, setID: s.id.uuidString, name: e.name,
                                       number: p.set + 1, count: e.sets.count, w: s.w, r: s.r)
    }
    let p = app.skin.palette
    return .init(next: next, doneSets: sets.filter(\.done).count, totalSets: sets.count,
                 restEnd: app.rest?.end, restTotal: app.rest?.total ?? 0, accent: p.accent, accentInk: p.accentInk)
  }

  // MARK: 出し入れ

  /// 下書き・休憩・テーマが変わったら呼ぶ。同じ瞬間の変更はまとめて1回にする
  static func schedule(_ app: AppState) {
    guard !scheduled else { return }
    scheduled = true
    Task {
      scheduled = false
      await sync(app)
    }
  }

  static func sync(_ app: AppState) async {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    // ロック画面で横にスワイプして消されたら、次に前面に来たとき出し直す
    if let id = activityID, !Activity<WorkoutAttributes>.activities.contains(where: { $0.id == id && $0.activityState == .active }) {
      activityID = nil
      last = nil
    }
    if activityID == nil {
      // 前回起動したときのものが残っていれば引き継ぎ、余分なものは消す
      let ids = Activity<WorkoutAttributes>.activities.map(\.id)
      activityID = ids.first
      for id in ids.dropFirst() { await end(id) }
    }
    guard let s = state(app) else {
      last = nil
      if let id = activityID {
        activityID = nil
        await end(id)
      }
      return
    }
    guard s != last else { return }
    let content = ActivityContent(state: s, staleDate: s.restEnd)
    if let id = activityID {
      last = s
      await update(id, content)
    } else if app.isActive {
      // 新しく出せるのはアプリが前面にあるときだけ
      activityID = (try? Activity.request(attributes: WorkoutAttributes(), content: content))?.id
      if activityID != nil { last = s }
    }
  }

  // Activity は Sendable でないので、メインアクターの外で id から引き直して操作する
  private nonisolated static func update(_ id: String, _ content: ActivityContent<WorkoutAttributes.ContentState>) async {
    await Activity<WorkoutAttributes>.activities.first { $0.id == id }?.update(content)
  }

  private nonisolated static func end(_ id: String) async {
    await Activity<WorkoutAttributes>.activities.first { $0.id == id }?.end(nil, dismissalPolicy: .immediate)
  }

  // MARK: ロック画面のボタン

  static func complete(exID: String, setID: String) async {
    let app = AppState.shared
    if let e = app.draft.exercises.first(where: { $0.id.uuidString == exID }),
       let s = e.sets.first(where: { $0.id.uuidString == setID }), !s.done {
      app.toggleDone(e.id, s.id)
    }
    await sync(app)
  }

  static func adjustRest(_ sec: Int) async {
    let app = AppState.shared
    app.adjustRest(Double(sec))
    await sync(app)
  }

  static func stopRest() async {
    let app = AppState.shared
    app.stopRest()
    await sync(app)
  }
}
