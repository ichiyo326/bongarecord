import Foundation
import SwiftData
import os

// MARK: - キャラ練度集計 専用ModelActor

/// `BattleRecord`から特定キャラの試合数・勝利数を数える、MainActorから
/// 切り離された背景actor。
///
/// **なぜ`@ModelActor`か**:
/// `ModelContext`はスレッドセーフではなく、特定の実行コンテキストに
/// 紐づく前提で設計されている。`@ModelActor`マクロは「このactor専用の
/// `ModelContext`」を自動生成し、そのcontextへのアクセスをこのactorの
/// シリアル実行キューだけに限定してくれる。これにより「MainActorとは
/// 別の場所で、安全にSwiftDataを触る」ことが可能になる。
///
/// **重要な注意点(1個だけでは並列にならない)**:
/// actorはその性質上、内部の処理を「同時に1つずつ」しか実行しない。
/// つまりこのactorのインスタンスを1個だけ用意して33キャラ分の呼び出しを
/// 投げても、MainActorからは解放されるが、集計自体は直列のまま。
/// 本当の並列化には`ProficiencyCalculatorPool`のように複数インスタンスを
/// 用意し、キャラをグループに分けて振り分ける必要がある。
@ModelActor
actor ProficiencyCalculator {

    struct CharacterStat: Sendable {
        let charId: Int
        let games: Int
        let wins: Int
    }

    /// 単一キャラの試合数・勝利数を数える。
    func stat(for charId: Int) throws -> CharacterStat {
        let totalDesc = FetchDescriptor<BattleRecord>(
            predicate: #Predicate { $0.characterId == charId }
        )
        let games = try modelContext.fetchCount(totalDesc)

        let winsDesc = FetchDescriptor<BattleRecord>(
            predicate: #Predicate { $0.characterId == charId && $0.resultRaw == 0 }
        )
        let wins = try modelContext.fetchCount(winsDesc)

        return CharacterStat(charId: charId, games: games, wins: wins)
    }

    /// 渡された複数キャラを「このactor内で」直列に集計する。
    /// プール側から、あらかじめ分割されたサブグループを渡される想定。
    func stats(for charIds: [Int]) throws -> [CharacterStat] {
        try charIds.map { try stat(for: $0) }
    }
}

// MARK: - 複数ModelActorで本当の並列読み取りを行うプール

/// `ProficiencyCalculator`を複数インスタンス持ち、33キャラを
/// グループ分けして本当の意味で並列にfetchCountを実行する。
///
/// **なぜプールなのか**:
/// SQLite(WALモード)は複数の読み取りトランザクションを同時に捌ける。
/// だがそれを活かすには「独立したModelContextを複数、同時に動かす」
/// 必要がある。プールはその独立したcontext群(=actor群)を保持する役割。
enum ProficiencyCalculatorPool {

    private static let log = OSLog(subsystem: "com.yourname.BongaRecord", category: "Proficiency")

    /// - Parameters:
    ///   - container: アプリ全体で共有している`ModelContainer`
    ///   - charIds: 集計対象のキャラID一覧(全キャラ)
    ///   - poolSize: 同時に並列実行するactor数(≒同時読み取り数)
    static func computeAll(
        container: ModelContainer,
        charIds: [Int],
        poolSize: Int = 4
    ) async throws -> [ProficiencyCalculator.CharacterStat] {

        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "ProficiencyCompute", signpostID: signpostID)
        defer { os_signpost(.end, log: log, name: "ProficiencyCompute", signpostID: signpostID) }

        let clampedPoolSize = max(1, min(poolSize, charIds.count))
        let groups = split(charIds, into: clampedPoolSize)

        return try await withThrowingTaskGroup(of: [ProficiencyCalculator.CharacterStat].self) { group in
            for chunk in groups {
                // グループごとに独立したModelActorを1つ生成する。
                // これが「並列に動ける実行単位」の実体。
                group.addTask {
                    let calculator = ProficiencyCalculator(modelContainer: container)
                    return try await calculator.stats(for: chunk)
                }
            }

            var merged: [ProficiencyCalculator.CharacterStat] = []
            merged.reserveCapacity(charIds.count)
            for try await partial in group {
                merged.append(contentsOf: partial)
            }
            return merged
        }
    }

    /// charIdsをpoolSize個のグループにできるだけ均等に分割する。
    private static func split(_ ids: [Int], into groupCount: Int) -> [[Int]] {
        guard groupCount > 1 else { return [ids] }
        var groups: [[Int]] = Array(repeating: [], count: groupCount)
        for (index, id) in ids.enumerated() {
            groups[index % groupCount].append(id)
        }
        return groups.filter { !$0.isEmpty }
    }
}
