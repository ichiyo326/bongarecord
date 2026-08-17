import XCTest
import SwiftData
@testable import BongaRecord_Project

/// 候補C(SingleFetchAggregator: 1回のfetch + Swift側集計)を、
/// これまでのLegacy(直列fetchCount)・Pool(ModelActor並列)と
/// 三者比較する。
final class SingleFetchAggregatorTests: XCTestCase {

    // MARK: - 正しさの検証

    /// 3方式すべてが同じ結果を返すことを確認する。
    func testUnit_AllThreeMethodsAgree() async throws {
        let container = try PerformanceTestSupport.makeSeededContainer(
            recordCount: 3000, characterCount: 34
        )
        let charIds = Array(0..<34)

        let legacyContext = ModelContext(container)
        let legacy = try LegacyProficiencyCalculator.computeAll(context: legacyContext, charIds: charIds)

        let pool = try await ProficiencyCalculatorPool.computeAll(
            container: container, charIds: charIds, poolSize: 4
        )
        let poolByChar = Dictionary(uniqueKeysWithValues: pool.map { ($0.charId, ($0.games, $0.wins)) })

        let singleFetchContext = ModelContext(container)
        let candidateC = try SingleFetchAggregator.computeAll(context: singleFetchContext, charIds: charIds)

        for charId in charIds {
            let l = legacy[charId] ?? (0, 0)
            let p = poolByChar[charId] ?? (0, 0)
            let c = candidateC[charId] ?? .init()

            XCTAssertEqual(l.games, p.0, "charId \(charId): Legacy/Pool games不一致")
            XCTAssertEqual(l.games, c.games, "charId \(charId): Legacy/候補C games不一致")
            XCTAssertEqual(l.wins, p.1, "charId \(charId): Legacy/Pool wins不一致")
            XCTAssertEqual(l.wins, c.wins, "charId \(charId): Legacy/候補C wins不一致")
        }
    }

    // MARK: - データ規模別 三者比較(in-memory)

    func testIntegration_ThreeWayComparison_1k() async throws {
        try await runThreeWayComparison(recordCount: 1_000, label: "1,000件")
    }

    func testIntegration_ThreeWayComparison_50k() async throws {
        try await runThreeWayComparison(recordCount: 50_000, label: "50,000件")
    }

    func testIntegration_ThreeWayComparison_500k() async throws {
        try await runThreeWayComparison(recordCount: 500_000, label: "500,000件")
    }

    /// 候補Cが本当に不利になるかを見るための大規模データ(200万件)。
    /// 「クエリ回数を減らす」戦略が、オブジェクト実体化コストの増大で
    /// 逆転するポイントがあるかを確認する。
    func testIntegration_ThreeWayComparison_2M_StressTest() async throws {
        try await runThreeWayComparison(recordCount: 2_000_000, label: "2,000,000件", iterations: 2)
    }

    // MARK: - 実ディスクI/O条件での三者比較

    func testIntegration_ThreeWayComparison_DiskBacked_300k() async throws {
        let (container, storeURL) = try PerformanceTestSupport.makeDiskBackedContainer(
            recordCount: 300_000, characterCount: 34
        )
        defer { PerformanceTestSupport.cleanupDiskBackedStore(at: storeURL) }

        let charIds = Array(0..<34)
        let legacyContext = ModelContext(container)
        let singleFetchContext = ModelContext(container)

        try await PerformanceTestSupport.benchmark(label: "Legacy/ディスク上300,000件", iterations: 3) {
            _ = try LegacyProficiencyCalculator.computeAll(context: legacyContext, charIds: charIds)
        }

        let pool = PersistentProficiencyPool(container: container, poolSize: 4)
        try await PerformanceTestSupport.benchmark(label: "Pool(4)/ディスク上300,000件", iterations: 3) {
            _ = try await pool.computeAll(charIds: charIds)
        }

        try await PerformanceTestSupport.benchmark(label: "候補C/ディスク上300,000件", iterations: 3) {
            _ = try SingleFetchAggregator.computeAll(context: singleFetchContext, charIds: charIds)
        }
    }

    // MARK: - 共通処理

    private func runThreeWayComparison(
        recordCount: Int,
        label: String,
        iterations: Int = 3
    ) async throws {
        let container = try PerformanceTestSupport.makeSeededContainer(
            recordCount: recordCount, characterCount: 34
        )
        let charIds = Array(0..<34)
        let legacyContext = ModelContext(container)
        let singleFetchContext = ModelContext(container)

        try await PerformanceTestSupport.benchmark(label: "Legacy/\(label)", iterations: iterations) {
            _ = try LegacyProficiencyCalculator.computeAll(context: legacyContext, charIds: charIds)
        }

        let pool = PersistentProficiencyPool(container: container, poolSize: 4)
        try await PerformanceTestSupport.benchmark(label: "Pool(4)/\(label)", iterations: iterations) {
            _ = try await pool.computeAll(charIds: charIds)
        }

        try await PerformanceTestSupport.benchmark(label: "候補C(単発fetch)/\(label)", iterations: iterations) {
            _ = try SingleFetchAggregator.computeAll(context: singleFetchContext, charIds: charIds)
        }
    }
}
