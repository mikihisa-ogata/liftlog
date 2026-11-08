import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// 履歴タブ（docs/spec.md 2.6・2.7）

struct HistoryView: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  @Environment(\.modelContext) private var context
  @Query(sort: Workout.newestFirst) private var workouts: [Workout]
  @Query(sort: \Routine.order) private var routines: [Routine]
  @State private var month = String(Day.today().prefix(7))
  @State private var muscle: String?
  @State private var flash: String?
  @State private var importing = false
  @State private var exportDoc: BackupDocument?

  private static let shownCount = 5

  var body: some View {
    let p = skin.palette
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          if workouts.isEmpty {
            Note("まだ記録がありません。「記録」タブで種目とセットを入れて保存すると、ここに日付ごとに並びます。")
              .padding(.vertical, 24)
          } else {
            calendar(proxy)
            mapCard
            if workouts.contains(where: \.isExample) {
              Card {
                Note("「サンプル」の付いた記録は見本です。自分の記録をつけ始めたら消してください。")
                Button("サンプルを削除", action: deleteSamples).skinButton(small: true)
              }
            }
            list
          }
          backup
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
      }
      .background(p.c(p.bg))
      .onChange(of: flash) { _, d in
        guard let d else { return }
        withAnimation { proxy.scrollTo("day-" + d, anchor: .top) }
        Task { try? await Task.sleep(for: .seconds(2.4)); if flash == d { flash = nil } }
      }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { importBackup($0) }
    .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }),
                  document: exportDoc, contentType: .json, defaultFilename: Backup.fileName()) { result in
      if case .success = result { app.toast("バックアップを書き出しました") }
    }
  }

  // MARK: カレンダー

  private func calendar(_ proxy: ScrollViewProxy) -> some View {
    @Bindable var app = app
    let p = skin.palette
    let parts = month.split(separator: "-").compactMap { Int($0) }
    let first = month + "-01"
    let lead = (Day.calendar.component(.weekday, from: Day.date(first) ?? .now) + 5) % 7
    let days = Day.calendar.range(of: .day, in: .month, for: Day.date(first) ?? .now)?.count ?? 30
    let has = Set(workouts.map(\.date)), today = Day.today()
    let cur = String(today.prefix(7))
    let streak = Calc.goalStreak(workouts.map(\.date), goal: app.goal, today: today)
    return Card {
      HStack {
        Button { month = String(Day.add(first, months: -1).prefix(7)) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
          .accessibilityLabel("前の月")
        Spacer()
        Text(String(format: "%d.%02d", parts[0], parts[1])).font(skin.num(22))
        Spacer()
        Button { month = String(Day.add(first, months: 1).prefix(7)) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
          .disabled(month >= cur)
          .accessibilityLabel("次の月")
      }
      .foregroundStyle(p.c(p.ink))
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
        ForEach(Array("月火水木金土日").map(String.init), id: \.self) { Text($0).font(.caption2.bold()).foregroundStyle(p.c(p.muted)) }
        ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 34) }
        ForEach(1...days, id: \.self) { i in
          let d = String(format: "%@-%02d", month, i)
          let isToday = d == today
          if has.contains(d) {
            Button { openDay(d) } label: {
              Text("\(i)").font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(p.c(p.accentInk))
                .background(p.c(p.accent), in: RoundedRectangle(cornerRadius: min(p.radiusCtl, 17)))
                .overlay { if isToday { RoundedRectangle(cornerRadius: min(p.radiusCtl, 17)).strokeBorder(p.c(p.ink), lineWidth: 2) } }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(DateText.short(d))の記録を見る")
          } else {
            Text("\(i)").font(.subheadline).frame(maxWidth: .infinity, minHeight: 34)
              .foregroundStyle(isToday ? p.c(p.ink) : p.c(p.muted))
              .overlay { if isToday { RoundedRectangle(cornerRadius: min(p.radiusCtl, 17)).strokeBorder(p.c(p.ink), lineWidth: 1.5) } }
          }
        }
      }
      VStack(alignment: .leading, spacing: 8) {
        (Text("\(streak)").font(skin.num(24)) + Text("週連続で週\(app.goal)回以上").font(.subheadline.bold()))
        HStack(spacing: 6) {
          ForEach(1...5, id: \.self) { g in Chip("週\(g)", selected: g == app.goal) { app.goal = g } }
        }
        .accessibilityLabel("1週間の目標回数")
      }
    }
  }

  private func openDay(_ d: String) {
    let idx = workouts.firstIndex { $0.date == d } ?? 0
    if idx >= Self.shownCount { app.historyAll = true }
    flash = nil
    Task { flash = d }
  }

  // MARK: 鍛えた部位

  private var mapCard: some View {
    @Bindable var app = app
    let p = skin.palette
    let days = app.historyDays
    let from = Day.add(Day.today(), days: -days + 1)
    let ms = Calc.muscleSets(workouts.filter { $0.date >= from })
    let perWeek = { (m: String) in (ms.sets[m] ?? 0) * 7 / Double(days) }
    let lv = { (m: String) in Calc.level(perWeek(m), Calc.weekSteps) }
    let rank = ms.sets.keys.sorted { ms.sets[$0]! != ms.sets[$1]! ? ms.sets[$0]! > ms.sets[$1]! : $0 < $1 }
    let c = Catalog.shared
    return Card {
      HStack {
        SectionTitle(text: "鍛えた部位")
        Spacer()
        HStack(spacing: 6) {
          ForEach([(7, "1週間"), (28, "4週間"), (91, "3か月")], id: \.0) { d, l in Chip(l, selected: d == days) { app.historyDays = d } }
        }
      }
      BodyMapView(level: lv, selected: muscle) { m in muscle = m != nil && m != muscle ? m : nil }
        .frame(maxWidth: 280).frame(maxWidth: .infinity)
      if let m = muscle {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
          Text(c.muscleName(m)).font(.subheadline.bold())
          Text(Fmt.w(perWeek(m))).font(skin.num(22))
          Text("セット／週").font(.caption)
        }
        .frame(maxWidth: .infinity)
      } else {
        Note("図の部位を押すと名称が出ます").frame(maxWidth: .infinity)
      }
      if rank.isEmpty {
        Note("この期間の記録はありません。")
      } else {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
          ForEach(rank, id: \.self) { m in
            HStack(spacing: 6) {
              RoundedRectangle(cornerRadius: 2).fill(p.level(lv(m))).frame(width: 12, height: 12)
              Text(c.muscleShort(m)).font(.footnote)
              Spacer()
              Text(Fmt.w(perWeek(m))).font(skin.num(16))
            }
            .accessibilityElement(children: .combine)
          }
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        Note("数字と色の濃さは1週間あたりのセット数：")
        HStack(spacing: 12) {
          ForEach(Array(["1〜", "4〜", "8〜", "12〜"].enumerated()), id: \.offset) { i, t in
            HStack(spacing: 4) {
              RoundedRectangle(cornerRadius: 2).fill(p.level(i + 1)).frame(width: 12, height: 12)
              Text(t).font(.caption).foregroundStyle(p.c(p.muted))
            }
          }
        }
      }
      Note("補助で使う部位は0.5セットとして数えています。" + (ms.unknown.isEmpty ? "" : "部位が登録されていない種目（\(ms.unknown.joined(separator: "・"))）は含みません。"))
    }
  }

  // MARK: 記録の一覧

  @ViewBuilder private var list: some View {
    let p = skin.palette
    let prs = Calc.prMap(workouts)
    let shown = app.historyAll ? workouts : Array(workouts.prefix(Self.shownCount))
    ForEach(Array(shown.enumerated()), id: \.element.id) { i, w in
      if i == 0 || shown[i - 1].date.prefix(7) != w.date.prefix(7) {
        Text(w.date.prefix(7).replacingOccurrences(of: "-", with: ".")).font(skin.num(20)).foregroundStyle(p.c(p.muted))
      }
      DayCard(workout: w, prs: prs[w.id] ?? [], flash: flash == w.date,
              toRoutine: {
                app.createRoutine(w.exercises.map(\.name), context: context, routines: routines)
                app.toast("ルーティンを作りました。名前は書き換えられます")
              },
              edit: { app.edit(w) },
              delete: { delete(w) })
        .id(workouts.first { $0.date == w.date }?.id == w.id ? "day-" + w.date : w.id)
    }
    if shown.count < workouts.count {
      Button("それより前の記録 \(workouts.count - shown.count)件を表示") { app.historyAll = true }.skinButton()
    }
  }

  private func delete(_ w: Workout) {
    app.ask("\(DateText.short(w.date))の記録を削除しますか？", "削除した記録は元に戻せません。", ok: "削除") {
      context.delete(w)
      do { try context.save(); app.toast("記録を削除しました") } catch { app.toast("削除できませんでした。もう一度試してください") }
    }
  }

  private func deleteSamples() {
    app.ask("サンプルを削除しますか？", "最初に入っているサンプルの記録をすべて消します。自分で付けた記録は消えません。", ok: "削除") {
      for w in workouts where w.isExample { context.delete(w) }
      try? context.save()
      app.toast("サンプルを削除しました")
    }
  }

  // MARK: バックアップ

  private var backup: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle(text: "バックアップ")
      Note("記録はこの端末の中だけに保存されます。機種変更の前や、ときどきの控えとしてファイルに書き出しておいてください。読み込むと、同じ記録は上書きされ、それ以外は追加されます。体重の記録、ルーティン、記録画面に出す種目の設定も含まれますが、体の写真は含まれません。")
      HStack(spacing: 8) {
        Button("ファイルに書き出す", action: exportBackup).skinButton(small: true)
        Button("ファイルから読み込む") { importing = true }.skinButton(small: true)
      }
    }
    .padding(.top, 8)
  }

  private func exportBackup() {
    do { exportDoc = BackupDocument(data: try Backup.export(from: context)) }
    catch { app.toast("書き出せませんでした。もう一度試してください") }
  }

  private func importBackup(_ result: Result<URL, Error>) {
    guard case .success(let url) = result else { return }
    // ファイルアプリから選んだファイルは、読む間だけアクセス権を取る
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let contents = try Backup.parse(try Data(contentsOf: url))
      try Backup.apply(contents, to: context)
      app.exset = ExerciseSettings.load()
      app.toast(contents.summary)
    } catch {
      app.toast(Backup.failureMessage)
    }
  }
}

