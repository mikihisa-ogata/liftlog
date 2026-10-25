import SwiftData
import SwiftUI

@main
struct LiftLogApp: App {
  var body: some Scene {
    WindowGroup {
      RootView()
    }
    .modelContainer(for: LiftLogSchema.models)
  }
}

/// 下タブ。今はバックアップの読み込みを確かめるため、履歴タブだけ中身がある
struct RootView: View {
  var body: some View {
    TabView {
      Tab("記録", systemImage: "pencil") { Placeholder(title: "記録") }
      Tab("履歴", systemImage: "calendar") { HistoryView() }
      Tab("推移", systemImage: "chart.line.uptrend.xyaxis") { Placeholder(title: "推移") }
      Tab("体", systemImage: "camera") { Placeholder(title: "体") }
      Tab("ガイド", systemImage: "book") { Placeholder(title: "ガイド") }
    }
  }
}

private struct Placeholder: View {
  let title: String
  var body: some View {
    NavigationStack {
      ContentUnavailableView("準備中", systemImage: "hammer", description: Text("この画面はまだ移植していません"))
        .navigationTitle(title)
    }
  }
}
