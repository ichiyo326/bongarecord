import Foundation
import SwiftData
@testable import BongaRecord_Project

// MARK: - テスト用データ生成

enum PerformanceTestSupport {

    /// テスト専用のin-memory ModelContainerを作り、指定件数の戦績をキャラに
    /// 均等分配してシードする。
    ///
    /// - Parameters:
    ///   - recordCount: 挿入する`BattleRecord`の総数
    ///   - characterCount: 分配先のキャラ数(実際のロスターサイズに合わせて調整可)
    static func makeSeededContainer(
        recordCount: Int,
        characterCount: Int = 34
    ) throws -> ModelContainer {
        let schema = Schema([
            BattleRecord.self,
            PlayerInfo.self,
            MapPreference.self,
            CharacterPreference.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true // ディスクI/Oを排除し、集計ロジック自体の差だけを見る
        )
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        // 大量insertはバッチで。1件ごとにsave()すると挿入自体が支配的コストになり、
        // 「集計の速度差」を見たいテストの趣旨がぼやけるため。
        let batchSize = 2000
        for i in 0..<recordCount {
            let record = BattleRecord(
                date: Date(),
                mapId: i % 48,
                characterId: i % characterCount,
                result: (i % 3 == 0) ? .win : .lose
            )
            context.insert(record)
            if i % batchSize == 0 {
                try context.save()
            }
        }
        try context.save()

        return container
    }

    /// 非同期処理の実行時間を複数回計測し、平均・最小・最大(ms)を返す。
    /// XCTestの`measure{}`は同期クロージャ専用のため自前で用意している。
    @discardableResult
    static func benchmark(
        label: String,
        iterations: Int = 5,
        _ block: () async throws -> Void
    ) async rethrows -> (avgMs: Double, minMs: Double, maxMs: Double) {
        var samples: [Double] = []
        samples.reserveCapacity(iterations)

        for _ in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            try await block()
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            samples.append(elapsedMs)
        }

        let avg = samples.reduce(0, +) / Double(samples.count)
        let minV = samples.min() ?? 0
        let maxV = samples.max() ?? 0

        print(String(
            format: "[Benchmark] %@: avg=%.1fms min=%.1fms max=%.1fms (n=%d)",
            label, avg, minV, maxV, iterations
        ))

        return (avg, minV, maxV)
    }
}

// MARK: - 旧実装(直列forループ)の再現

/// `ProfileView`の元の実装を、テストで比較できる形に切り出したもの。
/// 本体側は既にModelActorプール版に置き換わっているため、
/// 性能比較の基準点としてここに残しておく。
enum LegacyProficiencyCalculator {

    static func computeAll(
        context: ModelContext,
        charIds: [Int]
    ) throws -> [Int: (games: Int, wins: Int)] {
        var result: [Int: (games: Int, wins: Int)] = [:]

        for charId in charIds {
            let totalDesc = FetchDescriptor<BattleRecord>(
                predicate: #Predicate { $0.characterId == charId }
            )
            let games = try context.fetchCount(totalDesc)

            let winsDesc = FetchDescriptor<BattleRecord>(
                predicate: #Predicate { $0.characterId == charId && $0.resultRaw == 0 }
            )
            let wins = try context.fetchCount(winsDesc)

            result[charId] = (games, wins)
        }

        return result
    }
}
