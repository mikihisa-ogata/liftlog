import AVFoundation
import Foundation
import Observation
import SwiftData
import UIKit
import UserNotifications

enum AppTab: String, CaseIterable, Sendable {
  case log, history, progress, body, guide
}

/// 確認ダイアログ。「キャンセル／（任意で2つ目の選択肢）／実行」
struct ConfirmRequest: Identifiable {
  let id = UUID()
  var title: String
  var note: String
  var ok: String
  var destructive = true
  var alt: String?
  var onOK: () -> Void
  var onAlt: (() -> Void)?
}

/// 種目ガイドの詳細を開く。fromLog は記録タブの「やり方」から開いたとき（記録に追加するボタンは出さない）
struct GuideRequest: Identifiable {
  var name: String
  var fromLog: Bool
  var id: String { name }
}

/// 休憩タイマー。残り時間は終了時刻から毎回計算する
struct RestState: Codable, Equatable {
  var end: Date
  var total: TimeInterval
}

/// 画面をまたいで使う状態（下書き・設定・トースト・休憩タイマー）。設定は UserDefaults に Web 版と同じキーで持つ
@MainActor
@Observable
final class AppState {
  private let defaults: UserDefaults
  /// アプリ本体とロック画面のボタンが共有する1つ。ライブアクティビティを出すのはこれだけ（テストで作るものは出さない）
  static let shared: AppState = {
    let a = AppState()
    a.syncsActivity = true
    return a
  }()
  private var syncsActivity = false
  /// テストでは時刻を差し替える
  var clock: () -> Date = { .now }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    tab = AppTab(rawValue: defaults.string(forKey: "liftlog.tab") ?? "") ?? .log
    skin = Skin(rawValue: defaults.string(forKey: "liftlog.skin") ?? "") ?? .iron
    let sec = defaults.integer(forKey: "liftlog.restSec")
    restSec = Self.restSecs.contains(sec) ? sec : 90
    metric = defaults.string(forKey: "liftlog.metric") == "max" ? "max" : "e1rm"
    let hp = defaults.integer(forKey: "liftlog.hp")
    historyDays = [7, 28, 91].contains(hp) ? hp : 7
    let goal = defaults.integer(forKey: "liftlog.goal")
    self.goal = (1...5).contains(goal) ? goal : 2
    bwRange = ["1m", "3m", "all"].contains(defaults.string(forKey: "liftlog.bwRange") ?? "") ? defaults.string(forKey: "liftlog.bwRange")! : "1m"
    exset = ExerciseSettings.load(defaults)
    rest = Self.decode(RestState.self, defaults.data(forKey: "liftlog.rest"))
    draft = Self.decode(Draft.self, defaults.data(forKey: "liftlog.draft")) ?? .blank(Day.today())
    freshDraftDate()
  }

  private static func decode<T: Decodable>(_ t: T.Type, _ data: Data?) -> T? {
    data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
  }

  private func store<T: Encodable>(_ v: T?, _ key: String) {
    if let v, let data = try? JSONEncoder().encode(v) { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
  }

  // MARK: 設定

  var tab: AppTab { didSet { defaults.set(tab.rawValue, forKey: "liftlog.tab") } }
  var skin: Skin { didSet { defaults.set(skin.rawValue, forKey: "liftlog.skin"); activityChanged() } }
  var metric: String { didSet { defaults.set(metric, forKey: "liftlog.metric") } }
  var historyDays: Int { didSet { defaults.set(historyDays, forKey: "liftlog.hp") } }
  var goal: Int { didSet { defaults.set(goal, forKey: "liftlog.goal") } }
  var bwRange: String { didSet { defaults.set(bwRange, forKey: "liftlog.bwRange") } }
  var exset: ExerciseSettings { didSet { exset.save(defaults) } }

  /// 記録タブ・表示する種目の設定で選んでいる部位
  var part = "胸"
  /// ガイドタブで選んでいる部位
  var guidePart = "胸"
  /// 推移タブで選んでいる種目。nil なら記録回数が一番多い種目。体重を選んでいるときは showWeight
  var progressExercise: String?
  var showWeight = false

  // MARK: 画面をまたぐ表示

  var toastText: String?
  private var toastTask: Task<Void, Never>?
  var confirm: ConfirmRequest?
  var guide: GuideRequest?
  /// ルーティンの編集画面。中の値は名前欄を選ぶルーティンの id（空文字なら選ばない）
  var routinesFocus: String?
  var showWeek = false
  var showSkins = false
  /// 履歴タブを開き直したら、直近5件だけに戻す
  var historyAll = false

  func toast(_ msg: String) {
    toastText = msg
    toastTask?.cancel()
    toastTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2.2))
      if !Task.isCancelled { self?.toastText = nil }
    }
  }

  func ask(_ title: String, _ note: String, ok: String, destructive: Bool = true, alt: String? = nil, onAlt: (() -> Void)? = nil, onOK: @escaping () -> Void) {
    confirm = ConfirmRequest(title: title, note: note, ok: ok, destructive: destructive, alt: alt, onOK: onOK, onAlt: onAlt)
  }

  func setTab(_ t: AppTab) {
    if t == .history { historyAll = false }
    tab = t
  }

  // MARK: 下書き

  var draft: Draft { didSet { store(draft, "liftlog.draft"); activityChanged() } }

  /// ロック画面のライブアクティビティを今の下書き・休憩に合わせる
  func activityChanged() {
    if syncsActivity { LiveWorkout.schedule(self) }
  }

  /// 何も入っていない下書きは、日をまたいで開いたら日付を今日に戻す
  @discardableResult
  func freshDraftDate() -> Bool {
    let t = Day.today(clock())
    guard draft.isEmpty, draft.date != t else { return false }
    draft.date = t
    return true
  }

  func addExercise(_ raw: String, workouts: [Workout]) {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    let prev = Calc.lastSession(name, in: workouts, draftId: draft.id, draftDate: draft.date)
    let sets = prev.map { $0.sets.map { Draft.SetRow(w: Fmt.w($0.w), r: String($0.r)) } } ?? [Draft.SetRow(w: "", r: "")]
    for i in draft.exercises.indices { draft.exercises[i].closed = true }
    draft.exercises.append(.init(name: name, sets: sets))
    toast(prev != nil ? "\(name)を追加（前回の内容を入力済み）" : "\(name)を追加")
  }

  func copyPrevious(_ exID: UUID, workouts: [Workout]) {
    guard let i = draft.exercises.firstIndex(where: { $0.id == exID }),
          let p = Calc.lastSession(draft.exercises[i].name, in: workouts, draftId: draft.id, draftDate: draft.date) else { return }
    draft.exercises[i].sets = p.sets.map { .init(w: Fmt.w($0.w), r: String($0.r)) }
  }

  /// 「＋ セット追加」：直前のセットの重量・回数をコピーして1行足す。足した行の id を返す
  @discardableResult
  func addSet(_ exID: UUID) -> UUID? {
    guard let i = draft.exercises.firstIndex(where: { $0.id == exID }) else { return nil }
    let last = draft.exercises[i].sets.last
    let row = Draft.SetRow(w: last?.w ?? "", r: last?.r ?? "")
    draft.exercises[i].sets.append(row)
    return row.id
  }

  /// 「済」チェック。オンにしたら休憩タイマーを始め直す
  func toggleDone(_ exID: UUID, _ setID: UUID) {
    guard let i = draft.exercises.firstIndex(where: { $0.id == exID }),
          let j = draft.exercises[i].sets.firstIndex(where: { $0.id == setID }) else { return }
    draft.exercises[i].sets[j].done.toggle()
    if draft.exercises[i].sets[j].done { startRest() }
  }

  /// 保存。成功したら true
  func saveDraft(context: ModelContext, workouts: [Workout]) -> Bool {
    let exercises = draft.exercises.map { e in
      ExerciseRecord(name: e.name, sets: e.sets.map { SetRecord(w: Self.number($0.w), r: Int(Self.number($0.r).rounded())) }.filter { $0.r > 0 })
    }.filter { !$0.sets.isEmpty }
    guard !exercises.isEmpty else {
      toast("回数が入ったセットがありません。回数を入れてから保存してください")
      return false
    }
    let now = clock().timeIntervalSince1970 * 1000
    let memo = draft.memo.trimmingCharacters(in: .whitespacesAndNewlines)
    if let id = draft.id, let old = workouts.first(where: { $0.id == id }) {
      old.date = draft.date; old.exercises = exercises; old.memo = memo; old.updatedAt = now
    } else {
      context.insert(Workout(id: draft.id ?? NewId.make("w", now: clock()), date: draft.date, exercises: exercises, memo: memo, createdAt: now, updatedAt: now))
    }
    do {
      try context.save()
    } catch {
      context.rollback()
      toast("保存できませんでした。端末の空き容量を確かめてください")
      return false
    }
    toast(draft.id != nil ? "変更を保存しました" : "\(DateText.short(draft.date))の記録を保存しました")
    draft = .blank(Day.today(clock()))
    setTab(.history)
    return true
  }

  /// JS の +v || 0 に合わせる
  static func number(_ s: String) -> Double {
    let v = Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) ?? 0
    return v.isFinite ? v : 0
  }

  func clearDraft() {
    ask("入力をクリアしますか？", "入力中の種目・セット・メモが消えます。保存済みの記録はそのまま残ります。", ok: "クリア") { [self] in
      draft = .blank(Day.today(clock()))
      toast("入力をクリアしました")
    }
  }

  /// 履歴の「編集」
  func edit(_ w: Workout) {
    if draft.id == w.id { setTab(.log); return }
    let open = { [self] in
      draft = Draft(id: w.id, date: w.date, exercises: w.exercises.map { e in
        .init(name: e.name, sets: e.sets.map { .init(w: Fmt.w($0.w), r: String($0.r)) })
      }, memo: w.memo)
      setTab(.log)
    }
    if !draft.exercises.isEmpty || !draft.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      ask("\(DateText.short(w.date))の記録を編集しますか？", "入力中の種目・セット・メモは消えます。保存済みの記録はそのまま残ります。", ok: "編集する", destructive: false, onOK: open)
    } else {
      open()
    }
  }

  // MARK: ルーティン

  /// ルーティンを作って編集画面を開く
  func createRoutine(_ names: [String], context: ModelContext, routines: [Routine]) {
    var uniq: [String] = []
    for n in names where !uniq.contains(n) { uniq.append(n) }
    let r = Routine(id: NewId.make("r", now: clock()), name: Calc.routineName(uniq, used: Set(routines.map(\.name)), exset),
                    exercises: uniq, order: (routines.map(\.order).max() ?? -1) + 1)
    context.insert(r)
    try? context.save()
    routinesFocus = r.id
  }

  /// 記録タブのルーティンのチップ
  func callRoutine(_ r: Routine, workouts: [Workout]) {
    guard !r.exercises.isEmpty else {
      toast("「\(r.name)」には種目が入っていません。「作成・編集」から足してください")
      return
    }
    let names = r.exercises, title = r.name
    let add = { [self] in
      let have = Set(draft.exercises.map(\.name))
      let list = names.filter { !have.contains($0) }
      for n in list { addExercise(n, workouts: workouts) }
      toast(list.isEmpty ? "「\(title)」の種目はすべて入っています" : "「\(title)」の\(list.count)種目を追加しました")
    }
    if draft.exercises.isEmpty { add(); return }
    ask("「\(title)」を呼び出しますか？", "入力中の種目が\(draft.exercises.count)つあります。置き換えると、入力中のセットは消えます。",
        ok: "置き換える", alt: "後ろに足す", onAlt: add) { [self] in
      draft.exercises = []
      add()
    }
  }

  // MARK: 休憩タイマー

  static let restSecs = [60, 90, 120, 180]
  var restSec: Int { didSet { defaults.set(restSec, forKey: "liftlog.restSec") } }
  var rest: RestState? { didSet { store(rest, "liftlog.rest"); activityChanged() } }
  /// アプリが前面にあるか（裏に回っている間は鳴らさない）
  var isActive = true
  private var restTask: Task<Void, Never>?
  private var player: AVAudioPlayer?
  private var askedNotification = false

  func startRest() {
    rest = RestState(end: clock().addingTimeInterval(TimeInterval(restSec)), total: TimeInterval(restSec))
    restChanged()
  }

  /// ±15秒は終了時刻をずらす
  func adjustRest(_ sec: Double) {
    guard var r = rest else { return }
    r.end.addTimeInterval(sec)
    r.total = max(r.total, r.end.timeIntervalSince(clock()))
    rest = r
    restChanged()
  }

  func stopRest() { finishRest(.stop) }

  enum Finish { case stop, alarm, late }

  /// 画面に戻ったときと、終了時刻になったときに呼ぶ
  func checkRest() {
    guard let r = rest, isActive else { return }
    let over = clock().timeIntervalSince(r.end)
    if over >= 0 { finishRest(over > 60 ? .late : .alarm) }
  }

  private func finishRest(_ how: Finish) {
    rest = nil
    restTask?.cancel()
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"])
    switch how {
    case .stop: break
    case .late: toast("休憩は終わっています")
    case .alarm:
      UINotificationFeedbackGenerator().notificationOccurred(.warning)
      beep()
      toast("休憩終了。次のセットへ")
    }
  }

  private func restChanged() {
    restTask?.cancel()
    guard let r = rest else { return }
    restTask = Task { [weak self] in
      let wait = r.end.timeIntervalSinceNow
      if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
      guard !Task.isCancelled else { return }
      self?.checkRest()
    }
    scheduleNotification(r)
  }

  /// アプリを閉じていても終わったら知らせるよう、終了時刻にローカル通知を出す
  private func scheduleNotification(_ r: RestState) {
    let center = UNUserNotificationCenter.current()
    center.removePendingNotificationRequests(withIdentifiers: ["rest"])
    let wait = r.end.timeIntervalSince(clock())
    guard wait > 1 else { return }
    let schedule = {
      let c = UNMutableNotificationContent()
      c.title = "休憩終了"
      c.body = "次のセットへ"
      c.sound = .default
      center.add(UNNotificationRequest(identifier: "rest", content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)))
    }
    if askedNotification { schedule(); return }
    askedNotification = true
    Task {
      _ = try? await center.requestAuthorization(options: [.alert, .sound])
      schedule()
    }
  }

  /// 880Hz の矩形波を 0.35 秒間隔で3回（Web 版と同じ音）
  private func beep() {
    try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
    try? AVAudioSession.sharedInstance().setActive(true)
    player = try? AVAudioPlayer(data: Self.beepWAV)
    player?.play()
  }

  static let beepWAV: Data = {
    let rate = 22050, length = Int(Double(rate) * 1.0)
    var samples = [Int16](repeating: 0, count: length)
    for i in 0..<3 {
      let start = Int(Double(rate) * (0.05 + Double(i) * 0.35))
      for n in 0..<Int(Double(rate) * 0.25) where start + n < length {
        let t = Double(n) / Double(rate)
        let env = t < 0.01 ? t / 0.01 : max(0, 1 - (t - 0.01) / 0.24)
        let square: Double = sin(2 * .pi * 880 * t) >= 0 ? 1 : -1
        samples[start + n] = Int16(square * env * 0.3 * Double(Int16.max))
      }
    }
    var d = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + length * 2)); d.append(contentsOf: Array("WAVEfmt ".utf8))
    u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
    d.append(contentsOf: Array("data".utf8)); u32(UInt32(length * 2))
    for s in samples { u16(UInt16(bitPattern: s)) }
    return d
  }()

  /// 起動時：開き直しても続きから数える
  func resumeRest() { restChanged() }
}

/// アプリを開いている間に休憩の通知が来ても出さない（画面の中で鳴らす）
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    []
  }
}
