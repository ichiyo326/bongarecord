import XCTest
import SwiftData
@testable import BongaRecord_Project

final class ProficiencyPerformanceTests: XCTestCase {

    // MARK: - 単体テスト: 正しさの検証

    /// パフォーマンス比較の前提として、新旧の実装が「同じ結果」を返すことを
    /// 保証する。ここが崩れていたら速度比較そのものに意味がなくなる。
    func testUnit_ParallelResultMatchesLegacy() async throws {
        let container = try PerformanceTestSupport.makeSeededContainer(
            recordCount: 3000,
            characterCount: 34
        )
        let charIds = Array(0..<34)

        let legacyContext = ModelContext(container)
        let legacy = try LegacyProficiencyCalculator.computeAll(
            context: legacyContext,
            charIds: charIds
        )

        let parallel = try await ProficiencyCalculatorPool.computeAll(
            container: container,
            charIds: charIds,
            poolSize: 4
        )
        let parallelByChar = Dictionary(
            uniqueKeysWithValues: parallel.map { ($0.charId, ($0.games, $0.wins)) }
        )

        for charId in charIds {
            let legacyStat = legacy[charId] ?? (0, 0)
            let parallelStat = parallelByChar[charId] ?? (0, 0)
            XCTAssertEqual(
                legacyStat.games, parallelStat.0,
                "charId \(charId) の試合数が新旧で一致しない"
            )
            XCTAssertEqual(
                legacyStat.wins, parallelStat.1,
                "charId \(charId) の勝利数が新旧で一致しない"
            )
        }
    }

    /// 極小規模(1キャラだけ)での単体テスト。ModelActor経由の
    /// actor-hopオーバーヘッドが、直列版に対してどれだけ乗るかを見る。
    /// データ量が少ないほどオーバーヘッドが結果を支配しやすい、という
    /// 「並列化は万能ではない」ことを確認するためのテスト。
    func testUnit_SingleCharacter_OverheadComparison() async throws {
        let container = try PerformanceTestSupport.makeSeededContainer(
            recordCount: 200,
            characterCount: 34
        )
        let legacyContext = ModelContext(container)

        let (legacyAvg, _, _) = try await PerformanceTestSupport.benchmark(
            label: "Legacy/1キャラ/200件",
            iterations: 10
        ) {
            _ = try LegacyProficiencyCalculator.computeAll(context: legacyContext, charIds: [0])
        }

        let (poolAvg, _, _) = try await PerformanceTestSupport.benchmark(
            label: "Pool/1キャラ/200件",
            iterations: 10
        ) {
            _ = try await ProficiencyCalculatorPool.computeAll(
                container: container, charIds: [0], poolSize: 4
            )
        }

        print("[Unit] 1キャラ比較: legacy=\(legacyAvg)ms pool=\(poolAvg)ms (poolの方が遅くて正常。actor切替コストが支配的なため)")
        // ここではアサーションで速度を強制しない。
        // 「小規模だとプール版が負ける」ことを可視化するのが目的。
    }

    // MARK: - 複合テスト: 実運用規模でのシリアル vs 並列

    func testIntegration_SmallDataset_1kRecords() async throws {
        try await runComparison(recordCount: 1_000, label: "1,000件")
    }

    func testIntegration_MediumDataset_50kRecords() async throws {
        try await runComparison(recordCount: 50_000, label: "50,000件")
    }

    func testIntegration_LargeDataset_500kRecords() async throws {
        // READMEが想定している「100万行」に近い、現実的な負荷テスト規模
        try await runComparison(recordCount: 500_000, label: "500,000件")
    }

    /// poolSizeを1→2→4→8と変えたときのスケーリング傾向を見る複合テスト。
    /// 「並列数を増やせば増やすほど速くなるわけではない」ことを実測で確認する。
    func testIntegration_PoolSizeScaling() async throws {
        let container = try PerformanceTestSupport.makeSeededContainer(
            recordCount: 200_000,
            characterCount: 34
        )
        let charIds = Array(0..<34)

        for poolSize in [1, 2, 4, 8, 16] {
            try await PerformanceTestSupport.benchmark(
                label: "Pool(size=\(poolSize))/200,000件",
                iterations: 3
            ) {
                _ = try await ProficiencyCalculatorPool.computeAll(
                    container: container, charIds: charIds, poolSize: poolSize
                )
            }
        }
    }

    // MARK: - 共通処理

    private func runComparison(recordCount: Int, label: String) async throws {
        let container = try PerformanceTestSupport.makeSeededContainer(
            recordCount: recordCount,
            characterCount: 34
        )
        let charIds = Array(0..<34)
        let legacyContext = ModelContext(container)

        try await PerformanceTestSupport.benchmark(
            label: "Legacy/\(label)",
            iterations: 3
        ) {
            _ = try LegacyProficiencyCalculator.computeAll(
                context: legacyContext, charIds: charIds
            )
        }

        try await PerformanceTestSupport.benchmark(
            label: "Pool(size=4)/\(label)",
            iterations: 3
        ) {
            _ = try await ProficiencyCalculatorPool.computeAll(
                container: container, charIds: charIds, poolSize: 4
            )
        }
    }
}
