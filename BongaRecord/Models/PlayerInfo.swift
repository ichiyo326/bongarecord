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

    /// 旧スキーマ（お気に入りキャラ固定4枠）。新しい`favoriteCharIdsRaw`への
    /// 移行専用として残しており、以降は読み書きしない（削除するとCloudKitの
    /// 既存スキーマとの整合が崩れるリスクがあるため、値は残したまま無効化する）。
    var favoriteChar1Id: Int = -1
    var favoriteChar2Id: Int = -1
    var favoriteChar3Id: Int = -1
    var favoriteChar4Id: Int = -1

    /// お気に入りキャラ（可変長）。以前は4枠固定だったが、5人以上も選べるようにするため
    /// 配列で持つ形に変更した。SwiftDataはInt配列をそのまま属性として保存できる。
    var favoriteCharIdsRaw: [Int] = []

    var lastModified: Date   = Date()

    /// ランク（クラス）記録を使うか（個人で任意）
    var rankTrackingEnabled: Bool = false
    /// 現在のランク（`PlayerRank.rawValue`）。-1 = 未設定。昇格・降格で上下する。
    var currentRankRaw: Int = -1

    /// 旧スキーマ（アーケード／コナステの単一選択）。`playsArcade`/`playsKonasute`への
    /// 移行専用として残している。以降は読み書きしない。
    var classTypeRaw: Int = 0

    /// プレイ環境（複数選択可）。アーケードとコナステを両方プレイしている人も
    /// 選べるよう、単一のenumではなく独立した2つのBoolで持つ。
    var playsArcade: Bool   = true
    var playsKonasute: Bool = false

    var rateText: String  = ""
    var goal: String      = ""

    /// 下記2つの移行が実行済みかどうか（それぞれ一度だけ実行すればよい）。
    var classMigratedV2: Bool = false
    var favoriteCharsMigratedV2: Bool = false

    init() {}

    // MARK: - Computed

    var theme: AppTheme {
        get { AppTheme(rawValue: themeRaw) ?? .light }
        set {
            themeRaw = newValue.rawValue
            lastModified = Date()
        }
    }

    /// 「クラス・レート」欄などの表示用。複数選択されていれば「・」区切りで両方出す。
    var playClassLabel: String {
        var parts: [String] = []
        if playsArcade   { parts.append("アーケード") }
        if playsKonasute { parts.append("コナステ") }
        return parts.isEmpty ? "未設定" : parts.joined(separator: "・")
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

    /// お気に入りキャラ（人数の上限なし。-1や重複は保存時に取り除く）。
    var favoriteCharIds: [Int] {
        get { favoriteCharIdsRaw }
        set {
            var seen = Set<Int>()
            favoriteCharIdsRaw = newValue.filter { $0 != -1 && seen.insert($0).inserted }
            lastModified = Date()
        }
    }

    var favoriteMapNames: [String] {
        favoriteMapIds.map { MasterData.map(byId: $0)?.name ?? "" }
    }

    // MARK: - 旧スキーマからの移行

    /// 「クラス単一選択→複数選択」「お気に入りキャラ固定4枠→可変長」の
    /// 一度きりの移行。`ensurePlayerInfo()`から毎回呼ばれるが、フラグが
    /// 立っていれば即returnするので実質無害。
    func migrateLegacyDataIfNeeded() {
        if !classMigratedV2 {
            playsArcade   = (classTypeRaw == 0)
            playsKonasute = (classTypeRaw == 1)
            classMigratedV2 = true
        }
        if !favoriteCharsMigratedV2 {
            if favoriteCharIdsRaw.isEmpty {
                let legacy = [favoriteChar1Id, favoriteChar2Id, favoriteChar3Id, favoriteChar4Id]
                    .filter { $0 != -1 }
                if !legacy.isEmpty {
                    favoriteCharIdsRaw = legacy
                }
            }
            favoriteCharsMigratedV2 = true
        }
    }
}

// MARK: - ModelContext

@MainActor
extension ModelContext {
    func ensurePlayerInfo() -> PlayerInfo {
        let descriptor = FetchDescriptor<PlayerInfo>(
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
        )
        let info: PlayerInfo
        if let existing = (try? fetch(descriptor))?.first {
            info = existing
        } else {
            let new = PlayerInfo()
            insert(new)
            info = new
        }
        info.migrateLegacyDataIfNeeded()
        try? save()
        return info
    }
}
