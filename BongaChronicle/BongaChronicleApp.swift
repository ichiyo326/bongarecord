import SwiftUI
import SwiftData
import UserNotifications

// フォアグラウンドでも通知バナーを表示するためのDelegate
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

@main
struct BongaChronicleApp: App {
    let modelContainer: ModelContainer
    private let notificationDelegate = NotificationDelegate()

    init() {
        // 通知Delegateを設定
        UNUserNotificationCenter.current().delegate = notificationDelegate

        do {
            let schema = Schema([
                BattleRecord.self,
                PlayerInfo.self,
                MapPreference.self,
                CharacterPreference.self
            ])
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            modelContainer = try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("ModelContainer の初期化に失敗: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // アプリ全体でDynamic Typeの上限を .large までに固定。
                // これがないと「文字を拡大」設定を上げるだけで各画面のレイアウトが
                // 個別に壊れていき、そのたびに画面ごとの対症療法（minimumScaleFactor等）が
                // 必要になってしまう。ここで一括して上限を設けることで、
                // 各Viewは「最大 .large まで来ることを前提にレイアウトすればよい」状態になる。
                .dynamicTypeSize(...DynamicTypeSize.large)
        }
        .modelContainer(modelContainer)
    }
}
