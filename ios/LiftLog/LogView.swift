import SwiftData
import SwiftUI

// 記録タブ（docs/spec.md 2.1〜2.4）

struct LogView: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  @Environment(\.modelContext) private var context
  @Query(sort: Workout.newestFirst) private var workouts: [Workout]
  @Query(sort: \Routine.order) private var routines: [Routine]
  @State private var custom = ""
  @State private var showExset = false
  @FocusState private var focus: FieldID?

  enum FieldID: Hashable {
    case weight(UUID), reps(UUID), memo, custom
  }

  var body: some View {
    @Bindable var app = app
    let p = skin.palette
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Hero(workouts: workouts)

        HStack(alignment: .bottom, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text("日付").font(.caption.bold()).foregroundStyle(p.c(p.muted))
            DatePicker("日付", selection: Binding(
              get: { Day.date(app.draft.date) ?? .now },
              set: { app.draft.date = DateText.ymd($0, calendar: Day.calendar) }
            ), displayedComponents: .date)
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "ja_JP"))
          }
          if app.draft.id != nil {
            Text("過去の記録を編集中").font(.footnote.bold()).foregroundStyle(p.c(p.accentInk))
              .padding(.horizontal, 8).padding(.vertical, 4).background(p.c(p.accent), in: Capsule())
          }
        }

        ForEach($app.draft.exercises) { $ex in
          ExerciseCard(ex: $ex, workouts: workouts, focus: $focus)
        }

        routinesSection
        pickerSection

        VStack(alignment: .leading, spacing: 4) {
          Text("メモ").font(.caption.bold()).foregroundStyle(p.c(p.muted))
          TextField("調子、睡眠、フォームの気づきなど", text: $app.draft.memo, axis: .vertical)
            .lineLimit(3...8)
            .focused($focus, equals: .memo)
            .field(skin)
        }

        VStack(spacing: 10) {
          Button(app.draft.id != nil ? "変更を保存" : "保存") {
            focus = nil
            _ = app.saveDraft(context: context, workouts: workouts)
          }
          .skinButton(.primary)
          Button("入力をクリア") { app.clearDraft() }.skinButton()
        }
      }
      .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
    }
    .scrollDismissesKeyboard(.interactively)
    .background(p.c(p.bg))
    .sheet(isPresented: $showExset) { ExerciseSettingsSheet() }
    .toolbar {
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("完了") { focus = nil }
      }
    }
  }

  @ViewBuilder private var routinesSection: some View {
    let p = skin.palette
    VStack(alignment: .leading, spacing: 10) {
      if app.draft.exercises.isEmpty {
        HStack {
          SectionTitle(text: "ルーティン")
          Spacer()
          Button("作成・編集") { app.routinesFocus = "" }.font(.subheadline.bold()).foregroundStyle(p.c(p.accent))
        }
        if routines.isEmpty {
          Note("よくやる種目の組み合わせを保存しておくと、ここからまとめて追加できます。")
        } else {
          FlowLayout(spacing: 8) {
            ForEach(routines) { r in
              Chip(action: { app.callRoutine(r, workouts: workouts) }) {
                HStack(spacing: 6) {
                  Text(r.name)
                  Text("\(r.exercises.count)種目").font(.caption).foregroundStyle(p.c(p.muted))
                }
              }
            }
          }
        }
      } else {
        Button("入力中の種目をルーティンとして保存") {
          app.createRoutine(app.draft.exercises.map(\.name), context: context, routines: routines)
          app.toast("ルーティンを作りました。名前は書き換えられます")
        }
        .skinButton(small: true)
      }
    }
  }

  @ViewBuilder private var pickerSection: some View {
    @Bindable var app = app
    let p = skin.palette
    let c = Catalog.shared
    let list = c.shownOf(app.part, app.exset)
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        SectionTitle(text: "種目を追加")
        Spacer()
        Button("表示する種目を選ぶ") { showExset = true }.font(.subheadline.bold()).foregroundStyle(p.c(p.accent))
      }
      PartChips(selection: $app.part)
      if list.isEmpty {
        Note("\(app.part)の種目はすべて非表示です。「表示する種目を選ぶ」から選んでください。")
      } else {
        FlowLayout(spacing: 8) {
          ForEach(list, id: \.self) { n in
            Chip(action: { app.addExercise(n, workouts: workouts) }) {
              HStack(spacing: 6) {
                ExerciseIcon(name: n, size: 24)
                Text(n)
              }
            }
          }
        }
      }
      HStack(spacing: 8) {
        TextField("その他", text: $custom)
          .focused($focus, equals: .custom)
          .submitLabel(.done)
          .onSubmit(addCustom)
          .field(skin)
        Button("追加", action: addCustom).skinButton(small: true)
      }
    }
  }

  private func addCustom() {
    app.addExercise(custom, workouts: workouts)
    custom = ""
  }
}

