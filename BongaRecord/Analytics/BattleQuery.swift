import Foundation

/// 戦績検索の共通クエリ条件。
///
/// `BattleStatsView.runSearch()` にあった「日付だけSQLで絞り、
/// マップ/キャラ/ロールはメモリ側で絞る」という既存方針を踏襲する。
/// AI Tool層（Phase 3）はこの型を経由してのみ検索条件を組み立て、
/// SwiftDataの`Predicate`やID型を直接扱わない。
struct BattleQuery: Sendable, Equatable {

    /// 期間の指定方法。
    /// `.recent(n)` だけは日付ではなく「直近N戦」という試合数ベースの絞り込み。
    enum Period: Sendable, Equatable {
        case all
        case today
        case thisWeek
        case thisMonth
        case lastMonth
        case thisYear
        case recent(Int)
        case range(start: Date?, end: Date?)
    }

    var period: Period = .all
    var characterId: Int?
    var roleFilter: CharacterRole?
    var mapId: Int?

    /// `.recent`以外の期間でも件数上限を掛けたい場合に使う（例: 「今月の直近10戦」）。
    /// `.recent(n)`が指定されている場合はそちらが優先される。
    var limit: Int?

    init(period: Period = .all,
         characterId: Int? = nil,
         roleFilter: CharacterRole? = nil,
         mapId: Int? = nil,
         limit: Int? = nil) {
        self.period = period
        self.characterId = characterId
        self.roleFilter = roleFilter
        self.mapId = mapId
        self.limit = limit
    }

    /// AI Toolの`Arguments`（自由文字列）から`Period`へ変換する。
    /// 指示書 7章の`periodType`（例: "today", "thisMonth", "recent30"）に対応。
    /// 未知の文字列は`.all`にフォールバックする（LLMに断定させないための安全側デフォルト）。
    static func period(fromToolString raw: String) -> Period {
        switch raw {
        case "today":                  return .today
        case "thisWeek", "week":       return .thisWeek
        case "thisMonth", "month":     return .thisMonth
        case "lastMonth":              return .lastMonth
        case "thisYear", "year":       return .thisYear
        case "all", "":                return .all
        default:
            if raw.hasPrefix("recent"), let n = Int(raw.dropFirst("recent".count)), n > 0 {
                return .recent(n)
            }
            return .all
        }
    }
}
