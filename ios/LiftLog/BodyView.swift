import PhotosUI
import SwiftData
import SwiftUI

// 写真タブ（docs/spec.md 2.9）。写真は端末の中（SwiftData）だけに保存する

struct BodyView: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  @Environment(\.modelContext) private var context
  @Query private var photos: [Photo]
  @Query private var weights: [BodyWeight]
  @State private var pickerItem: PhotosPickerItem?
  @State private var camera = false
  @State private var newPhoto: NewPhoto?
  @State private var selected: [String] = []

  struct NewPhoto: Identifiable {
    let id = UUID()
    var jpeg: Data
  }

  private var sorted: [Photo] {
    photos.sorted { $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt }
  }

  private func weight(_ ph: Photo) -> Double? { weights.first { $0.date == ph.date }?.w }

  var body: some View {
    let p = skin.palette
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack(spacing: 10) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
              Button("撮影する") { camera = true }.skinButton(.primary)
            }
            PhotosPicker(selection: $pickerItem, matching: .images) { Text("写真から選ぶ") }
              .skinButton(UIImagePickerController.isSourceTypeAvailable(.camera) ? .normal : .primary)
          }
          .id("top")
          if photos.isEmpty {
            Note("まだ写真がありません。同じ場所・同じ姿勢で定期的に撮っておくと、見た目の変化を並べて比べられます。")
          } else {
            if photos.contains(where: \.isExample) {
              Card {
                Note("「サンプル」の付いた写真は見本です。自分の写真を撮り始めたら消してください。")
                Button("サンプルを削除", action: deleteSamples).skinButton(small: true)
              }
            }
            if photos.count >= 2 { compare }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
              ForEach(sorted) { ph in tile(ph, proxy) }
            }
          }
          Note("写真はこの端末の中だけに保存され、外には送りません。容量が大きくなるため、履歴の「バックアップ」には含まれません。")
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
      }
      .background(p.c(p.bg))
    }
    .onChange(of: pickerItem) { _, item in
      guard let item else { return }
      pickerItem = nil
      Task {
        guard let data = try? await item.loadTransferable(type: Data.self), let jpeg = ImageShrink.jpeg(data) else {
          app.toast("この写真は読み込めませんでした"); return
        }
        newPhoto = NewPhoto(jpeg: jpeg)
      }
    }
    .fullScreenCover(isPresented: $camera) {
      CameraPicker { image in
        camera = false
        guard let image else { return }
        if let jpeg = ImageShrink.jpeg(image) { newPhoto = NewPhoto(jpeg: jpeg) } else { app.toast("この写真は読み込めませんでした") }
      }
      .ignoresSafeArea()
    }
    .sheet(item: $newPhoto) { NewPhotoSheet(jpeg: $0.jpeg) }
  }

  // MARK: ビフォー・アフター

  private var compare: some View {
    let p = skin.palette
    let pick = selected.compactMap { id in photos.first { $0.id == id } }.sorted { $0.date != $1.date ? $0.date < $1.date : $0.createdAt < $1.createdAt }
    return Card {
      HStack {
        SectionTitle(text: "ビフォー・アフター")
        Spacer()
        if !pick.isEmpty { Button("選択を解除") { selected = [] }.font(.footnote.bold()).foregroundStyle(p.c(p.accent)) }
      }
      HStack(alignment: .top, spacing: 10) {
        slot(pick.first, "ビフォー")
        slot(pick.count > 1 ? pick[1] : nil, "アフター")
      }
      if pick.count == 2 {
        let days = Day.between(pick[0].date, pick[1].date)
        let dw = weight(pick[0]).flatMap { a in weight(pick[1]).map { $0 - a } }
        Note("\(days)日間" + (dw.map { "・体重 \($0 > 0 ? "+" : "")\(Fmt.w($0)) kg" } ?? ""))
      }
    }
  }

  @ViewBuilder private func slot(_ ph: Photo?, _ label: String) -> some View {
    let p = skin.palette
    if let ph {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(label).font(.caption.bold())
          Spacer()
          Text(Day.long(ph.date)).font(.caption2).foregroundStyle(p.c(p.muted))
        }
        Color.clear.aspectRatio(3 / 4, contentMode: .fit)
          .overlay { PhotoImage(data: ph.jpeg, thumb: 600, fill: true) }
          .clipShape(RoundedRectangle(cornerRadius: 8))
        if let w = weight(ph) { (Text(Fmt.w(w)).font(skin.num(18)) + Text(" kg").font(.caption)) }
      }
      .frame(maxWidth: .infinity)
    } else {
      Text("一覧の「比較」で写真を選んでください")
        .font(.footnote).foregroundStyle(p.c(p.muted)).multilineTextAlignment(.center)
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 160)
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(p.c(p.line), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])) }
    }
  }

  private func tile(_ ph: Photo, _ proxy: ScrollViewProxy) -> some View {
    let p = skin.palette
    let sel = selected.contains(ph.id)
    return VStack(alignment: .leading, spacing: 6) {
      Color.clear.aspectRatio(3 / 4, contentMode: .fit)
        .overlay { PhotoImage(data: ph.jpeg, thumb: 400, fill: true) }
        .clipShape(RoundedRectangle(cornerRadius: 6))
      HStack(spacing: 4) {
        Text(Day.long(ph.date)).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
        if ph.isExample { Badge(text: "サンプル") }
      }
      if let w = weight(ph) { (Text(Fmt.w(w)).font(skin.num(16)) + Text(" kg").font(.caption2)) }
      if !ph.memo.isEmpty { Text(ph.memo).font(.caption2).foregroundStyle(p.c(p.muted)).lineLimit(3) }
      HStack(spacing: 6) {
        Button("比較") {
          if let i = selected.firstIndex(of: ph.id) { selected.remove(at: i) } else {
            selected.append(ph.id)
            if selected.count > 2 { selected.removeFirst() }
          }
          if selected.count == 2 { withAnimation { proxy.scrollTo("top", anchor: .top) } }
        }
        .skinButton(sel ? .primary : .normal, small: true)
        .accessibilityAddTraits(sel ? .isSelected : [])
        Button("削除") { delete(ph) }.skinButton(.danger, small: true)
      }
    }
    .padding(8)
    .background(p.c(p.surface), in: RoundedRectangle(cornerRadius: p.radius))
    .overlay { RoundedRectangle(cornerRadius: p.radius).strokeBorder(sel ? p.c(p.accent) : p.c(p.line), lineWidth: sel ? 2 : 1) }
  }

  private func delete(_ ph: Photo) {
    app.ask("\(DateText.short(ph.date))の写真を削除しますか？", "削除した写真は元に戻せません。", ok: "削除") {
      selected.removeAll { $0 == ph.id }
      context.delete(ph)
      do { try context.save(); app.toast("写真を削除しました") } catch { app.toast("削除できませんでした。もう一度試してください") }
    }
  }

  private func deleteSamples() {
    app.ask("サンプルの写真を削除しますか？", "最初に入っている見本の写真をすべて消します。自分で撮った写真は消えません。", ok: "削除") {
      for ph in photos where ph.isExample { context.delete(ph) }
      try? context.save()
      app.toast("サンプルの写真を削除しました")
    }
  }
}