/// 部位のチップ（胸・肩・背中・腕・腹・脚）
struct PartChips: View {
  @Binding var selection: String
  var body: some View {
    FlowLayout(spacing: 8) {
      ForEach(Catalog.shared.partNames, id: \.self) { p in
        Chip(p, selected: p == selection) { selection = p }
      }
    }
  }
}

// MARK: ヒーロー

private struct Hero: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  var workouts: [Workout]

  var body: some View {
    let p = skin.palette
    let s = Calc.summary(workouts.map(\.date), today: Day.today())
    VStack(alignment: .leading, spacing: 14) {
      if skin == .iron {
        HazardStripe().frame(height: 10).padding(.horizontal, -16)
      }
      HStack(alignment: .lastTextBaseline) {
        (Text("LIFT").foregroundStyle(skin == .plate ? Color.white : p.c(p.ink)) + Text("LOG").foregroundStyle(p.c(skin == .plate ? p.pr : p.accent)))
          .font(skin == .clock ? .system(size: 30, weight: .regular, design: .monospaced) : skin.num(34))
          .accessibilityLabel("リフトログ")
        Spacer()
        Button("テーマ") { app.showSkins = true }
          .font(.footnote.bold())
          .padding(.horizontal, 12).padding(.vertical, 6)
          .foregroundStyle(skin == .plate ? Color(hex: 0xdddddd) : p.c(p.ink))
          .overlay { RoundedRectangle(cornerRadius: min(p.radiusCtl, 16)).strokeBorder(skin == .plate ? Color(hex: 0x555555) : p.c(p.line)) }
      }
      Button { app.showWeek = true } label: {
        HStack(spacing: 8) {
          stat("連続", "\(s.streak)", "週", highlight: skin == .plate)
          stat("今週", "\(s.week)", "回", more: true)
          stat("累計", "\(s.total)", "日", pr: skin == .clock)
        }
        .padding(.trailing, skin == .plate ? 64 : 0)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("今週のまとめ。連続\(s.streak)週、今週\(s.week)回、累計\(s.total)日。押すと部位ごとのセット数を開く")
    }
    .padding(skin == .plate ? 16 : 0)
    .background { if skin == .plate { PlateHero() } }
  }

  private func stat(_ k: String, _ v: String, _ unit: String, more: Bool = false, highlight: Bool = false, pr: Bool = false) -> some View {
    let p = skin.palette
    let valueColor: Color = highlight ? p.c(p.pr) : pr ? p.c(p.pr) : skin == .clock ? p.c(p.accent) : skin == .plate ? .white : p.c(p.ink)
    return VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Text(k)
        if more { Text("部位別 ›").font(.caption2) }
      }
      .font(.caption.bold())
      .foregroundStyle(skin == .plate ? Color(hex: 0xb5b5b5) : p.c(p.muted))
      HStack(alignment: .lastTextBaseline, spacing: 2) {
        Text(v).font(skin.num(skin == .clock ? 34 : 40)).foregroundStyle(valueColor)
        Text(unit).font(.caption.bold()).foregroundStyle(skin == .plate ? Color(hex: 0xb5b5b5) : p.c(p.muted))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(skin == .plate ? 0 : 10)
    .background {
      if skin == .iron {
        HStack(spacing: 0) { p.c(p.accent).frame(width: 4); p.c(p.surface) }
      } else if skin == .clock {
        Color.black
      }
    }
  }
}

