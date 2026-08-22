import Foundation
import Combine
import UserNotifications

// MARK: - 実績・マイルストーン通知
//
// 「通算◯勝達成」「◯連勝達成」のような節目を検知して、その場でローカル通知する。
// 「末尾通知」（MatsubiNotificationManager）とは目的が異なる別機能だが、通知の
// 許可要求まわりはOSの同じ`UNUserNotificationCenter`を使うため、許可済みなら
// どちらの機能を先にONにしても追加のダイアログは出ない。
@MainActor
final class AchievementNotifier: ObservableObject {
    static let shared = AchievementNotifier()

    /// 通算勝利数の節目（達成した瞬間に通知）
    static let totalWinMilestones = [10, 50, 100, 300, 500, 1000, 3000, 5000]
    /// 連勝数の節目
    static let winStreakMilestones = [3, 5, 10, 15, 20, 30, 50]

    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Key.enabled) }
    }
    @Published private(set) var isAuthorized = false

    /// 直近に通知した節目（同じ節目で何度も通知しないためのガード）
    private var lastNotifiedTotalWins: Int {
        get { UserDefaults.standard.integer(forKey: Key.lastTotalWins) }
        set { UserDefaults.standard.set(newValue, forKey: Key.lastTotalWins) }
    }
    private var lastNotifiedStreak: Int {
        get { UserDefaults.standard.integer(forKey: Key.lastStreak) }
        set { UserDefaults.standard.set(newValue, forKey: Key.lastStreak) }
    }

    private enum Key {
        static let enabled       = "achievement.enabled"
        static let lastTotalWins = "achievement.lastTotalWins"
        static let lastStreak    = "achievement.lastStreak"
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Key.enabled)
        checkAuthorization()
    }

    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                Task { @MainActor in
                    self.isAuthorized = granted
                }
            }
    }

    /// 戦績が変化するたびに呼ぶ。新しく節目を超えていれば通知を1件出す。
    /// （複数の節目を一気に飛び越えた場合も、直近の1件だけ通知する＝スパム防止）
    func checkAndNotify(records: [BattleRecord]) {
        guard isEnabled, isAuthorized else { return }

        // 通算勝利数はsince:0で集計した`snapshot.wins`と同じ値なので、
        // 別途`records.filter { ... }.count`で全件を数え直さずsnapshotを使い回す。
        let snapshot = BattleStatsSnapshot.compute(from: records, since: 0)

        let totalWins = snapshot.wins
        if let milestone = Self.totalWinMilestones.last(where: { $0 <= totalWins && $0 > lastNotifiedTotalWins }) {
            notify(title: "実績達成🎉", body: "通算 \(milestone)勝 を達成しました！")
        }
        lastNotifiedTotalWins = totalWins

        if snapshot.streakType == .win {
            if let milestone = Self.winStreakMilestones.last(where: { $0 <= snapshot.streakCount && $0 > lastNotifiedStreak }) {
                notify(title: "連勝記録🔥", body: "\(milestone)連勝 達成中です！")
            }
            lastNotifiedStreak = snapshot.streakCount
        } else {
            // 連勝が途切れたら基準をリセット（次の連勝でまた同じ節目を通知できるように）
            lastNotifiedStreak = 0
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // ほぼ即時（0秒だと登録に失敗することがあるため0.1秒後にしている）
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "achievement-\(UUID().uuidString)",
            content: content, trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }
}
