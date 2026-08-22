import XCTest
import SwiftData
@testable import BongaRecord_Project

/// `GetStageStatsTool.call()`が、実在するマップ名だけを返し、
/// minimumMatches未満のステージを除外することを検証する。
final class GetStageStatsToolTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([BattleRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func testCall_ExcludesStagesBelowMinimumMatches() async throws {
        let context = try makeContext()
        // mapId 0（ボムタウン1）: 1戦のみ → 既定のminimumMatches(3)未満なので除外されるはず
        context.insert(BattleRecord(mapId: 0, characterId: 0, result: .win))
        // mapId 1（ボムタウン2.1）: 4戦（1勝3敗）→ 含まれるはず
        context.insert(BattleRecord(mapId: 1, characterId: 0, result: .win))
        context.insert(BattleRecord(mapId: 1, characterId: 0, result: .lose))
        context.insert(BattleRecord(mapId: 1, characterId: 0, result: .lose))
        context.insert(BattleRecord(mapId: 1, characterId: 0, result: .lose))
        try context.save()

        let tool = GetStageStatsTool(analytics: BattleAnalyticsService(context: context))
        let text = try await tool.call(arguments: .init(
            period: "all", character: "", role: "",
            minimumMatches: 0, // 0以下は既定値3にフォールバックする実装
            limit: 0,          // 0以下は既定値5にフォールバックする実装
            sortByWinRateDescending: false
        ))

        XCTAssertTrue(text.contains(MasterData.map(byId: 1)!.name))
        XCTAssertFalse(text.contains(MasterData.map(byId: 0)!.name))
    }

    func testCall_NoQualifyingStagesReturnsExplicitMessage() async throws {
        let context = try makeContext()
        let tool = GetStageStatsTool(analytics: BattleAnalyticsService(context: context))

        let text = try await tool.call(arguments: .init(
            period: "all", character: "", role: "",
            minimumMatches: 3, limit: 5, sortByWinRateDescending: false
        ))

        // データが無いことを断定せずに伝えるメッセージであること
        XCTAssertTrue(text.contains("条件に合うステージがありません"))
    }

    func testCall_SortAscendingPutsLowestWinRateFirst() async throws {
        let context = try makeContext()
        // mapId 0: 3戦全敗(勝率0%)
        for _ in 0..<3 { context.insert(BattleRecord(mapId: 0, characterId: 0, result: .lose)) }
        // mapId 1: 3戦全勝(勝率100%)
        for _ in 0..<3 { context.insert(BattleRecord(mapId: 1, characterId: 0, result: .win)) }
        try context.save()

        let tool = GetStageStatsTool(analytics: BattleAnalyticsService(context: context))
        let text = try await tool.call(arguments: .init(
            period: "all", character: "", role: "",
            minimumMatches: 3, limit: 5, sortByWinRateDescending: false
        ))

        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "\(MasterData.map(byId: 0)!.name): 3戦 0勝3敗 勝率0.0%")
    }
}