/// アイアンのハザードライン
private struct HazardStripe: View {
  @Environment(\.skin) private var skin
  var body: some View {
    Canvas { ctx, size in
      ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(skin.palette.c(skin.palette.bg)))
      var x = -size.height
      while x < size.width + size.height {
        var p = Path()
        p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0))
        p.addLine(to: CGPoint(x: x + size.height + 12, y: 0)); p.addLine(to: CGPoint(x: x + 12, y: size.height)); p.closeSubpath()
        ctx.fill(p, with: .color(skin.palette.c(skin.palette.accent)))
        x += 24
      }
    }
  }
}

/// プレートの黒いヒーローと、赤・青のプレートの輪
private struct PlateHero: View {
  var body: some View {
    GeometryReader { g in
      ZStack {
        Color(hex: 0x111111)
        Circle().strokeBorder(Color(hex: 0xe2231a), lineWidth: 26).frame(width: 230, height: 230)
          .position(x: g.size.width + 130 - 115, y: -40 + 115)
        Circle().strokeBorder(Color(hex: 0x0057b8), lineWidth: 16).frame(width: 110, height: 110)
          .position(x: g.size.width + 60 - 55, y: 20 + 55)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 24))
  }
}

// MARK: 種目カード

private struct ExerciseCard: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  @Binding var ex: Draft.Exercise
  var workouts: [Workout]
  var focus: FocusState<LogView.FieldID?>.Binding

  var body: some View {
    let p = skin.palette
    let open = !ex.closed
    let prev = Calc.lastSession(ex.name, in: workouts, draftId: app.draft.id, draftDate: app.draft.date)
    Card {
      HStack(spacing: 8) {
        Button { ex.closed.toggle() } label: {
          HStack(spacing: 8) {
            Image(systemName: "chevron.down").font(.footnote.bold()).foregroundStyle(p.c(p.muted))
              .rotationEffect(.degrees(open ? 0 : -90))
            ExerciseIcon(name: ex.name, size: 36)
            Text(ex.name).font(.system(size: 17, weight: .heavy)).foregroundStyle(p.c(p.ink)).multilineTextAlignment(.leading)
          }
        }
        .buttonStyle(.plain)
        .accessibilityValue(open ? "開いている" : "閉じている")
        if open, Catalog.shared.guide[ex.name] != nil {
          Button("やり方") { app.guide = GuideRequest(name: ex.name, fromLog: true) }
            .font(.footnote.bold()).foregroundStyle(p.c(p.accent))
        }
        Spacer()
        if open {
          Button { app.draft.exercises.removeAll { $0.id == ex.id } } label: {
            Image(systemName: "xmark").font(.body.bold()).foregroundStyle(p.c(p.muted)).frame(width: 36, height: 36)
          }
          .accessibilityLabel("\(ex.name)を外す")
        }
      }
      if open {
        if prev != nil {
          Button("前回をコピー") { app.copyPrevious(ex.id, workouts: workouts) }
            .font(.footnote.bold()).foregroundStyle(p.c(p.accent))
        } else {
          Note("この種目は初めての記録です")
        }
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
          GridRow {
            Text("SET"); Text("重量（kg）"); Text(""); Text("回数"); Text("済"); Text("")
          }
          .font(.caption2.bold()).foregroundStyle(p.c(p.muted))
          ForEach(Array($ex.sets.enumerated()), id: \.element.id) { j, $s in
            GridRow {
              Text(String(format: "%02d", j + 1)).font(skin.num(17)).foregroundStyle(p.c(skin == .plate ? p.muted : p.ink))
              TextField("0", text: $s.w)
                .keyboardType(.decimalPad)
                .focused(focus, equals: .weight(s.id))
                .multilineTextAlignment(.center)
                .font(skin.num(19))
                .field(skin)
                .opacity(s.done ? 0.6 : 1)
                .accessibilityLabel("\(j + 1)セット目の重量")
              Text("×").foregroundStyle(p.c(p.muted))
              TextField("0", text: $s.r)
                .keyboardType(.numberPad)
                .focused(focus, equals: .reps(s.id))
                .multilineTextAlignment(.center)
                .font(skin.num(19))
                .field(skin)
                .opacity(s.done ? 0.6 : 1)
                .accessibilityLabel("\(j + 1)セット目の回数")
              Button { app.toggleDone(ex.id, s.id) } label: {
                Image(systemName: "checkmark").font(.body.bold())
                  .frame(width: 36, height: 36)
                  .foregroundStyle(s.done ? p.c(p.accentInk) : p.c(p.muted))
                  .background(s.done ? p.c(p.accent) : p.c(p.field), in: RoundedRectangle(cornerRadius: min(p.radiusCtl, 10)))
                  .overlay { RoundedRectangle(cornerRadius: min(p.radiusCtl, 10)).strokeBorder(s.done ? p.c(p.accent) : p.c(p.line)) }
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(j + 1)セット目を終えた")
              .accessibilityAddTraits(s.done ? .isSelected : [])
              Button { ex.sets.removeAll { $0.id == s.id } } label: {
                Image(systemName: "trash").foregroundStyle(p.c(p.muted)).frame(width: 32, height: 36)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("\(j + 1)セット目を削除")
            }
          }
        }
        Button("＋ セット追加") {
          if let id = app.addSet(ex.id) { focus.wrappedValue = .reps(id) }
        }
        .skinButton(small: true)
      }
    }
  }
}

