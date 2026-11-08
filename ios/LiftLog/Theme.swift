import SwiftUI

// テーマ（docs/spec.md 2.11）。どのテーマも決まった見た目なので、OS のライト／ダーク設定には追従しない

enum Skin: String, CaseIterable, Identifiable, Sendable {
  case iron, plate, clock
  var id: String { rawValue }

  var name: String {
    switch self {
    case .iron: "アイアン"
    case .plate: "プレート"
    case .clock: "ジムクロック"
    }
  }

  /// テーマを選ぶ画面の見本の文字
  var swatch: String {
    switch self {
    case .iron: "IRON"
    case .plate: "PLATE"
    case .clock: "01:24"
    }
  }

  var palette: Palette {
    switch self {
    case .iron:
      Palette(bg: 0x0d0d0d, surface: 0x1a1a1a, field: 0x0d0d0d, ink: 0xf2f2f2, muted: 0xb3b3b3, line: 0x3a3a3a,
              accent: 0xffd400, accentInk: 0x000000, accentSoft: 0x2b2600, pr: 0xffd400, prInk: 0x000000, danger: 0xff5a4f,
              topBand: 0x0d0d0d, mapSkin: 0x262626, mapOff: 0x3d3d3d, radius: 0, radiusCtl: 0, dark: true)
    case .plate:
      Palette(bg: 0xf4f4f2, surface: 0xffffff, field: 0xf4f4f2, ink: 0x111111, muted: 0x555555, line: 0xd4d4cf,
              accent: 0xcf1f16, accentInk: 0xffffff, accentSoft: 0xfde4e2, pr: 0xffc20e, prInk: 0x111111, danger: 0xcf1f16,
              topBand: 0x111111, mapSkin: 0xe4e4e0, mapOff: 0xc9c9c3, radius: 18, radiusCtl: 999, dark: false)
    case .clock:
      Palette(bg: 0x0a0a0c, surface: 0x141418, field: 0x0a0a0c, ink: 0xededf0, muted: 0xa8a8b4, line: 0x34343c,
              accent: 0xff2e2e, accentInk: 0xffffff, accentSoft: 0x2a0f11, pr: 0x39ff88, prInk: 0x04140a, danger: 0xff2e2e,
              topBand: 0x0a0a0c, mapSkin: 0x202026, mapOff: 0x383840, radius: 10, radiusCtl: 10, dark: true)
    }
  }

  /// 数字のフォント。Web 版の Anton / Barlow Condensed（斜体）/ Share Tech Mono に近い端末内のフォントを使う
  func num(_ size: CGFloat) -> Font {
    switch self {
    case .iron: .system(size: size, weight: .bold).width(.compressed)
    case .plate: .system(size: size, weight: .black).width(.condensed).italic()
    case .clock: .system(size: size, weight: .regular, design: .monospaced)
    }
  }
}

struct Palette: Sendable {
  var bg, surface, field, ink, muted, line, accent, accentInk, accentSoft, pr, prInk, danger, topBand, mapSkin, mapOff: UInt32
  var radius: CGFloat
  var radiusCtl: CGFloat
  var dark: Bool

  func c(_ hex: UInt32) -> Color { Color(hex: hex) }

  /// 人体図の色の濃さ（0〜4）。アクセント色を部位の地の色に 30 / 55 / 80 / 100% 混ぜる
  func level(_ lv: Int) -> Color {
    let k: [Double] = [0, 0.3, 0.55, 0.8, 1]
    return Color(hex: Self.mix(accent, mapOff, k[max(0, min(4, lv))]))
  }

  static func mix(_ a: UInt32, _ b: UInt32, _ k: Double) -> UInt32 {
    func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xff) }
    func m(_ s: UInt32) -> UInt32 { UInt32((ch(a, s) * k + ch(b, s) * (1 - k)).rounded()) << s }
    return m(16) | m(8) | m(0)
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
  }
}

private struct SkinKey: EnvironmentKey { static let defaultValue: Skin = .iron }

extension EnvironmentValues {
  var skin: Skin {
    get { self[SkinKey.self] }
    set { self[SkinKey.self] = newValue }
  }
}

// MARK: よく使う部品

/// 面（カード）
struct Card<Content: View>: View {
  @Environment(\.skin) private var skin
  var padding: CGFloat = 14
  @ViewBuilder var content: Content

  var body: some View {
    let p = skin.palette
    VStack(alignment: .leading, spacing: 10) { content }
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(p.c(p.surface), in: RoundedRectangle(cornerRadius: p.radius))
      .overlay {
        if skin != .plate { RoundedRectangle(cornerRadius: p.radius).strokeBorder(p.c(p.line)) }
      }
  }
}

