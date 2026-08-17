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
}
#endif