// MARK: 部位ごとの今週

struct WeekSheet: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  @Query private var workouts: [Workout]

  var body: some View {
    let p = skin.palette
    let mon = Day.weekStart(Day.today()), prev = Day.add(mon, days: -7)
    let now = Calc.partTotals(workouts.filter { $0.date >= mon }, app.exset)
    let last = Calc.partTotals(workouts.filter { $0.date >= prev && $0.date < mon }, app.exset)
    let parts = Catalog.shared.partNames + (now.t["その他"] != nil || last.t["その他"] != nil ? ["その他"] : [])
    let get = { (x: [String: Calc.PartTotal], k: String) in x[k] ?? .init() }
    let sumSets = { (x: [String: Calc.PartTotal]) in x.values.reduce(0) { $0 + $1.sets } }
    let sumVol = { (x: [String: Calc.PartTotal]) in x.values.reduce(0) { $0 + $1.vol } }
    let mx = max(1, parts.flatMap { [get(now.t, $0).sets, get(last.t, $0).sets] }.max() ?? 1)
    var other: [String] = []
    for n in now.other + last.other where !other.contains(n) { other.append(n) }

    return SheetFrame(title: "部位ごとの今週") {
      HStack(spacing: 18) {
        total("\(sumSets(now.t))", "セット", Fmt.diff(Double(sumSets(now.t)), Double(sumSets(last.t))), up: sumSets(now.t) >= sumSets(last.t))
        total(Fmt.n(sumVol(now.t)), "kg", Fmt.diff(sumVol(now.t), sumVol(last.t), unit: "kg"), up: sumVol(now.t) >= sumVol(last.t))
      }
      ForEach(parts, id: \.self) { part in
        let a = get(now.t, part), b = get(last.t, part)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 10) {
            Text(part).font(.subheadline.bold()).frame(width: 44, alignment: .leading)
            GeometryReader { g in
              VStack(alignment: .leading, spacing: 3) {
                RoundedRectangle(cornerRadius: 3).fill(p.c(p.accent)).frame(width: g.size.width * Double(a.sets) / Double(mx), height: 9).opacity(a.sets > 0 ? 1 : 0)
                RoundedRectangle(cornerRadius: 3).strokeBorder(p.c(p.muted), lineWidth: 1.5).frame(width: g.size.width * Double(b.sets) / Double(mx), height: 9).opacity(b.sets > 0 ? 1 : 0)
              }
            }
            .frame(height: 21)
            .accessibilityLabel("\(part) 今週\(a.sets)セット、先週\(b.sets)セット")
            (Text("\(a.sets)").font(skin.num(20)) + Text("セット").font(.caption)).frame(width: 64, alignment: .trailing)
          }
          HStack {
            Text("\(Fmt.n(a.vol))kg（先週 \(Fmt.n(b.vol))kg）")
            Spacer()
            Text("先週比 \(Fmt.diff(Double(a.sets), Double(b.sets)))")
          }
          .font(.caption).foregroundStyle(p.c(p.muted))
        }
        .padding(.vertical, 4)
      }
      Note("\(DateText.short(mon))から今日までの記録。塗りつぶした棒が今週、枠だけの棒が先週のセット数です。ボリュームは重量×回数の合計で、自重の種目は0kgになります。"
        + (other.isEmpty ? "" : "部位が決まっていない種目（\(other.joined(separator: "・"))）は「その他」に数えています。"))
    }
  }

  private func total(_ v: String, _ unit: String, _ diff: String, up: Bool) -> some View {
    let p = skin.palette
    return HStack(alignment: .lastTextBaseline, spacing: 4) {
      Text(v).font(skin.num(30))
      Text(unit).font(.caption.bold())
      Text(diff).font(.caption.bold()).foregroundStyle(diff.hasPrefix("±") ? p.c(p.muted) : up ? p.c(p.accent) : p.c(p.danger))
    }
  }
}

