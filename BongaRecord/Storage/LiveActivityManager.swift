import Foundation
import Combine
import ActivityKit

// MARK: - ロック画面／Dynamic Islandのライブアクティビティ管理
//
// 配信中かどうかに関わらず、「今日 〇勝〇敗」を常に見られるようにする機能。
// ライブアクティビティの見た目（ロック画面／Dynamic Islandの実際の描画）は
// Widget Extensionという別ターゲット側のコードが担当するため、このクラスは
// 「今日の集計を計算してActivityKitに渡す」役割に専念する。
///
/// **重要**: Widget Extensionをまだ追加していない場合、`Activity.request`は
/// 失敗する（あるいは何も表示されない）。同梱のセットアップ手順.mdを参照して
/// Widget Extensionを先に追加すること。
@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    /// ユーザーがこの機能を使うかどうか（設定画面のトグル）
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Key.enabled)
            if !isEnabled {
                end()
            }
        }
    }

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var lastError: String?

    private var activity: Activity<BongaRecordActivityAttributes>?

    private enum Key {
        static let enabled = "liveActivity.enabled"
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Key.enabled)
    }

    /// システム側でライブアクティビティが許可されているか
    /// （設定アプリ「Face IDとパスコード」→「ライブアクティビティ」でユーザーがOFFにできる）
    var systemActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// 戦績が変化するたびに呼ぶ。ONのときだけ開始／更新する。
    func update(records: [BattleRecord]) {
        guard isEnabled else { return }
        guard systemActivitiesEnabled else {
            lastError = "システム側でライブアクティビティが無効になっています（設定アプリ→Face IDとパスコード→ライブアクティビティ）"
            return
        }

        let snapshot = BattleStatsSnapshot.today(from: records)
        let state = BongaRecordActivityAttributes.ContentState(
            wins: snapshot.wins,
            losses: snapshot.losses,
            draws: snapshot.draws,
            winRate: snapshot.winRate,
            streakCount: snapshot.streakCount,
            streakType: snapshot.streakType.rawValue,
            updatedAt: Date()
        )

        if let activity {
            Task {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
            return
        }

        do {
            let attributes = BongaRecordActivityAttributes(startDate: Calendar.current.startOfDay(for: Date()))
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil)
            )
            isRunning = true
            lastError = nil
        } catch {
            lastError = "開始できませんでした: \(error.localizedDescription)"
        }
    }

    /// ライブアクティビティを終了する（設定OFF時、または明示的な終了操作時）
    func end() {
        guard let activity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        self.activity = nil
        isRunning = false
    }
}
