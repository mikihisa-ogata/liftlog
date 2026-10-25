import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 履歴タブ（仮）。読み込んだ記録の一覧と、バックアップの書き出し・読み込みだけを置く
struct HistoryView: View {
  @Environment(\.modelContext) private var context
  @Query(sort: Workout.newestFirst) private var workouts: [Workout]
  @Query private var weights: [BodyWeight]
  @Query private var routines: [Routine]
  @State private var importing = false
  @State private var exportDoc: BackupDocument?
  @State private var message: String?

  var body: some View {
    NavigationStack {
      List {
        if workouts.isEmpty {
          Text("まだ記録がありません。「記録」タブで種目とセットを入れて保存すると、ここに日付ごとに並びます。")
            .foregroundStyle(.secondary)
        }
        ForEach(workouts) { w in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(DateText.short(w.date)).bold()
              if w.isExample { Text("サンプル").font(.caption).foregroundStyle(.secondary) }
              Spacer()
              Text("\(w.exercises.count)種目 · \(w.exercises.reduce(0) { $0 + $1.sets.count })セット")
                .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(w.exercises.enumerated()), id: \.offset) { _, e in
              Text("\(e.name)  \(SetText.summary(e.sets))").font(.subheadline)
            }
            if !w.memo.isEmpty { Text(w.memo).font(.caption).foregroundStyle(.secondary) }
          }
        }
        Section("バックアップ") {
          Text("記録はこの端末の中だけに保存されます。機種変更の前や、ときどきの控えとしてファイルに書き出しておいてください。読み込むと、同じ記録は上書きされ、それ以外は追加されます。体重の記録、ルーティン、記録画面に出す種目の設定も含まれますが、体の写真は含まれません。")
            .font(.footnote).foregroundStyle(.secondary)
          Text("記録 \(workouts.count)件・体重 \(weights.count)日・ルーティン \(routines.count)件")
            .font(.footnote)
          Button("ファイルに書き出す") { exportBackup() }
          Button("ファイルから読み込む") { importing = true }
        }
      }
      .navigationTitle("履歴")
      .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { importBackup($0) }
      .fileExporter(isPresented: Binding(get: { exportDoc != nil }, set: { if !$0 { exportDoc = nil } }),
                    document: exportDoc, contentType: .json, defaultFilename: Backup.fileName()) { result in
        if case .success = result { message = "バックアップを書き出しました" }
      }
      .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {}
    }
  }

  private func exportBackup() {
    do { exportDoc = BackupDocument(data: try Backup.export(from: context)) }
    catch { message = "書き出せませんでした。もう一度試してください" }
  }

  private func importBackup(_ result: Result<URL, Error>) {
    guard case .success(let url) = result else { return }
    // ファイルアプリから選んだファイルは、読む間だけアクセス権を取る
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let contents = try Backup.parse(try Data(contentsOf: url))
      try Backup.apply(contents, to: context)
      message = contents.summary
    } catch {
      message = Backup.failureMessage
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

enum SetText {
  /// 重量は小数1桁まで、末尾の .0 は付けない（Web 版の fmtW）
  static func weight(_ w: Double) -> String {
    let v = (w * 10).rounded() / 10
    return v == v.rounded() ? String(Int(v)) : String(v)
  }

  /// "60×8 · 自重×10"（Web 版の setsText）
  static func summary(_ sets: [SetRecord]) -> String {
    sets.map { ($0.w != 0 ? weight($0.w) + "×" : "自重×") + String($0.r) }.joined(separator: " · ")
  }
}