// MARK: 記録画面に出す種目

struct ExerciseSettingsSheet: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  @State private var name = ""

  var body: some View {
    @Bindable var app = app
    let p = skin.palette
    let c = Catalog.shared
    let own = app.exset.ownOf(app.part)
    SheetFrame(title: "記録画面に出す種目") {
      Note("チェックを外した種目は「種目を追加」に出なくなります。ガイドからはいつでも追加できます。")
      PartChips(selection: $app.part)
      VStack(spacing: 0) {
        ForEach(c.presets(app.part), id: \.self) { n in
          let on = !app.exset.hidden.contains(n)
          Button {
            if on { app.exset.hidden.append(n) } else { app.exset.hidden.removeAll { $0 == n } }
          } label: {
            HStack(spacing: 10) {
              Image(systemName: on ? "checkmark.square.fill" : "square").foregroundStyle(on ? p.c(p.accent) : p.c(p.muted)).font(.title3)
              Text(n).foregroundStyle(p.c(p.ink))
              Spacer()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(on ? .isSelected : [])
          Divider().overlay(p.c(p.line))
        }
      }
      if !own.isEmpty {
        Text("自分で足した種目").font(.subheadline.bold())
        ForEach(own, id: \.self) { n in
          HStack {
            Text(n)
            Spacer()
            Button { app.exset.own[app.part] = own.filter { $0 != n } } label: { Image(systemName: "trash").foregroundStyle(p.c(p.muted)) }
              .accessibilityLabel("\(n)を外す")
          }
          .padding(.vertical, 6)
        }
      }
      HStack(spacing: 8) {
        TextField("\(app.part)に種目を足す", text: $name)
          .onChange(of: name) { _, v in if v.count > 30 { name = String(v.prefix(30)) } }
          .submitLabel(.done)
          .onSubmit(add)
          .field(skin)
        Button("追加", action: add).skinButton(small: true)
      }
    }
  }

  private func add() {
    let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !n.isEmpty else { return }
    let c = Catalog.shared
    let p = c.partOf(n, app.exset)
    if let p, p != app.part { app.toast("\(n)は\(p)にあります"); return }
    if c.presets(app.part).contains(n) {
      app.exset.hidden.removeAll { $0 == n }
      app.toast("\(n)を表示に戻しました")
    } else if p != nil {
      app.toast("\(n)はすでに入っています"); return
    } else {
      app.exset.own[app.part] = app.exset.ownOf(app.part) + [n]
    }
    name = ""
  }
}

// MARK: ルーティン

struct RoutinesSheet: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @Query(sort: \Routine.order) private var routines: [Routine]
  @Query private var workouts: [Workout]
  var focusId: String
  @FocusState private var nameFocus: String?

  var body: some View {
    let p = skin.palette
    let names = Catalog.shared.allNames(app.exset, recorded: Calc.namesByCount(workouts))
    NavigationStack {
      ScrollViewReader { proxy in
        List {
          ForEach(routines) { r in
            RoutineSection(routine: r, names: names, nameFocus: $nameFocus)
          }
          Section {
            Button("＋ 新しいルーティン") { app.createRoutine([], context: context, routines: routines) }.bold()
          } footer: {
            Text("種目は長押しして上下にドラッグすると並び替えられます。")
          }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(p.c(p.bg))
        .navigationTitle("ルーティン")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("閉じる")
          }
        }
        .onAppear { focusName(focusId, proxy) }
        .onChange(of: app.routinesFocus) { _, v in if let v { focusName(v, proxy) } }
        .onDisappear { try? context.save() }
      }
    }
    .tint(p.c(p.ink))
    .preferredColorScheme(p.dark ? .dark : .light)
  }

  private func focusName(_ id: String, _ proxy: ScrollViewProxy) {
    guard !id.isEmpty else { return }
    Task {
      try? await Task.sleep(for: .milliseconds(350))
      withAnimation { proxy.scrollTo(id, anchor: .center) }
      nameFocus = id
    }
  }
}

