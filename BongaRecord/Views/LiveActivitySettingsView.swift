import SwiftUI

// MARK: - ライブアクティビティ設定画面

/// ロック画面／Dynamic Islandに「今日 〇勝〇敗」を常時表示する機能のON/OFFと、
/// Widget Extensionの追加が必要である旨の案内を行う画面。
struct LiveActivitySettingsView: View {
    @ObservedObject private var manager = LiveActivityManager.shared

    var body: some View {
        ZStack {
            PuzzleBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    SectionLabel(text: "この機能について")
                        .padding(.horizontal).padding(.top, 8)
                    FormCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("配信中でなくても、ロック画面やDynamic Islandに「今日の勝敗数」を常に表示できます。")
                                .font(.caption)
                            Text("⚠️ 表示側（ロック画面の見た目）はWidget ExtensionというXcodeの別ターゲットで作る必要があり、これはこのアプリのコードだけでは自動化できません。「ライブアクティビティ_セットアップ手順.md」を見ながら一度だけXcodeで追加してください。追加が済んでいない状態でONにしても、内部的な開始処理は走りますが画面には何も表示されません。")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    SectionLabel(text: "設定")
                        .padding(.horizontal).padding(.top, 12)
                    FormCard {
                        Toggle("今日の戦績を常時表示する", isOn: $manager.isEnabled)
                    }

                    SectionLabel(text: "状態")
                        .padding(.horizontal).padding(.top, 12)
                    FormCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(manager.isRunning ? Color.green : Color.gray)
                                    .frame(width: 10, height: 10)
                                Text(manager.isRunning ? "表示中" : "停止中")
                                    .font(.subheadline)
                            }
                            Text(manager.systemActivitiesEnabled
                                 ? "システム側のライブアクティビティ設定: 有効"
                                 : "システム側のライブアクティビティ設定: 無効（設定アプリ→Face IDとパスコード→ライブアクティビティ をご確認ください）")
                                .font(.caption2)
                                .foregroundColor(manager.systemActivitiesEnabled ? .secondary : .red)
                            if let error = manager.lastError {
                                Text("⚠️ \(error)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .bongaNavigationBar(title: "ライブアクティビティ")
    }
}

#Preview {
    NavigationStack {
        LiveActivitySettingsView()
    }
}
