import Foundation
import SwiftData

// MARK: - Result Enum（Int rawValue：1バイト相当でストレージ節約）

enum BattleResult: Int, Codable, CaseIterable, Identifiable, Hashable {
    case win  = 0
    case lose = 1
    case draw = 2

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .win:  return "勝利"
        case .lose: return "敗北"
        case .draw: return "引分け"
        }
    }
}

// MARK: - Battle Record（SwiftData @Model）

/// 1試合分の戦績データ。
///
/// **コンパクト設計の意図**:
/// 100万行保持を想定しているため、文字列ではなくマスターデータへのID参照を使う。
/// 1行あたりおよそ30〜40バイト（メタデータ込み）に収まる見込み。
///
/// **CloudKit互換性**:
/// - 全プロパティにデフォルト値を持たせる（CloudKitの要件）
/// - `@Attribute(.unique)` は使わない（CloudKit非対応）
/// - 内部IDは SwiftData が自動採番する `persistentModelID` を使う
@Model
final class BattleRecord {
    /// 試合日時の UNIXタイムスタンプ（秒単位）
    /// Int64で持つことで `#Predicate` での範囲比較が高速・型安全
    var dateTimestamp: Int64 = 0

    /// `MasterData.maps` のID（0〜47）
    var mapId: Int = 0

    /// `MasterData.characters` のID（0〜33）
    var characterId: Int = 0

    /// `BattleResult.rawValue`（0=勝利, 1=敗北, 2=引分け）
    var resultRaw: Int = 0

    /// 記録時点の実ランク（`PlayerRank.rawValue`）。
    /// -1 = ランク未記録（ランク機能オフ時 or 設定前）。
    var rankRaw: Int = -1

    init(date: Date = Date(),
         mapId: Int,
         characterId: Int,
         result: BattleResult,
         rank: PlayerRank? = nil) {
        self.dateTimestamp = Int64(date.timeIntervalSince1970)
        self.mapId         = mapId
        self.characterId   = characterId
        self.resultRaw     = result.rawValue
        self.rankRaw       = rank?.rawValue ?? -1
    }

    // MARK: - 表示用 Computed Properties

    var date: Date {
        get { Date(timeIntervalSince1970: TimeInterval(dateTimestamp)) }
        set { dateTimestamp = Int64(newValue.timeIntervalSince1970) }
    }

    var map: GameMap?        { MasterData.map(byId: mapId) }
    var character: GameCharacter? { MasterData.character(byId: characterId) }
    var result: BattleResult { BattleResult(rawValue: resultRaw) ?? .draw }

    /// 記録時点の実ランク。未記録なら nil。
    var rank: PlayerRank? { rankRaw >= 0 ? PlayerRank(rawValue: rankRaw) : nil }

    var mapName: String       { map?.name ?? "不明" }
    var characterName: String { character?.name ?? "不明" }
}
