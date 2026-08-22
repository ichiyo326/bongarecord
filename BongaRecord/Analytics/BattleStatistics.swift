import Foundation

/// 集計済みの戦績（試合数・勝敗数・勝率）。
///
/// 勝率の定義は`BattleStatsSnapshot`と統一する：
/// 分母は「勝ち＋負け」のみ（引分けは除外）、小数第1位までのパーセント。
/// AIに勝率を計算させず、ここで確定させた値だけを返す（指示書 6章・32章）。
struct BattleStatistics: Sendable, Equatable {
    let totalMatches: Int
    let wins: Int
    let losses: Int
    let draws: Int

    var winRate: Double {
        let decisive = wins + losses
        guard decisive > 0 else { return 0 }
        return (Double(wins) / Double(decisive) * 1000).rounded() / 10
    }

    static let empty = BattleStatistics(totalMatches: 0, wins: 0, losses: 0, draws: 0)

    /// `[BattleRecord]`から直接集計する。
    static func aggregate(_ records: [BattleRecord]) -> BattleStatistics {
        var wins = 0, losses = 0, draws = 0
        for r in records {
            switch r.result {
            case .win:  wins += 1
            case .lose: losses += 1
            case .draw: draws += 1
            }
        }
        return BattleStatistics(totalMatches: records.count, wins: wins, losses: losses, draws: draws)
    }
}

/// 2期間の比較結果。差分はSwift側で確定させ、LLMには計算させない（指示書 7章）。
struct PeriodComparison: Sendable, Equatable {
    let periodA: BattleStatistics
    let periodB: BattleStatistics

    /// A の勝率 − B の勝率（ポイント、小数第1位まで）
    var winRatePointDifference: Double {
        ((periodA.winRate - periodB.winRate) * 10).rounded() / 10
    }

    var matchCountDifference: Int {
        periodA.totalMatches - periodB.totalMatches
    }
}

/// キャラクター別集計（`getCharacterStats`用）
struct CharacterStat: Sendable, Equatable, Identifiable {
    var id: Int { characterId }
    let characterId: Int
    let name: String
    let role: CharacterRole
    let statistics: BattleStatistics
}

/// ロール別集計（`getRoleStats`用）
struct RoleStat: Sendable, Equatable, Identifiable {
    var id: Int { role.rawValue }
    let role: CharacterRole
    let statistics: BattleStatistics
}

/// ステージ（マップ）別集計（`getStageStats`用）
struct StageStat: Sendable, Equatable, Identifiable {
    var id: Int { mapId }
    let mapId: Int
    let name: String
    let group: String
    let statistics: BattleStatistics
}
