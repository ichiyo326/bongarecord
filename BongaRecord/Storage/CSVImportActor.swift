import Foundation
import SwiftData
import os

// MARK: - CSV取込 専用ModelActor
//
// 「引継ぎデータ取込」は全戦績を削除→CSV由来の全レコードをinsertし直す
// 置換方式。件数が多いとMainActor上でfor-loop insertするとUIが固まってしまう
// （読み取り側`computeStats`をModelActorプールで並列化したのと対になる、
// 書き込み側の重い処理）。
//
// 並列化ではなく、MainActorから切り離した1つのバックグラウンドactorに
// 処理を丸ごと逃がし、`batchSize`件ごとに区切ってinsert→saveすることで
// 「1回のトランザクションで全件を抱え続ける」コストを抑える。進捗は
// `AsyncThrowingStream`でMainActor側へ随時通知する。
@ModelActor
actor CSVImportActor {

    /// 取り込みを開始し、`batchSize`件処理するたびに「ここまでの件数」を
    /// ストリームへ流す。全件終わったら`finish()`、エラー時は
    /// `finish(throwing:)`される。
    func importAll(
        _ drafts: [CSVManager.ImportedBattleDraft],
        rankStampRaw: Int,
        batchSize: Int = 500
    ) -> AsyncThrowingStream<Int, Error> {
        let (stream, continuation) = AsyncThrowingStream<Int, Error>.makeStream()

        Task {
            do {
                try await self.performImport(drafts,
                                              rankStampRaw: rankStampRaw,
                                              batchSize: batchSize,
                                              continuation: continuation)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        return stream
    }

    private func performImport(
        _ drafts: [CSVManager.ImportedBattleDraft],
        rankStampRaw: Int,
        batchSize: Int,
        continuation: AsyncThrowingStream<Int, Error>.Continuation
    ) throws {
        do {
            // 既存戦績を全削除（取り込みは置換方式）
            try modelContext.delete(model: BattleRecord.self)

            var count = 0
            for draft in drafts {
                let record = BattleRecord(date: draft.date,
                                           mapId: draft.mapId,
                                           characterId: draft.characterId,
                                           result: draft.result)
                record.rankRaw = rankStampRaw
                modelContext.insert(record)
                count += 1

                // batchSize件ごとに区切ってsaveすることで、1回のsaveが
                // 抱えるオブジェクト数を抑える（メモリ・コミットコストの平準化）。
                if count.isMultiple(of: batchSize) {
                    try modelContext.save()
                    continuation.yield(count)
                }
            }
            try modelContext.save()
            continuation.yield(count)
        } catch {
            // 途中まで進んだ変更を、このactor専用contextの範囲でロールバックする。
            modelContext.rollback()
            throw error
        }
    }
}
