import Foundation
import SwiftData

/// 戦績集計のFacade（指示書 5〜6章）。
///
/// - `AI/Tools/*`（Phase 3で追加予定）はこの型だけを呼び出し、
///   `ModelContext`や`BattleRecord`を直接扱わない。
/// - 集計ロジックは`BattleStatsView`にすでに存在するものと整合させてあるが、
///   このFacade自体はSwiftUIに依存しないため、View外（Tool・Widget・単体テスト）
///   からも同一の結果を再現できる。
/// - Phase 2以降、`FoundationModels`をimportするのはこのFacadeを呼び出す
///   AI Tool層のみとし、ここには持ち込まない（LLM ProviderからのFacade独立性、指示書 30章）。
struct BattleAnalyticsService {
    let context: ModelContext

    // MARK: - summary / comparePeriods

    func summary(query: BattleQuery) throws -> BattleStatistics {
        let records = try AnalyticsRepository.fetchRecords(context: context, query: query)
        return .aggregate(records)
    }

    func compare(periodA: BattleQuery, periodB: BattleQuery) throws -> PeriodComparison {
        PeriodComparison(periodA: try summary(query: periodA),
                          periodB: try summary(query: periodB))
    }

    // MARK: - getCharacterStats

    /// - Parameters:
    ///   - minimumMatches: これ未満の試合数のキャラは結果から除外する（既定1＝除外なし）。
    ///   - limit: 上位N件に絞る（nilなら全件）。
    ///   - sortByWinRateDescending: 勝率降順（true）/昇順（false）。
    func characterStats(
        query: BattleQuery,
        minimumMatches: Int = 1,
        limit: Int? = nil,
        sortByWinRateDescending: Bool = true
    ) throws -> [CharacterStat] {
        let records = try AnalyticsRepository.fetchRecords(context: context, query: query)
        var byCharacter: [Int: [BattleRecord]] = [:]
        for r in records { byCharacter[r.characterId, default: []].append(r) }

        var stats: [CharacterStat] = byCharacter.compactMap { characterId, recs in
            guard let character = MasterData.character(byId: characterId) else { return nil }
            let stat = BattleStatistics.aggregate(recs)
            guard stat.totalMatches >= minimumMatches else { return nil }
            return CharacterStat(characterId: characterId, name: character.name,
                                  role: character.role, statistics: stat)
        }

        stats.sort {
            sortByWinRateDescending ? $0.statistics.winRate > $1.statistics.winRate
                                     : $0.statistics.winRate < $1.statistics.winRate
        }
        if let limit { stats = Array(stats.prefix(limit)) }
        return stats
    }

    // MARK: - getRoleStats

    func roleStats(query: BattleQuery) throws -> [RoleStat] {
        let records = try AnalyticsRepository.fetchRecords(context: context, query: query)
        var byRole: [CharacterRole: [BattleRecord]] = [:]
        for r in records {
            guard let role = MasterData.character(byId: r.characterId)?.role else { continue }
            byRole[role, default: []].append(r)
        }
        return CharacterRole.allCases.compactMap { role in
            guard let recs = byRole[role], !recs.isEmpty else { return nil }
            return RoleStat(role: role, statistics: .aggregate(recs))
        }
    }

    // MARK: - getStageStats

    /// - Parameters:
    ///   - minimumMatches: 「1戦しかしていないステージを苦手と断定する」問題を避けるための下限（指示書 7章）。既定3。
    ///   - sortByWinRateDescending: 既定は昇順（苦手ステージ探し = 勝率が低い順に見たいケースが多いため）。
    func stageStats(
        query: BattleQuery,
        minimumMatches: Int = 3,
        limit: Int? = nil,
        sortByWinRateDescending: Bool = false
    ) throws -> [StageStat] {
        let records = try AnalyticsRepository.fetchRecords(context: context, query: query)
        var byMap: [Int: [BattleRecord]] = [:]
        for r in records { byMap[r.mapId, default: []].append(r) }

        var stats: [StageStat] = byMap.compactMap { mapId, recs in
            guard let map = MasterData.map(byId: mapId) else { return nil }
            let stat = BattleStatistics.aggregate(recs)
            guard stat.totalMatches >= minimumMatches else { return nil }
            return StageStat(mapId: mapId, name: map.name, group: map.group, statistics: stat)
        }

        stats.sort {
            sortByWinRateDescending ? $0.statistics.winRate > $1.statistics.winRate
                                     : $0.statistics.winRate < $1.statistics.winRate
        }
        if let limit { stats = Array(stats.prefix(limit)) }
        return stats
    }
}
