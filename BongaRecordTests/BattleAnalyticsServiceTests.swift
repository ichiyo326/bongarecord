import XCTest
import SwiftData
@testable import BongaRecord_Project

/// Phase 1（AI非依存のAnalytics API）の正しさを検証する。
/// この段階では`FoundationModels`はimportしない（指示書 25章 Phase 1）。
final class BattleAnalyticsServiceTests: XCTestCase {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([BattleRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// セピア(characterId: 10, attacker) / シロ(characterId: 0, bomber) を使って
    /// 既知の日付・勝敗パターンでレコードを投入する。
    @discardableResult
    private func seed(_ context: ModelContext) throws -> [BattleRecord] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

        let records: [BattleRecord] = [
            // セピア(10, attacker) 今日: 2勝1敗
            .init(date: day(0), mapId: 0, characterId: 10, result: .win),
            .init(date: day(0), mapId: 0, characterId: 10, result: .win),
            .init(date: day(0), mapId: 0, characterId: 10, result: .lose),
            // セピア(10) 40日前（今月には入らない想定日）: 1勝1敗
            .init(date: day(-40), mapId: 1, characterId: 10, result: .win),
            .init(date: day(-40), mapId: 1, characterId: 10, result: .lose),
            // シロ(0, bomber) 今日: 1勝2敗、マップ1で連敗
            .init(date: day(0), mapId: 1, characterId: 0, result: .win),
            .init(date: day(0), mapId: 1, characterId: 0, result: .lose),
            .init(date: day(0), mapId: 1, characterId: 0, result: .lose),
        ]
        for r in records { context.insert(r) }
        try context.save()
        return records
    }

    // MARK: - summary

    func testSummary_TodayAllCharacters() throws {
        let context = try makeInMemoryContext()
        try seed(context)

        let service = BattleAnalyticsService(context: context)
        let stats = try service.summary(query: BattleQuery(period: .today))

        // 今日の全件: セピア3戦(2勝1敗) + シロ3戦(1勝2敗) = 6戦3勝3敗
        XCTAssertEqual(stats.totalMatches, 6)
        XCTAssertEqual(stats.wins, 3)
        XCTAssertEqual(stats.losses, 3)
        XCTAssertEqual(stats.winRate, 50.0)
    }

    func testSummary_FilteredByCharacter() throws {
        let context = try makeInMemoryContext()
        try seed(context)

        let service = BattleAnalyticsService(context: context)
        // 期間指定なし(.all) + セピア(10)のみ = 全5戦(3勝2敗)
        let stats = try service.summary(query: BattleQuery(period: .all, characterId: 10))

        XCTAssertEqual(stats.totalMatches, 5)
        XCTAssertEqual(stats.wins, 3)
        XCTAssertEqual(stats.losses, 2)
    }

    func testSummary_RecentNIgnoresDateAndUsesCount() throws {
        let context = try makeInMemoryContext()
        try seed(context)

        let service = BattleAnalyticsService(context: context)
        // 直近3戦（新しい順）= 今日のシロ3戦
        let stats = try service.summary(query: BattleQuery(period: .recent(3)))

        XCTAssertEqual(stats.totalMatches, 3)
    }

    // MARK: - comparePeriods

    func testComparePeriods_WinRatePointDifferenceIsComputedInSwift() throws {
        let context = try makeInMemoryContext()
        try seed(context)

        let service = BattleAnalyticsService(context: context)
        let comparison = try service.compare(
            periodA: BattleQuery(period: .today),
            periodB: BattleQuery(period: .all)
        )

        // periodA(今日): 6戦3勝3敗 = 50.0%
        // periodB(全期間): 8戦4勝4敗 = 50.0%
        XCTAssertEqual(comparison.periodA.winRate, 50.0)
        XCTAssertEqual(comparison.periodB.winRate, 50.0)
        XCTAssertEqual(comparison.winRatePointDifference, 0.0)
        XCTAssertEqual(comparison.matchCountDifference, 6 - 8)
    }

    // MARK: - characterStats

    func testCharacterStats_SortedByWinRateDescendingByDefault() throws {
        let context = try makeInMemoryContext()
        try seed(context)

        let service = BattleAnalyticsService(context: context)
        let stats = try service.characterStats(query: BattleQuery(period: .all))

        // セピア: 3勝2敗=60% / シロ: 1勝2敗≒33.3%
        XCTAssertEqual(stats.first?.characterId, 10)
        XCTAssertEqual(stats.first?.name, "セピア")
        XCTAssertGreaterThan(stats[0].statistics.winRate, stats[1].statistics.winRate)
    }

    func testCharacterStats_MinimumMatchesExcludesLowSampleCharacters() throws {
        let context = try makeInMemoryContext()
        try seed(context)

        let service = BattleAnalyticsService(context: context)
        let stats = try service.characterStats(query: BattleQuery(period: .all), minimumMatches: 6)

        // どちらも6戦未満なので除外される
        XCTAssertTrue(stats.isEmpty)
    }

    // MARK: - roleStats

    func testRoleStats_GroupsByRole() throws {
        let context = try makeInMemoryContext()
        try seed(context)

        let service = BattleAnalyticsService(context: context)
        let stats = try service.roleStats(query: BattleQuery(period: .all))

        let attacker = stats.first { $0.role == .attacker }
        let bomber = stats.first { $0.role == .bomber }
        XCTAssertEqual(attacker?.statistics.totalMatches, 5)
        XCTAssertEqual(bomber?.statistics.totalMatches, 3)
    }

    // MARK: - stageStats

    func testStageStats_MinimumMatchesDefaultAvoidsSmallSampleStages() throws {
        let context = try makeInMemoryContext()
        try seed(context)

        let service = BattleAnalyticsService(context: context)
        // mapId 0: セピアの今日2戦のみ -> 既定のminimumMatches(3)未満なので除外される
        let stats = try service.stageStats(query: BattleQuery(period: .all))

        XCTAssertFalse(stats.contains { $0.mapId == 0 })
        // mapId 1: セピア40日前2戦 + シロ今日3戦 = 5戦なので含まれる
        XCTAssertTrue(stats.contains { $0.mapId == 1 })
    }
}