/// 写真を保存する前に、日付・体重・メモを入れる
private struct NewPhotoSheet: View {
  @Environment(AppState.self) private var app
  @Environment(\.skin) private var skin
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @Query private var weights: [BodyWeight]
  var jpeg: Data
  @State private var date = Day.today()
  @State private var w = ""
  @State private var memo = ""

  var body: some View {
    let p = skin.palette
    SheetFrame(title: "写真を保存") {
      PhotoImage(data: jpeg, thumb: 800).frame(maxHeight: 320).frame(maxWidth: .infinity)
      HStack {
        Text("日付").font(.caption.bold()).foregroundStyle(p.c(p.muted))
        Spacer()
        DatePicker("日付", selection: Binding(get: { Day.date(date) ?? .now }, set: { date = DateText.ymd($0, calendar: Day.calendar) }),
                   in: ...Date.now, displayedComponents: .date)
          .labelsHidden()
          .environment(\.locale, Locale(identifier: "ja_JP"))
      }
      VStack(alignment: .leading, spacing: 4) {
        Text("体重（kg・任意）").font(.caption.bold()).foregroundStyle(p.c(p.muted))
        TextField("", text: $w).keyboardType(.decimalPad).field(skin)
      }
      VStack(alignment: .leading, spacing: 4) {
        Text("メモ（任意）").font(.caption.bold()).foregroundStyle(p.c(p.muted))
        TextField("朝・食前など、撮った条件", text: $memo, axis: .vertical).lineLimit(2...5).field(skin)
      }
      HStack(spacing: 10) {
        Button("キャンセル") { dismiss() }.skinButton()
        Button("保存", action: save).skinButton(.primary)
      }
    }
    .onAppear(perform: fill)
    .onChange(of: date) { fill() }
  }

