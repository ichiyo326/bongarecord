import ActivityKit
import Foundation

// MARK: - ライブアクティビティの型定義
//
// このファイルはアプリ本体とWidget Extension（ロック画面／Dynamic Islandの見た目を
// 描画する側）の「両方」から参照する必要がある。そのため、Widget Extensionを
// 追加したあとは、Xcodeのファイルインスペクタで本ファイルの
// 「Target Membership」に、アプリ本体に加えてWidget Extensionのターゲットにも
// チェックを入れること（詳細は同梱のセットアップ手順.md を参照）。
public struct BongaRecordActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var wins: Int
        public var losses: Int
        public var draws: Int
        public var winRate: Double
        public var streakCount: Int
        /// "win" / "lose" / "none"
        public var streakType: String
        public var updatedAt: Date

        public init(wins: Int, losses: Int, draws: Int, winRate: Double,
                    streakCount: Int, streakType: String, updatedAt: Date) {
            self.wins = wins
            self.losses = losses
            self.draws = draws
            self.winRate = winRate
            self.streakCount = streakCount
            self.streakType = streakType
            self.updatedAt = updatedAt
        }
    }

    /// このライブアクティビティを開始した日時（今日の集計の起点表示などに使える）
    public var startDate: Date

    public init(startDate: Date) {
        self.startDate = startDate
    }
}
