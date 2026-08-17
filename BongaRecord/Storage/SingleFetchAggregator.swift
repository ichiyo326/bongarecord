import Foundation
import SwiftData

/// 候補C: 68回の`fetchCount`クエリではなく、`BattleRecord`を1回だけ
/// 全件fetchして、Swift側の辞書集計で試合数・勝利数を求める方式。
///
/// **狙い**: クエリの往復回数(68回→1回)を減らす。
///
/// **トレードオフ**: `fetchCount`はSQL側の`COUNT(*)`だけで完結し、
/// SwiftDataのモデルオブジェクトを1つも生成しない軽い操作。対して
/// `fetch()`は行ごとにモデルオブジェクトを実体化するコストがかかる。
/// つまりクエリ往復は減らせるが、代わりに「大量のオブジェクト生成」という
/// 別のコストを背負う。データ件数が多いほどこのコストが効いてくるため、
/// 「クエリ回数を減らせば必ず速くなる」とは限らない。実測での検証が必要。
enum SingleFetchAggregator {

    nonisolated struct AggregateResult {
        var games: Int = 0
        var wins: Int = 0
    }

    /// アプリターゲットはデフォルトでMainActor隔離が有効なため、明示的に
    /// `nonisolated`を付けてMainActor外(バックグラウンドコンテキストや
    /// テストのベンチマーク実行)からも呼べるようにしている。
    nonisolated static func computeAll(
        context: ModelContext,
        charIds: [Int]
    ) throws -> [Int: AggregateResult] {
        let descriptor = FetchDescriptor<BattleRecord>()
        let allRecords = try context.fetch(descriptor)

        var result: [Int: AggregateResult] = [:]
        for id in charIds {
            result[id] = AggregateResult()
        }

        for record in allRecords {
            // charIds に含まれないキャラ(既に削除された等)のレコードは無視。
            guard result[record.characterId] != nil else { continue }
            result[record.characterId]!.games += 1
            if record.resultRaw == 0 {
                result[record.characterId]!.wins += 1
            }
        }

        return result
    }
}
