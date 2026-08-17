import Foundation

// MARK: - 集計スナップショット（共通ロジック）
//
// 「勝敗数・勝率・直近の連勝連敗」は配信連携（OBS）・ライブアクティビティ・
// 戦績シェア画像・実績通知のすべてで必要になるため、ここに1箇所にまとめている。
// `StreamOverlaySync`は配信セッション単位、こちらは主に「今日」単位で使う想定だが、
// `since`に任意のUNIXタイムスタンプを渡せるので用途を問わず使える。
struct BattleStatsSnapshot {
    var wins: Int
    var losses: Int
    var draws: Int

    /// 勝率（%）。分母は勝ち＋負けのみ（引分けは除く）。試合数0なら0。
    var winRate: Double {
        let decisive = wins + losses
        guard decisive > 0 else { return 0 }
        return (Double(wins) / Double(decisive) * 1000).rounded() / 10
    }

    var totalGames: Int { wins + losses + draws }

    enum StreakType: String {
        case win, lose, none
    }

    var streakCount: Int
    var streakType: StreakType

    /// 「3連勝中」「2連敗中」のような短い表示用テキスト（連勝連敗が無ければ空文字）
    var streakText: String {
        switch streakType {
        case .win:  return "\(streakCount)連勝中"
        case .lose: return "\(streakCount)連敗中"
        case .none: return ""
        }
    }

    /// `records`から`since`（UNIXタイムスタンプ秒）以降の分だけを集計する。
    /// `records`は順不同で渡してよい（内部で新しい順に並べ替える）。
    static func compute(from records: [BattleRecord], since: Int64) -> BattleStatsSnapshot {
        let target = records
            .filter { $0.dateTimestamp >= since }
            .sorted { $0.dateTimestamp > $1.dateTimestamp }

        let wins   = target.filter { $0.result == .win }.count
        let losses = target.filter { $0.result == .lose }.count
        let draws  = target.filter { $0.result == .draw }.count

        var streakCount = 0
        var streakType: StreakType = .none
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

    /// 今日（端末のローカルカレンダーの0時）以降を集計する、よく使う形のショートカット。
    static func today(from records: [BattleRecord]) -> BattleStatsSnapshot {
        let startOfToday = Int64(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)
        return compute(from: records, since: startOfToday)
    }
}
