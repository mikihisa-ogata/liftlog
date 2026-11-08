import SwiftData
import SwiftUI
import UserNotifications

@main
struct LiftLogApp: App {
  @State private var app = AppState()
  private let container: ModelContainer
  private let notifications = NotificationDelegate()

  init() {
    do {
      container = try ModelContainer(for: Schema(LiftLogSchema.models))
    } catch {
      fatalError("保存先を開けませんでした: \(error)")
    }
    UNUserNotificationCenter.current().delegate = notifications
    // UI テストでは見本を入れない状態から始められるようにする
    if !ProcessInfo.processInfo.arguments.contains("-noSeed") {
      Seed.run(container.mainContext)
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(app)
    }
    .modelContainer(container)
  }
}

/// 下タブ。ヒーロー（ロゴ・テーマ・まとめ）は記録タブだけに出す
struct RootView: View {
  @Environment(AppState.self) private var app
  @Environment(\.scenePhase) private var phase

  var body: some View {
    @Bindable var app = app
    let skin = app.skin, p = skin.palette
    TabView(selection: $app.tab) {
      Tab("記録", systemImage: "square.and.pencil", value: AppTab.log) { tab(LogView(), .log) }
      Tab("履歴", systemImage: "calendar", value: AppTab.history) { tab(HistoryView(), .history) }
      Tab("推移", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) { tab(TrendView(), .progress) }
      Tab("写真", systemImage: "camera", value: AppTab.body) { tab(BodyView(), .body) }
      Tab("ガイド", systemImage: "book", value: AppTab.guide) { tab(GuideView(), .guide) }
    }
    .tint(p.c(p.accent))
    .environment(\.skin, skin)
    .preferredColorScheme(p.dark ? .dark : .light)
    .overlay(alignment: .bottom) { toast }
    .alert(app.confirm?.title ?? "", isPresented: Binding(get: { app.confirm != nil }, set: { if !$0 { app.confirm = nil } }), presenting: app.confirm) { c in
      Button("キャンセル", role: .cancel) {}
      if let alt = c.alt { Button(alt) { c.onAlt?() } }
      Button(c.ok, role: c.destructive ? .destructive : nil) { c.onOK() }
    } message: { c in
      Text(c.note)
    }
    .sheet(item: $app.guide) { GuideSheet(request: $0).environment(\.skin, skin) }
    .sheet(isPresented: Binding(get: { app.routinesFocus != nil }, set: { if !$0 { app.routinesFocus = nil } })) {
      RoutinesSheet(focusId: app.routinesFocus ?? "").environment(\.skin, skin)
    }
    .sheet(isPresented: $app.showWeek) { WeekSheet().environment(\.skin, skin) }
    .sheet(isPresented: $app.showSkins) {
      SkinSheet().environment(\.skin, skin).presentationDetents([.medium])
    }
    .onAppear {
      app.resumeRest()
      app.checkRest()
      syncIdle()
    }
    .onChange(of: phase) { _, ph in
      app.isActive = ph == .active
      if ph == .active {
        app.checkRest()
        app.freshDraftDate()
      }
      syncIdle()
    }
    .onChange(of: app.tab) { syncIdle() }
    .onChange(of: app.rest) { syncIdle() }
  }

  /// 休憩タイマーは記録タブでは常に、数えている間はほかのタブでも出す
  private func tab(_ content: some View, _ t: AppTab) -> some View {
    let p = app.skin.palette
    return NavigationStack {
      content
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if t == .log || app.rest != nil { RestBar() }
        }
    }
    .toolbarBackground(p.c(p.surface), for: .tabBar)
    .toolbarBackground(.visible, for: .tabBar)
  }

  /// 記録タブを開いている間とタイマー計測中は画面を消さない
  private func syncIdle() {
    UIApplication.shared.isIdleTimerDisabled = phase == .active && (app.tab == .log || app.rest != nil)
  }

  @ViewBuilder private var toast: some View {
    let p = app.skin.palette
    if let t = app.toastText {
      Text(t)
        .font(.subheadline.bold())
        .multilineTextAlignment(.center)
        .foregroundStyle(p.c(p.bg))
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(p.c(p.ink), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
        .padding(.bottom, app.tab == .log || app.rest != nil ? 150 : 90)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .id(t)
        .allowsHitTesting(false)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear { UIAccessibility.post(notification: .announcement, argument: t) }
    }
  }
}

/// テーマを選ぶ。選ぶとすぐ反映し、開いたままにする
private struct SkinSheet: View {
  @Environment(AppState.self) private var app

  var body: some View {
    SheetFrame(title: "テーマ") {
      ForEach(Skin.allCases) { s in
        let sp = s.palette
        Button { app.skin = s } label: {
          HStack(spacing: 14) {
            Text(s.swatch).font(s.num(24))
              .foregroundStyle(sp.c(s == .plate ? 0xffffff : sp.accent))
              .frame(width: 110, height: 52)
              .background(sp.c(s == .plate ? sp.accent : sp.bg), in: RoundedRectangle(cornerRadius: 10))
            Text(s.name).font(.headline)
            Spacer()
            if app.skin == s { Image(systemName: "checkmark").font(.headline) }
          }
          .padding(10)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(app.skin == s ? .isSelected : [])
      }
    }
    .environment(\.skin, app.skin)
  }
}
