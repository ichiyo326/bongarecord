import Foundation
import SwiftData

// MARK: - カスタムID採番ルール
//
// MasterData のデフォルトID … マップ 0〜47 / キャラ 0〜33
// ユーザー追加分は衝突しないよう 10000 以降を採番する。

enum CatalogID {
    static let customBase = 10000
}

// MARK: - マップのユーザー設定（並び順・非表示・追加分）

@Model
final class MapPreference {
    // CloudKit対応のため全プロパティにデフォルト値が必要
    var mapId: Int = 0          // 対応する GameMap.id（カスタムは10000+）
    var sortOrder: Int = 0      // 表示順（小さいほど上）
    var isHidden: Bool = false  // 非表示フラグ
    var isCustom: Bool = false  // ユーザー追加か
    var customName: String = "" // 追加分の名前
    var customGroup: String = ""// 追加分のグループ

    init(mapId: Int = 0,
         sortOrder: Int = 0,
         isHidden: Bool = false,
         isCustom: Bool = false,
         customName: String = "",
         customGroup: String = "") {
        self.mapId = mapId
        self.sortOrder = sortOrder
        self.isHidden = isHidden
        self.isCustom = isCustom
        self.customName = customName
        self.customGroup = customGroup
    }
}

// MARK: - キャラのユーザー設定

@Model
final class CharacterPreference {
    var characterId: Int = 0
    var sortOrder: Int = 0
    var isHidden: Bool = false
    var isCustom: Bool = false
    var customName: String = ""
    var customRoleRaw: Int = 0   // CharacterRole.rawValue

    init(characterId: Int = 0,
         sortOrder: Int = 0,
         isHidden: Bool = false,
         isCustom: Bool = false,
         customName: String = "",
         customRoleRaw: Int = 0) {
        self.characterId = characterId
        self.sortOrder = sortOrder
        self.isHidden = isHidden
        self.isCustom = isCustom
        self.customName = customName
        self.customRoleRaw = customRoleRaw
    }
}

// MARK: - 表示用の統一型（デフォルト or カスタムを問わず扱える）

struct DisplayMap: Identifiable, Hashable {
    let id: Int
    let name: String
    let group: String
    var isHidden: Bool
    var isCustom: Bool
}

struct DisplayCharacter: Identifiable, Hashable {
    let id: Int
    let name: String
    let role: CharacterRole
    var isHidden: Bool
    var isCustom: Bool
}

// MARK: - 解決ロジック（MasterData + Preference を合成）

enum Catalog {

    /// 表示すべきマップ一覧を返す。
    /// - デフォルトマップ＋カスタム追加分を合成
    /// - sortOrder の昇順、未設定（=Preferenceなし）は元の並び順を維持
    /// - includeHidden=false なら非表示を除外
    static func resolvedMaps(prefs: [MapPreference],
                             includeHidden: Bool = false) -> [DisplayMap] {
        var prefById: [Int: MapPreference] = [:]
        for p in prefs { prefById[p.mapId] = p }

        var result: [DisplayMap] = []

        // 1) デフォルトマップ
        for (index, m) in MasterData.maps.enumerated() {
            let p = prefById[m.id]
            result.append(DisplayMap(
                id: m.id,
                name: m.name,
                group: m.group,
                isHidden: p?.isHidden ?? false,
                isCustom: false
            ))
            // sortOrder 用に元indexを保持（後で安定ソート）
            _ = index
        }

        // 2) カスタム追加マップ
        for p in prefs where p.isCustom {
            result.append(DisplayMap(
                id: p.mapId,
                name: p.customName.isEmpty ? "（無名マップ）" : p.customName,
                group: p.customGroup.isEmpty ? "カスタム" : p.customGroup,
                isHidden: p.isHidden,
                isCustom: true
            ))
        }

        // 3) 並び替え：Preference に sortOrder があればそれを優先、
        //    なければデフォルト並び（id順 + カスタムは末尾）
        result.sort { lhs, rhs in
            let lo = prefById[lhs.id]?.sortOrder ?? defaultOrder(forMapId: lhs.id)
            let ro = prefById[rhs.id]?.sortOrder ?? defaultOrder(forMapId: rhs.id)
            if lo != ro { return lo < ro }
            return lhs.id < rhs.id
        }

        return includeHidden ? result : result.filter { !$0.isHidden }
    }

    /// 表示すべきキャラ一覧を返す。
    static func resolvedCharacters(prefs: [CharacterPreference],
                                   includeHidden: Bool = false) -> [DisplayCharacter] {
        var prefById: [Int: CharacterPreference] = [:]
        for p in prefs { prefById[p.characterId] = p }

        var result: [DisplayCharacter] = []

        for c in MasterData.characters {
            let p = prefById[c.id]
            result.append(DisplayCharacter(
                id: c.id,
                name: c.name,
                role: c.role,
                isHidden: p?.isHidden ?? false,
                isCustom: false
            ))
        }

        for p in prefs where p.isCustom {
            let role = CharacterRole(rawValue: p.customRoleRaw) ?? .bomber
            result.append(DisplayCharacter(
                id: p.characterId,
                name: p.customName.isEmpty ? "（無名キャラ）" : p.customName,
                role: role,
                isHidden: p.isHidden,
                isCustom: true
            ))
        }

        result.sort { lhs, rhs in
            let lo = prefById[lhs.id]?.sortOrder ?? defaultOrder(forCharId: lhs.id)
            let ro = prefById[rhs.id]?.sortOrder ?? defaultOrder(forCharId: rhs.id)
            if lo != ro { return lo < ro }
            return lhs.id < rhs.id
        }

        return includeHidden ? result : result.filter { !$0.isHidden }
    }

    /// 表示マップのグループ登場順（解決後リストから算出）
    static func resolvedMapGroups(_ maps: [DisplayMap]) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for m in maps where !seen.contains(m.group) {
            seen.insert(m.group)
            order.append(m.group)
        }
        return order
    }

    // MARK: - デフォルト並び順（Preference未設定時のフォールバック）

    private static func defaultOrder(forMapId id: Int) -> Int {
        id >= CatalogID.customBase ? 100000 + id : id
    }
    private static func defaultOrder(forCharId id: Int) -> Int {
        id >= CatalogID.customBase ? 100000 + id : id
    }

    // MARK: - 次のカスタムIDを採番

    static func nextCustomMapId(existing prefs: [MapPreference]) -> Int {
        let maxId = prefs.filter { $0.isCustom }.map { $0.mapId }.max() ?? (CatalogID.customBase - 1)
        return max(maxId + 1, CatalogID.customBase)
    }
    static func nextCustomCharId(existing prefs: [CharacterPreference]) -> Int {
        let maxId = prefs.filter { $0.isCustom }.map { $0.characterId }.max() ?? (CatalogID.customBase - 1)
        return max(maxId + 1, CatalogID.customBase)
    }

    // MARK: - 名前解決（戦績表示などでカスタム名も引けるように）

    static func mapName(byId id: Int, prefs: [MapPreference]) -> String? {
        if let m = MasterData.map(byId: id) { return m.name }
        if let p = prefs.first(where: { $0.isCustom && $0.mapId == id }) {
            return p.customName.isEmpty ? "（無名マップ）" : p.customName
        }
        return nil
    }
    static func charName(byId id: Int, prefs: [CharacterPreference]) -> String? {
        if let c = MasterData.character(byId: id) { return c.name }
        if let p = prefs.first(where: { $0.isCustom && $0.characterId == id }) {
            return p.customName.isEmpty ? "（無名キャラ）" : p.customName
        }
        return nil
    }
}