  /// 日付を変えたら、その日の体重を入れておく
  private func fill() { w = weights.first { $0.date == date }.map { Fmt.w($0.w) } ?? "" }

  private func save() {
    let wv = Calc.round1(AppState.number(w))
    context.insert(Photo(id: NewId.make("p"), date: date, memo: memo.trimmingCharacters(in: .whitespacesAndNewlines), jpeg: jpeg, createdAt: Date.now.timeIntervalSince1970 * 1000))
    // 体重は体重の記録に入れる（体脂肪率は残す）。空のときはその日の記録に触らない
    if wv > 0 {
      if let b = weights.first(where: { $0.date == date }) { b.w = wv } else { context.insert(BodyWeight(date: date, w: wv)) }
    }
    do {
      try context.save()
      app.toast("\(DateText.short(date))の写真を保存しました")
      dismiss()
    } catch {
      context.rollback()
      app.toast("保存できませんでした。端末の空き容量を確かめてください")
    }
  }
}

/// JPEG を縮小して表示する（一覧で大きな画像をそのまま描かないように）。
/// 縦横比は元の写真のまま。fill のときは枠いっぱいに広げてはみ出しを切る（枠は呼び出し側で決める）
struct PhotoImage: View {
  var data: Data
  var thumb: CGFloat
  var fill = false
  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
      } else {
        Color.gray.opacity(0.2)
      }
    }
    .task(id: data.count) {
      let d = data, size = thumb
      image = await Task.detached { () -> UIImage? in
        guard let img = UIImage(data: d) else { return nil }
        // preparingThumbnail は指定サイズに合わせて伸縮するので、元の縦横比を保ったサイズを渡す
        let k = min(1, size / max(img.size.width, img.size.height) * 4 / 3)
        let to = CGSize(width: (img.size.width * k).rounded(), height: (img.size.height * k).rounded())
        return img.preparingThumbnail(of: to) ?? img
      }.value
    }
    .accessibilityHidden(true)
  }
}

enum ImageShrink {
  /// 長辺1080pxの JPEG（品質0.8）
  static func jpeg(_ data: Data) -> Data? { UIImage(data: data).flatMap(jpeg) }

  static func jpeg(_ image: UIImage) -> Data? {
    let k = min(1, 1080 / max(image.size.width, image.size.height))
    let size = CGSize(width: (image.size.width * k).rounded(), height: (image.size.height * k).rounded())
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let out = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    return out.jpegData(compressionQuality: 0.8)
  }
}

/// カメラで撮る（UIImagePickerController）
struct CameraPicker: UIViewControllerRepresentable {
  var done: (UIImage?) -> Void

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let c = UIImagePickerController()
    c.sourceType = .camera
    c.delegate = context.coordinator
    return c
  }

  func updateUIViewController(_ c: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator(done: done) }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let done: (UIImage?) -> Void
    init(done: @escaping (UIImage?) -> Void) { self.done = done }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      done(info[.originalImage] as? UIImage)
    }
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
  }
}
