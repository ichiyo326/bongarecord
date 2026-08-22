import XCTest
import SwiftData
@testable import BongaRecord_Project

/// `GetBattleSummaryTool.call()`が正しい`BattleQuery`を組み立て、
/// `BattleAnalyticsService`の結果をそのまま返却文字列へ反映しているかを検証する。
/// LLM（Foundation Models）は一切介さない — 指示書23章「ToolとSwiftDataを密結合させない」
/// の狙いどおり、Tool単体でテストできることの確認。
final class GetBattleSummaryToolTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([BattleRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func testCall_FiltersByCharacterNameAndReturnsFormattedSummary() async throws {
        let context = try makeContext()
        // セピア(characterId: 10, attacker) 2勝1敗
        context.insert(BattleRecord(mapId: 0, characterId: 10, result: .win))
        context.insert(BattleRecord(mapId: 0, characterId: 10, result: .win))
        context.insert(BattleRecord(mapId: 0, characterId: 10, result: .lose))
        // 無関係キャラ(シロ, 0) は含まれないことを確認するためのノイズデータ
        context.insert(BattleRecord(mapId: 0, characterId: 0, result: .win))
        try context.save()

        let tool = GetBattleSummaryTool(analytics: BattleAnalyticsService(context: context))
        let text = try await tool.call(arguments: .init(
            period: "all", character: "セピア", role: "", stage: ""
        ))

        XCTAssertTrue(text.contains("試合数: 3"))
        XCTAssertTrue(text.contains("勝利: 2"))
        XCTAssertTrue(text.contains("敗北: 1"))
    }

    func testCall_UnknownCharacterNameFallsBackToNoFilter() async throws {
        let context = try makeContext()
        context.insert(BattleRecord(mapId: 0, characterId: 10, result: .win))
        context.insert(BattleRecord(mapId: 0, characterId: 0, result: .lose))
        try context.save()

        let tool = GetBattleSummaryTool(analytics: BattleAnalyticsService(context: context))
        // 存在しないキャラ名 → MasterDataで解決できずcharacterIdはnilのまま(=全件対象)。
        // LLMが幻覚で存在しないキャラ名を渡してきても、静かに無視して集計自体は破綻させない。
        let text = try await tool.call(arguments: .init(
            period: "all", character: "存在しないキャラ", role: "", stage: ""
        ))

        XCTAssertTrue(text.contains("試合数: 2"))
    }

    func testCall_NoMatchesReturnsZeroWithoutThrowing() async throws {
        let context = try makeContext()
        let tool = GetBattleSummaryTool(analytics: BattleAnalyticsService(context: context))

        let text = try await tool.call(arguments: .init(
            period: "today", character: "", role: "", stage: ""
        ))

        XCTAssertTrue(text.contains("試合数: 0"))
    }
}
