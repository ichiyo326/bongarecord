import Foundation
import Combine
import UserNotifications

/// 末尾通知のスケジューリングを管理
final class MatsubiNotificationManager: ObservableObject {
    static let shared = MatsubiNotificationManager()

    @Published var scheduledCount: Int = 0
    @Published var isAuthorized: Bool = false

    private let idPrefix = "matsubi-"

    private init() { checkAuthorization() }

    // MARK: - 権限

    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    func requestPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    self.isAuthorized = granted
                    completion(granted)
                }
            }
    }

    // MARK: - 末尾 → 対象分の計算

    /// 末尾値(0‑9, 12)から、1時間中の対象「分」を返す
    ///  - 0〜9 : 下1桁一致（例: 0 → 00,10,20,30,40,50）
    ///  - 12   : 12分間隔（0, 12, 24, 36, 48）
    func matchingMinutes(for values: Set<Int>) -> [Int] {
        var mins: Set<Int> = []
        for v in values {
            if v <= 9 {
                // 下1桁一致（例: 0 → 00,10,20,30,40,50）
                for m in 0..<60 where m % 10 == v { mins.insert(m) }
            } else if v == 12 {
                // 12分間隔（0, 12, 24, 36, 48）
                for m in stride(from: 0, to: 60, by: 12) { mins.insert(m) }
            }
        }
        return mins.sorted()
    }

    /// 指定条件での通知件数を事前計算（64上限チェック用）
    func previewCount(
        matsubiValues: Set<Int>,
        startHour: Int, startMinute: Int,
        endHour: Int, endMinute: Int
    ) -> Int {
        let mins = matchingMinutes(for: matsubiValues)
        let startVal = startHour * 60 + startMinute
        let endVal   = endHour * 60 + endMinute
        var count = 0
        for h in 0..<24 {
            for m in mins {
                let tv = h * 60 + m
                if tv >= startVal && tv <= endVal { count += 1 }
            }
        }
        return count
    }

    // MARK: - スケジュール

    func scheduleNotifications(
        matsubiValues: Set<Int>,
        startHour: Int, startMinute: Int,
        endHour: Int, endMinute: Int,
        secondsBefore: Int,
        completion: @escaping (Int) -> Void
    ) {
        let center = UNUserNotificationCenter.current()

        // まず既存の末尾通知IDを全パターン生成して同期的に削除
        var allPossibleIds: [String] = []
        for h in 0..<24 {
            for m in 0..<60 {
                allPossibleIds.append("\(idPrefix)\(h)-\(m)")
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: allPossibleIds)

        // 少し待ってから追加（削除の処理完了を確保）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let mins = self.matchingMinutes(for: matsubiValues)
            let cal  = Calendar.current
            let now  = Date()
            let today = cal.startOfDay(for: now)

            let startVal = startHour * 60 + startMinute
            let endVal   = endHour * 60 + endMinute

            var requests: [UNNotificationRequest] = []

            for hour in 0..<24 {
                for minute in mins {
                    let tv = hour * 60 + minute
                    guard tv >= startVal, tv <= endVal else { continue }

                    guard let target = cal.date(
                        bySettingHour: hour, minute: minute, second: 0, of: today
                    ) else { continue }

                    let notifTime = target.addingTimeInterval(-Double(secondsBefore))
                    guard notifTime > now else { continue }

                    let content = UNMutableNotificationContent()
                    content.title = "末尾通知"
                    content.body  = "\(secondsBefore)秒後に \(String(format: "%02d:%02d", hour, minute)) です"
                    content.sound = .default

                    let comps = cal.dateComponents(
                        [.year, .month, .day, .hour, .minute, .second], from: notifTime
                    )
                    let trigger = UNCalendarNotificationTrigger(
                        dateMatching: comps, repeats: false
                    )

                    let req = UNNotificationRequest(
                        identifier: "\(self.idPrefix)\(hour)-\(minute)",
                        content: content, trigger: trigger
                    )
                    requests.append(req)

                    if requests.count >= 60 { break }
                }
                if requests.count >= 60 { break }
            }

            for r in requests { center.add(r) }

            DispatchQueue.main.async {
                self.scheduledCount = requests.count
                completion(requests.count)
            }
        }
    }

    // MARK: - クリア

    func clearNotifications() {
        var allPossibleIds: [String] = []
        for h in 0..<24 {
            for m in 0..<60 {
                allPossibleIds.append("\(idPrefix)\(h)-\(m)")
            }
        }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: allPossibleIds)
        scheduledCount = 0
    }

    /// 現在のスケジュール件数を更新
    func refreshCount() {
        UNUserNotificationCenter.current()
            .getPendingNotificationRequests { reqs in
                let c = reqs.filter { $0.identifier.hasPrefix(self.idPrefix) }.count
                DispatchQueue.main.async { self.scheduledCount = c }
            }
    }
}
