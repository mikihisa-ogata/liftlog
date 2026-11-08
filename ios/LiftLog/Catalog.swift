import Foundation

// 既定の種目・筋肉・種目ガイド（docs/spec.md 3章）。中身は Resources/guide.json にあり、
// ios/scripts/export-guide.mjs が Web 版の index.html から書き出す

/// 図の1つの形。Web 版の SVG の要素をそのまま写したもの
struct FigureShape: Decodable, Sendable {
  /// line / polyline / polygon / circle / rect
  var k: String
  /// ghost（スタートの薄い姿勢）/ body / gear / arrow / floor
  var layer: String
  var solid: Bool?
  var sw: Double?
  var p: [[Double]]?
  var cx: Double?, cy: Double?, r: Double?
  var x: Double?, y: Double?, w: Double?, h: Double?, rx: Double?
}

/// 1枚の図。vb は viewBox、sc は床（y=146）を中心にした拡大率
struct Figure: Decodable, Sendable {
  var vb: [Double]
  var sc: Double
  var items: [FigureShape]
}

struct Guide: Decodable, Sendable {
  var gear: String
  var main: [String]
  var sub: [String]
  /// 正面から見た図か（そうでなければ横から）
  var front: Bool
  var note: String
  var steps: [String]
  var tips: [String]
  var start: Figure
  var finish: Figure
  var icon: Figure
}

struct Muscle: Decodable, Sendable, Hashable {
  var key: String
  var name: String
  var short: String
}

struct BodyMapData: Decodable, Sendable {
  struct View: Decodable, Sendable {
    struct Part: Decodable, Sendable { var m: String; var d: [String] }
    var mid: [String]
    var parts: [Part]
  }
  struct Silhouette: Decodable, Sendable { var ellipse: [Double]; var path: String }
}

struct Catalog: Decodable, Sendable {
  struct Part: Decodable, Sendable { var name: String; var exercises: [String] }
  var parts: [Part]
  var muscles: [Muscle]
  var guide: [String: Guide]
  var sil: BodyMapData.Silhouette
  var body: [String: BodyMapData.View]

  static let shared: Catalog = {
    guard let url = Bundle.main.url(forResource: "guide", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let c = try? JSONDecoder().decode(Catalog.self, from: data)
    else { fatalError("guide.json を読めません。node ios/scripts/export-guide.mjs で作り直してください") }
    return c
  }()

  /// 部位の名前（胸・肩・背中・腕・腹・脚）
  var partNames: [String] { parts.map(\.name) }

  func presets(_ part: String) -> [String] { parts.first { $0.name == part }?.exercises ?? [] }

  func muscleName(_ key: String) -> String { muscles.first { $0.key == key }?.name ?? key }
  func muscleShort(_ key: String) -> String { muscles.first { $0.key == key }?.short ?? key }

  /// 種目の部位。既定の種目と自分で足した種目から引き、どちらにもなければ nil
  func partOf(_ name: String, _ x: ExerciseSettings) -> String? {
    partNames.first { presets($0).contains(name) || x.ownOf($0).contains(name) }
  }

  /// 記録画面に出す種目（非表示にした既定の種目を除き、自分で足した種目を後ろに）
  func shownOf(_ part: String, _ x: ExerciseSettings) -> [String] {
    presets(part).filter { !x.hidden.contains($0) } + x.ownOf(part)
  }

  /// ルーティンの種目の候補：既定の種目＋自分で足した種目＋記録にある種目
  func allNames(_ x: ExerciseSettings, recorded: [String]) -> [String] {
    var seen = Set<String>(), out: [String] = []
    for n in partNames.flatMap({ presets($0) + x.ownOf($0) }) + recorded where seen.insert(n).inserted { out.append(n) }
    return out
  }
}

extension ExerciseSettings {
  func ownOf(_ part: String) -> [String] { own[part] ?? [] }
}