/// ルーティン1つぶん：名前・種目の並び・種目の追加・削除
private struct RoutineSection: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  @Environment(\.modelContext) private var context
  var routine: Routine
  var names: [String]
  var nameFocus: FocusState<String?>.Binding
  @State private var name = ""
  @State private var adding = ""

  var body: some View {
    let p = skin.palette
    let r = routine
    let q = adding.trimmingCharacters(in: .whitespaces)
    let suggestions = q.isEmpty ? [] : Array(names.filter { $0.contains(q) && $0 != q && !r.exercises.contains($0) }.prefix(8))
    Section {
      TextField("ルーティンの名前", text: $name)
        .font(.headline)
        .focused(nameFocus, equals: r.id)
        .submitLabel(.done)
        .onChange(of: name) { _, v in if v.count > 30 { name = String(v.prefix(30)) } }
        .onSubmit(commitName)
        .onChange(of: nameFocus.wrappedValue) { old, _ in if old == r.id { commitName() } }
        .id(r.id)
        .accessibilityLabel("ルーティンの名前")
      ForEach(Array(r.exercises.enumerated()), id: \.offset) { i, n in
        HStack {
          ExerciseIcon(name: n, size: 24)
          Text(n)
          Spacer()
          Button { r.exercises.remove(at: i); try? context.save() } label: { Image(systemName: "trash").foregroundStyle(p.c(p.muted)) }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(n)を外す")
        }
      }
      .onMove { from, to in r.exercises.move(fromOffsets: from, toOffset: to); try? context.save() }
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          TextField("種目名", text: $adding)
            .submitLabel(.done)
            .onSubmit { add(adding) }
            .accessibilityLabel("\(r.name)に追加する種目")
          Button("追加") { add(adding) }.buttonStyle(.borderless).bold()
        }
        if !suggestions.isEmpty {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
              ForEach(suggestions, id: \.self) { n in Chip(n) { add(n) } }
            }
          }
        }
      }
      Button("このルーティンを削除", role: .destructive, action: delete)
    }
    .onAppear { name = r.name }
    .onChange(of: r.name) { _, v in if nameFocus.wrappedValue != r.id { name = v } }
  }

  /// 空にしたら元の名前に戻す
  private func commitName() {
    let v = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if v.isEmpty { name = routine.name; return }
    if v != routine.name { routine.name = v; try? context.save() }
  }

  private func add(_ raw: String) {
    let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !n.isEmpty else { return }
    if routine.exercises.contains(n) { app.toast("\(n)はすでに入っています"); return }
    routine.exercises.append(n)
    try? context.save()
    adding = ""
  }

  private func delete() {
    let r = routine
    app.ask("「\(r.name)」を削除しますか？", "ルーティンだけを消します。保存済みの記録はそのまま残ります。", ok: "削除") {
      context.delete(r)
      try? context.save()
      app.toast("ルーティンを削除しました")
    }
  }
}

