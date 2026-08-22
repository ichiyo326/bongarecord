#if DEBUG
import Foundation
import SwiftData

/// 開発者向けベンチマーク画面専用の「旧実装(直列forループ)」再現。
///
/// `BongaRecordTests`側にも同じ役割の`LegacyProficiencyCalculator`があるが、
/// あちらは`@testable import`前提でテストターゲット内に閉じている。
/// アプリ本体(この画面)から実機の本物のデータに対して比較したいので、
/// アプリターゲット側にも同じロジックを`#if DEBUG`で隔離した形で置く。
/// Release(App Store配布)ビルドではこのファイルごとコンパイル対象から
/// 除外されるため、リリース版のバイナリには一切含まれない。
enum DeveloperLegacyCalculator {
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

    /// `BattleStatsSnapshot.compute`の旧実装（シングルパス化する前の再現）。
    /// filter→全件sort→勝敗filter×3→streak用ループ、で記録全体を5回なめる。
    static func legacySnapshotCompute(from records: [BattleRecord], since: Int64) -> BattleStatsSnapshot {
        let target = records
            .filter { $0.dateTimestamp >= since }
            .sorted { $0.dateTimestamp > $1.dateTimestamp }

        let wins   = target.filter { $0.result == .win }.count
        let losses = target.filter { $0.result == .lose }.count
        let draws  = target.filter { $0.result == .draw }.count

        var streakCount = 0
        var streakType: BattleStatsSnapshot.StreakType = .none
        if let latest = target.first, latest.result != .draw {
            streakType = (latest.result == .win) ? .win : .lose
            for r in target {
                if r.result.rawValue == latest.result.rawValue {
                    streakCount += 1
                } else {
                    break
                }
            }
        }

        return BattleStatsSnapshot(wins: wins, losses: losses, draws: draws,
                                    streakCount: streakCount, streakType: streakType)
    }

    /// CSV取込の旧実装（MainActorのcontextで同期的に全削除→for文insert→save）。
    /// 引数のcontextは呼び出し側が用意したものをそのまま使う
    /// （計測対象はあくまで「削除・挿入・保存」の時間で、コンテナ生成コストは含めない）。
    static func legacyImport(
        _ drafts: [CSVManager.ImportedBattleDraft],
        rankStampRaw: Int,
        context: ModelContext
    ) throws {
        try context.delete(model: BattleRecord.self)
        for draft in drafts {
            let record = BattleRecord(date: draft.date,
                                       mapId: draft.mapId,
                                       characterId: draft.characterId,
                                       result: draft.result)
            record.rankRaw = rankStampRaw
            context.insert(record)
        }
        try context.save()
    }

    /// ランク一括スタンプの旧実装（MainActorのcontextで全件fetch→forループ→save）。
    static func legacyStampAll(rank: Int, context: ModelContext) throws -> Int {
        let all = try context.fetch(FetchDescriptor<BattleRecord>())
        for r in all { r.rankRaw = rank }
        try context.save()
        return all.count
    }
}
#endif
