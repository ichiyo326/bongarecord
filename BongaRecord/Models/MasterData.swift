import Foundation

// MARK: - Role

enum CharacterRole: Int, CaseIterable, Codable, Identifiable, Hashable {
    case bomber   = 0
    case attacker = 1
    case shooter  = 2
    case blocker  = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .bomber:   return "ボマー"
        case .attacker: return "アタッカー"
        case .shooter:  return "シューター"
        case .blocker:  return "ブロッカー"
        }
    }

    var iconName: String {
        switch self {
        case .bomber:   return "flame.fill"
        case .attacker: return "hand.raised.fill"
        case .shooter:  return "scope"
        case .blocker:  return "cube.fill"
        }
    }
}

// MARK: - Character / Map (静的マスター、ID参照用)

struct GameCharacter: Identifiable, Hashable {
    let id: Int      // 0〜33
    let name: String
    let role: CharacterRole
}

struct GameMap: Identifiable, Hashable {
    let id: Int      // 0〜47
    let name: String
    let group: String
}

// MARK: - Master Data

/// ゲーム内マップ・キャラのマスターデータ。
/// IDで戦績データ側から参照することで、行サイズを節約しつつ
/// マップ名やキャラ名の変更にも柔軟に対応できる。
enum MasterData {

    // --- 定義（順番がIDになる） ---

    private static let characterDefs: [(String, CharacterRole)] = [
        // ボマー (8)
        ("シロ", .bomber), ("クロ", .bomber), ("藤崎詩織", .bomber),
        ("グレイ", .bomber), ("シロン", .bomber), ("プラチナ", .bomber),
        ("ダァク", .bomber), ("シロヱ", .bomber),
        // アタッカー (9)
        ("オレン", .attacker), ("ウルシ", .attacker), ("セピア", .attacker),
        ("アサギ", .attacker), ("テッカ", .attacker), ("チグサ", .attacker),
        ("チアモ", .attacker), ("スイスイ", .attacker), ("おはぎ", .attacker),
        // シューター (8)
        ("エメラ", .shooter), ("パプル", .shooter), ("ツガル", .shooter),
        ("パステル", .shooter), ("オリーヴ", .shooter), ("シルヴァ", .shooter),
        ("ブラス", .shooter), ("ミツモトダイア", .shooter),
        // ブロッカー (9)
        ("モモコ", .blocker), ("アクア", .blocker), ("グリムアロエ", .blocker),
        ("パイン", .blocker), ("プルーン", .blocker), ("メロン", .blocker),
        ("ブルーベリー", .blocker), ("ヒイロ", .blocker), ("ロゼ", .blocker)
    ]

    private static let mapDefs: [(String, String)] = [
        // ボムタウン系 (8)
        ("ボムタウン1", "ボムタウン"), ("ボムタウン2.1", "ボムタウン"),
        ("ボムタウン3.2", "ボムタウン"), ("ボムタウン4.1", "ボムタウン"),
        ("ボムタウン5.1", "ボムタウン"), ("ボムタウン6 レインボー", "ボムタウン"),
        ("ボムタウン7", "ボムタウン"), ("ボムタウン8", "ボムタウン"),
        // パニックアイランド系 (7)
        ("パニックアイランド1.1", "パニックアイランド"),
        ("パニックアイランド2.2", "パニックアイランド"),
        ("パニックアイランド3", "パニックアイランド"),
        ("パニックアイランド4", "パニックアイランド"),
        ("パニックアイランド5.2", "パニックアイランド"),
        ("パニックアイランド6", "パニックアイランド"),
        ("パニックアイランド 岩礁", "パニックアイランド"),
        // カラクリ城系 (6)
        ("カラクリ城1", "カラクリ城"), ("カラクリ城2.1", "カラクリ城"),
        ("カラクリ城3", "カラクリ城"), ("カラクリ城4.1", "カラクリ城"),
        ("カラクリ城 黄昏1.1", "カラクリ城"), ("カラクリ城 黎明", "カラクリ城"),
        // ヒエールビレッジ系 (5)
        ("ヒエールビレッジ1", "ヒエールビレッジ"),
        ("ヒエールビレッジ2", "ヒエールビレッジ"),
        ("ヒエールビレッジ 雪解", "ヒエールビレッジ"),
        ("ヒエールビレッジ 雪灯り", "ヒエールビレッジ"),
        ("ヒエールビレッジ 冬茜", "ヒエールビレッジ"),
        // ボム砂漠系 (3)
        ("ボム砂漠1", "ボム砂漠"), ("ボム砂漠2", "ボム砂漠"), ("ボム砂漠3", "ボム砂漠"),
        // ボム火山系 (3)
        ("ボム火山1", "ボム火山"), ("ボム火山2", "ボム火山"), ("ボム火山3", "ボム火山"),
        // サイバースペース系 (6)
        ("サイバースペース1.1", "サイバースペース"),
        ("サイバースペース2", "サイバースペース"),
        ("サイバースペース3.1", "サイバースペース"),
        ("サイバースペース4.1", "サイバースペース"),
        ("サイバースペース5", "サイバースペース"),
        ("サイバースペース ヘキサ", "サイバースペース"),
        // 聖邪の遺跡系 (4)
        ("聖邪の遺跡1.2", "聖邪の遺跡"), ("聖邪の遺跡2.1", "聖邪の遺跡"),
        ("聖邪の遺跡3", "聖邪の遺跡"), ("聖邪の遺跡 哀愁", "聖邪の遺跡"),
        // アクアブルー城系 (6)
        ("アクアブルー城1.1", "アクアブルー城"),
        ("アクアブルー城2", "アクアブルー城"), ("アクアブルー城3", "アクアブルー城"),
        ("アクアブルー城4", "アクアブルー城"), ("アクアブルー城5.1", "アクアブルー城"),
        ("アクアブルー城6", "アクアブルー城")
    ]

    // --- 公開API ---

    static let characters: [GameCharacter] = characterDefs.enumerated().map { i, pair in
        GameCharacter(id: i, name: pair.0, role: pair.1)
    }

    static let maps: [GameMap] = mapDefs.enumerated().map { i, pair in
        GameMap(id: i, name: pair.0, group: pair.1)
    }

    // O(1) 検索用キャッシュ
    private static let charactersById:   [Int: GameCharacter] =
        Dictionary(uniqueKeysWithValues: characters.map { ($0.id, $0) })
    private static let mapsById:         [Int: GameMap] =
        Dictionary(uniqueKeysWithValues: maps.map       { ($0.id, $0) })
    private static let charactersByName: [String: GameCharacter] =
        Dictionary(uniqueKeysWithValues: characters.map { ($0.name, $0) })
    private static let mapsByName:       [String: GameMap] =
        Dictionary(uniqueKeysWithValues: maps.map       { ($0.name, $0) })

    static func character(byId id: Int) -> GameCharacter?     { charactersById[id] }
    static func map(byId id: Int) -> GameMap?                 { mapsById[id] }
    static func character(byName name: String) -> GameCharacter? { charactersByName[name] }
    static func map(byName name: String) -> GameMap?             { mapsByName[name] }

    /// マップグループの登場順
    static func mapGroups() -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for m in maps where !seen.contains(m.group) {
            seen.insert(m.group)
            order.append(m.group)
        }
        return order
    }
}