/// 履歴の記録カード
private struct DayCard: View {
  @Environment(\.skin) private var skin
  var workout: Workout
  var prs: Set<String>
  var flash: Bool
  var toRoutine: () -> Void
  var edit: () -> Void
  var delete: () -> Void

  var body: some View {
    let p = skin.palette
    let w = workout
    let ms = Calc.muscleSets([w]).sets
    Card {
      HStack {
        Text(DateText.short(w.date)).font(.headline)
        if w.isExample { Badge(text: "サンプル") }
        Spacer()
        Text("\(w.exercises.count)種目 · \(w.exercises.reduce(0) { $0 + $1.sets.count })セット").font(.caption).foregroundStyle(p.c(p.muted))
      }
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(Array(w.exercises.enumerated()), id: \.offset) { _, e in
            VStack(alignment: .leading, spacing: 1) {
              HStack(spacing: 6) {
                Text(e.name).font(.subheadline.bold())
                if prs.contains(e.name) { Badge(text: "自己ベスト", pr: true) }
              }
              Text(SetText.summary(e.sets)).font(skin.num(15)).foregroundStyle(p.c(p.muted))
            }
          }
        }
        Spacer(minLength: 0)
        BodyMapView(level: { Calc.level(ms[$0] ?? 0, Calc.daySteps) }, labels: false)
          .frame(width: 84)
          .accessibilityHidden(true)
      }
      if !w.memo.isEmpty { Text(w.memo).font(.footnote).foregroundStyle(p.c(p.muted)) }
      HStack(spacing: 8) {
        Button("ルーティンにする", action: toRoutine).skinButton(small: true)
        Button("編集", action: edit).skinButton(small: true)
        Button("削除", action: delete).skinButton(.danger, small: true)
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: p.radius).strokeBorder(p.c(p.accent), lineWidth: 3).opacity(flash ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: flash)
    }
  }
}

struct BackupDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.json]
  var data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
