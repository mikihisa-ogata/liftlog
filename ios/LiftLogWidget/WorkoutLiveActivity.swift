import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct LiftLogWidgetBundle: WidgetBundle {
  var body: some Widget {
    WorkoutLiveActivity()
  }
}

/// 筋トレ中にロック画面と Dynamic Island に出す。次のセットの「済」と休憩タイマー
struct WorkoutLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: WorkoutAttributes.self) { context in
      LockScreenView(s: context.state, stale: context.isStale)
    } dynamicIsland: { context in
      let s = context.state, stale = context.isStale
      let accent = rgb(s.accent)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          if let n = s.next {
            VStack(alignment: .leading, spacing: 2) {
              Text(n.name).font(.headline).lineLimit(1)
              Text("\(n.number)セット目（全\(n.count)）").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
          } else {
            Label("全セット済", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(accent)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          if let end = restEnd(s, stale) {
            RestTimer(end: end).font(.title2.bold()).foregroundStyle(accent).frame(maxWidth: 90, alignment: .trailing)
          } else {
            Text("\(s.doneSets)/\(s.totalSets)セット").font(.caption.bold()).foregroundStyle(.secondary)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(spacing: 8) {
            if let n = s.next {
              HStack {
                Text(setText(n)).font(.title3.bold()).monospacedDigit()
                Spacer()
                DoneButton(n: n, s: s)
              }
            }
            if restEnd(s, stale) != nil { RestButtons(s: s) }
          }
          .padding(.horizontal, 4)
        }
      } compactLeading: {
        Image(systemName: "dumbbell.fill").foregroundStyle(accent)
      } compactTrailing: {
        if let end = restEnd(s, stale) {
          RestTimer(end: end).frame(maxWidth: 46).foregroundStyle(accent)
        } else {
          Text("\(s.doneSets)/\(s.totalSets)").monospacedDigit()
        }
      } minimal: {
        if let end = restEnd(s, stale) {
          RestTimer(end: end).font(.caption2).frame(maxWidth: 36).foregroundStyle(accent)
        } else {
          Image(systemName: "dumbbell.fill").foregroundStyle(accent)
        }
      }
      .keylineTint(accent)
    }
  }
}

private struct LockScreenView: View {
  var s: WorkoutAttributes.ContentState
  var stale: Bool

  var body: some View {
    let accent = rgb(s.accent)
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("リフトログ", systemImage: "dumbbell.fill").font(.caption.bold()).foregroundStyle(accent)
        Spacer()
        Text("\(s.doneSets)/\(s.totalSets)セット済").font(.caption).foregroundStyle(.secondary).monospacedDigit()
      }
      if let end = restEnd(s, stale) {
        HStack(alignment: .firstTextBaseline) {
          Text("休憩").font(.subheadline.bold())
          Spacer()
          RestTimer(end: end).font(.system(size: 34, weight: .bold)).frame(maxWidth: 130, alignment: .trailing)
        }
        ProgressView(timerInterval: end.addingTimeInterval(-max(1, s.restTotal))...end, countsDown: true) {
          EmptyView()
        } currentValueLabel: {
          EmptyView()
        }
        .tint(accent)
        RestButtons(s: s)
      } else if s.restEnd != nil {
        Label("休憩終了。次のセットへ", systemImage: "bell.fill").font(.subheadline.bold()).foregroundStyle(accent)
      }
      if let n = s.next {
        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 2) {
            Text("次：\(n.name)　\(n.number)セット目（全\(n.count)）").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Text(setText(n)).font(.title3.bold()).monospacedDigit()
          }
          Spacer()
          DoneButton(n: n, s: s)
        }
      } else {
        Text("すべてのセットが済みました。アプリを開いて保存してください").font(.subheadline)
      }
    }
    .padding(16)
  }
}

/// 残り時間。終了時刻を過ぎていたら 0:00 のまま
private struct RestTimer: View {
  var end: Date

  var body: some View {
    let now = Date.now
    Text(timerInterval: now...max(now, end), countsDown: true)
      .monospacedDigit()
      .multilineTextAlignment(.trailing)
  }
}

private struct DoneButton: View {
  var n: WorkoutAttributes.NextSet
  var s: WorkoutAttributes.ContentState

  var body: some View {
    Button(intent: CompleteSetIntent(exID: n.exID, setID: n.setID)) {
      Label("済", systemImage: "checkmark").font(.headline).foregroundStyle(rgb(s.accentInk))
    }
    .buttonStyle(.borderedProminent)
    .tint(rgb(s.accent))
    .accessibilityLabel("\(n.name)の\(n.number)セット目を済にする")
  }
}

private struct RestButtons: View {
  var s: WorkoutAttributes.ContentState

  var body: some View {
    HStack(spacing: 8) {
      Button(intent: AdjustRestIntent(seconds: -15)) { Text("−15秒").frame(maxWidth: .infinity) }
        .accessibilityLabel("休憩を15秒短くする")
      Button(intent: AdjustRestIntent(seconds: 15)) { Text("＋15秒").frame(maxWidth: .infinity) }
        .accessibilityLabel("休憩を15秒延ばす")
      Button(intent: StopRestIntent()) { Text("休憩終了").frame(maxWidth: .infinity) }
    }
    .font(.subheadline.bold())
    .buttonStyle(.bordered)
    .tint(rgb(s.accent))
  }
}

/// 休憩中なら終了時刻。終了時刻を過ぎた（stale になった）ら nil
private func restEnd(_ s: WorkoutAttributes.ContentState, _ stale: Bool) -> Date? {
  stale ? nil : s.restEnd
}

/// 「60kg × 10回」。重量が空か0なら回数だけ
private func setText(_ n: WorkoutAttributes.NextSet) -> String {
  let w = n.w.trimmingCharacters(in: .whitespaces), r = n.r.trimmingCharacters(in: .whitespaces)
  let reps = r.isEmpty ? "回数未入力" : "\(r)回"
  return w.isEmpty || Double(w) == 0 ? reps : "\(w)kg × \(reps)"
}

private func rgb(_ hex: UInt32) -> Color {
  Color(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
}
