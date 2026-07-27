import Foundation
import SwiftData

enum AppTheme: Int, Codable, CaseIterable, Identifiable {
    case light = 0
    case dark  = 1

    var id: Int { rawValue }
    var label: String { self == .light ? "ライト" : "ダーク" }
}

@Model
final class PlayerInfo {
    var name: String         = "ボンバーガール"
    var comment: String      = "よろしくお願いします"
    var themeRaw: Int        = 0
    var favoriteMap1Id: Int  = -1
    var favoriteMap2Id: Int  = -1
    var favoriteMap3Id: Int  = -1
    var favoriteChar1Id: Int = -1
    var favoriteChar2Id: Int = -1
    var favoriteChar3Id: Int = -1
    var favoriteChar4Id: Int = -1
    var lastModified: Date   = Date()

    /// ランク（クラス）記録を使うか（個人で任意）
    var rankTrackingEnabled: Bool = false
    /// 現在のランク（`PlayerRank.rawValue`）。-1 = 未設定。昇格・降格で上下する。
    var currentRankRaw: Int = -1

    init() {}

    // MARK: - Computed

    var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .light }
        set {
            themeRaw = newValue.rawValue
            lastModified = Date()
        }
    }

    /// 現在のランク。未設定なら nil。
    var currentRank: PlayerRank? {
        get { currentRankRaw >= 0 ? PlayerRank(rawValue: currentRankRaw) : nil }
        set {
            currentRankRaw = newValue?.rawValue ?? -1
            lastModified = Date()
        }
    }

    /// ランクを設定／変更する（昇格・降格の両方。上下自由）。
    /// 以降に記録する試合へ反映される（過去の記録は変更しない）。
    func setRank(to rank: PlayerRank) {
        currentRankRaw = rank.rawValue
        lastModified = Date()
    }

    var favoriteMapIds: [Int] {
        get { [favoriteMap1Id, favoriteMap2Id, favoriteMap3Id] }
        set {
            let p = (newValue + Array(repeating: -1, count: 3)).prefix(3).map { $0 }
            favoriteMap1Id = p[0]
            favoriteMap2Id = p[1]
            favoriteMap3Id = p[2]
            lastModified = Date()
        }
    }

    var favoriteCharIds: [Int] {
        get { [favoriteChar1Id, favoriteChar2Id, favoriteChar3Id, favoriteChar4Id] }
        set {
            let p = (newValue + Array(repeating: -1, count: 4)).prefix(4).map { $0 }
            favoriteChar1Id = p[0]
            favoriteChar2Id = p[1]
            favoriteChar3Id = p[2]
            favoriteChar4Id = p[3]
            lastModified = Date()
        }
    }

    var favoriteMapNames: [String] {
        favoriteMapIds.map { MasterData.map(byId: $0)?.name ?? "" }
    }
}

// MARK: - ModelContext

@MainActor
extension ModelContext {
    func ensurePlayerInfo() -> PlayerInfo {
        let descriptor = FetchDescriptor<PlayerInfo>(
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
        )
        if let existing = (try? fetch(descriptor))?.first {
            return existing
        }
        let new = PlayerInfo()
        insert(new)
        try? save()
        return new
    }
}
