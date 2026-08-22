import Foundation
import SwiftData

/// `BattleQuery`を実際の`ModelContext`検索へ変換する層。
///
/// SwiftDataへの直接依存はここに閉じ込める。AI Tool（Phase 3）や
/// `BattleAnalyticsService`はこの型を経由してのみレコードを取得し、
/// `ModelContext`や`#Predicate`を直接扱わない（指示書 6章）。
///
/// `BattleStatsView.runSearch()`と同じ方針：日付範囲だけSQLの`#Predicate`で絞り、
/// キャラ/ロール/マップはメモリ側でフィルタする（フィルタ後は少件数の前提）。
enum AnalyticsRepository {

    nonisolated static func fetchRecords(
        context: ModelContext,
        query: BattleQuery
    ) throws -> [BattleRecord] {
        let (startTs, endTs) = dateRange(for: query.period)

        let predicate: Predicate<BattleRecord> = #Predicate { r in
            r.dateTimestamp >= startTs && r.dateTimestamp < endTs
        }
        let descriptor = FetchDescriptor<BattleRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.dateTimestamp, order: .reverse)]
        )
        var matched = try context.fetch(descriptor)

        if let cid = query.characterId {
            matched = matched.filter { $0.characterId == cid }
        }
        if let role = query.roleFilter {
            matched = matched.filter { MasterData.character(byId: $0.characterId)?.role == role }
        }
        if let mid = query.mapId {
            matched = matched.filter { $0.mapId == mid }
        }

        switch query.period {
        case .recent(let n):
            matched = Array(matched.prefix(n))
        default:
            if let limit = query.limit {
                matched = Array(matched.prefix(limit))
            }
        }

        return matched
    }

    /// `Period`を`[startTs, endTs)`のUNIXタイムスタンプ範囲へ変換する。
    /// `.recent`は日付ではなく件数で絞るため、ここでは無制限範囲を返す。
    private static func dateRange(for period: BattleQuery.Period) -> (Int64, Int64) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today

        switch period {
        case .all, .recent:
            return (.min, .max)

        case .today:
            return (Int64(today.timeIntervalSince1970), Int64(tomorrow.timeIntervalSince1970))

        case .thisWeek:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
            let start = cal.date(from: comps) ?? today
            return (Int64(start.timeIntervalSince1970), Int64(tomorrow.timeIntervalSince1970))

        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: today)
            let start = cal.date(from: comps) ?? today
            return (Int64(start.timeIntervalSince1970), Int64(tomorrow.timeIntervalSince1970))

        case .lastMonth:
            let comps = cal.dateComponents([.year, .month], from: today)
            guard let thisMonthStart = cal.date(from: comps),
                  let lastMonthStart = cal.date(byAdding: .month, value: -1, to: thisMonthStart) else {
                return (.min, .max)
            }
            return (Int64(lastMonthStart.timeIntervalSince1970), Int64(thisMonthStart.timeIntervalSince1970))

        case .thisYear:
            let comps = cal.dateComponents([.year], from: today)
            let start = cal.date(from: comps) ?? today
            return (Int64(start.timeIntervalSince1970), Int64(tomorrow.timeIntervalSince1970))

        case .range(let s, let e):
            let start: Int64 = s.map { Int64(cal.startOfDay(for: $0).timeIntervalSince1970) } ?? .min
            let end: Int64
            if let e {
                let next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: e)) ?? e
                end = Int64(next.timeIntervalSince1970)
            } else {
                end = .max
            }
            return (start, end)
        }
    }
}