// MARK: 休憩タイマー

struct RestBar: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin

  var body: some View {
    let p = skin.palette
    Group {
      if let r = app.rest {
        TimelineView(.periodic(from: .now, by: 0.25)) { tl in
          let left = max(0, Int(ceil(r.end.timeIntervalSince(tl.date))))
          VStack(spacing: 8) {
            HStack(spacing: 8) {
              Text("休憩").font(.caption.bold()).foregroundStyle(p.c(p.muted))
              Text(Fmt.clock(left)).font(skin.num(34)).foregroundStyle(skin == .clock ? p.c(p.accent) : p.c(p.ink))
                .monospacedDigit()
                .accessibilityLabel("残り\(left / 60)分\(left % 60)秒")
              Spacer(minLength: 0)
              Button("−15秒") { app.adjustRest(-15) }.skinButton(small: true)
              Button("＋15秒") { app.adjustRest(15) }.skinButton(small: true)
              Button("止める") { app.stopRest() }.skinButton(small: true)
            }
            GeometryReader { g in
              ZStack(alignment: .leading) {
                Capsule().fill(p.c(p.line))
                Capsule().fill(p.c(p.accent)).frame(width: g.size.width * min(1, max(0, r.end.timeIntervalSince(tl.date) / r.total)))
              }
            }
            .frame(height: 5)
          }
        }
      } else {
        HStack(spacing: 8) {
          Text("休憩\n（秒）").font(.caption2.bold()).foregroundStyle(p.c(p.muted)).multilineTextAlignment(.leading)
          ForEach(AppState.restSecs, id: \.self) { s in
            Chip("\(s)", selected: s == app.restSec) { app.restSec = s }
          }
          Spacer(minLength: 0)
          Button("開始") { app.startRest() }.skinButton(.primary, small: true)
        }
      }
    }
    .padding(.horizontal, 16).padding(.vertical, 10)
    .background(skin == .clock ? Color.black : p.c(p.surface))
    .overlay(alignment: .top) { p.c(p.line).frame(height: 1) }
  }
}

// MARK: 折り返して並べる

struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(proposal.width ?? .infinity, subviews)
    return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for row in arrange(bounds.width, subviews) {
      var x = bounds.minX
      for i in row.items {
        let s = subviews[i].sizeThatFits(.unspecified)
        subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y + (row.height - s.height) / 2), proposal: ProposedViewSize(width: min(s.width, bounds.width), height: s.height))
        x += min(s.width, bounds.width) + spacing
      }
    }
  }

  private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

  private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
    var rows: [Row] = [], cur = Row()
    for (i, v) in subviews.enumerated() {
      let s = v.sizeThatFits(.unspecified)
      let w = min(s.width, maxWidth)
      if !cur.items.isEmpty, cur.width + spacing + w > maxWidth {
        rows.append(cur)
        cur = Row(y: cur.y + cur.height + spacing)
      }
      cur.width += (cur.items.isEmpty ? 0 : spacing) + w
      cur.height = max(cur.height, s.height)
      cur.items.append(i)
    }
    if !cur.items.isEmpty { rows.append(cur) }
    return rows
  }
}