/// 見出し（h2）
struct SectionTitle: View {
  @Environment(\.skin) private var skin
  var text: String
  var body: some View {
    Text(text).font(.system(size: 17, weight: .heavy)).foregroundStyle(skin.palette.c(skin.palette.ink))
  }
}

/// 注記（小さい灰色の文）
struct Note: View {
  @Environment(\.skin) private var skin
  var text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text).font(.footnote).foregroundStyle(skin.palette.c(skin.palette.muted)).fixedSize(horizontal: false, vertical: true)
  }
}

/// 選択できる丸いチップ
struct Chip<Label: View>: View {
  @Environment(\.skin) private var skin
  var selected = false
  var action: () -> Void
  @ViewBuilder var label: Label

  var body: some View {
    let p = skin.palette
    Button(action: action) {
      label
        .font(.system(size: 14, weight: .bold))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .foregroundStyle(selected ? p.c(p.accentInk) : p.c(p.ink))
        .background(selected ? p.c(p.accent) : p.c(p.surface), in: RoundedRectangle(cornerRadius: min(p.radiusCtl, 18)))
        .overlay { RoundedRectangle(cornerRadius: min(p.radiusCtl, 18)).strokeBorder(selected ? p.c(p.accent) : p.c(p.line)) }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

extension Chip where Label == Text {
  init(_ title: String, selected: Bool = false, action: @escaping () -> Void) {
    self.init(selected: selected, action: action) { Text(title) }
  }
}

enum ButtonKind { case normal, primary, danger }

/// Web 版の .btn
struct SkinButtonStyle: ButtonStyle {
  @Environment(\.skin) private var skin
  @Environment(\.isEnabled) private var enabled
  var kind: ButtonKind = .normal
  var small = false

  func makeBody(configuration: Configuration) -> some View {
    let p = skin.palette
    let fg: Color = switch kind {
    case .primary: p.c(p.accentInk)
    case .danger: p.c(p.danger)
    case .normal: p.c(p.ink)
    }
    configuration.label
      .font(.system(size: small ? 13 : 15, weight: .bold))
      .lineLimit(1).minimumScaleFactor(0.7)
      .padding(.horizontal, small ? 12 : 16).padding(.vertical, small ? 7 : 12)
      .frame(maxWidth: small ? nil : .infinity)
      .foregroundStyle(fg)
      .background(kind == .primary ? p.c(p.accent) : p.c(p.surface), in: RoundedRectangle(cornerRadius: min(p.radiusCtl, 22)))
      .overlay { if kind != .primary { RoundedRectangle(cornerRadius: min(p.radiusCtl, 22)).strokeBorder(p.c(p.line)) } }
      .opacity(configuration.isPressed ? 0.7 : enabled ? 1 : 0.5)
      .contentShape(Rectangle())
  }
}

extension View {
  func skinButton(_ kind: ButtonKind = .normal, small: Bool = false) -> some View {
    buttonStyle(SkinButtonStyle(kind: kind, small: small))
  }

  /// 入力欄の見た目
  func field(_ skin: Skin) -> some View {
    let p = skin.palette
    return padding(.horizontal, 10).padding(.vertical, 9)
      .background(p.c(p.field), in: RoundedRectangle(cornerRadius: min(p.radiusCtl, 12)))
      .overlay { RoundedRectangle(cornerRadius: min(p.radiusCtl, 12)).strokeBorder(p.c(p.line)) }
      .foregroundStyle(p.c(p.ink))
  }
}

/// 小さいバッジ（サンプル・自己ベスト）
struct Badge: View {
  @Environment(\.skin) private var skin
  var text: String
  var pr = false
  var body: some View {
    let p = skin.palette
    Text(text).font(.system(size: 11, weight: .heavy))
      .padding(.horizontal, 6).padding(.vertical, 2)
      .foregroundStyle(pr ? p.c(p.prInk) : p.c(p.muted))
      .background(pr ? p.c(p.pr) : p.c(p.field), in: RoundedRectangle(cornerRadius: 4))
      .overlay { if !pr { RoundedRectangle(cornerRadius: 4).strokeBorder(p.c(p.line)) } }
  }
}

/// 「×」で閉じる見出し付きのシート
struct SheetFrame<Content: View>: View {
  @Environment(\.skin) private var skin
  @Environment(\.dismiss) private var dismiss
  var title: String
  @ViewBuilder var content: Content

  var body: some View {
    let p = skin.palette
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) { content }
          .padding(16)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(p.c(p.bg))
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("閉じる")
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("完了") { hideKeyboard() }
        }
      }
    }
    .tint(p.c(p.ink))
    .preferredColorScheme(p.dark ? .dark : .light)
  }
}

@MainActor
func hideKeyboard() {
  UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
