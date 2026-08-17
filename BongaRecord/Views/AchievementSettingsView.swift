import SwiftUI

// MARK: - 実績・マイルストーン通知の設定画面

struct AchievementSettingsView: View {
    @ObservedObject private var notifier = AchievementNotifier.shared

    var body: some View {
        ZStack {
            PuzzleBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    SectionLabel(text: "この機能について")
                        .padding(.horizontal).padding(.top, 8)
                    FormCard {
                        Text("通算勝利数や連勝数が節目に達したとき、その場で通知します。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    SectionLabel(text: "設定")
                        .padding(.horizontal).padding(.top, 12)
                    FormCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("実績通知を受け取る", isOn: $notifier.isEnabled)
                            if notifier.isEnabled && !notifier.isAuthorized {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("通知の許可がまだありません。")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                    Button("通知を許可する") {
                                        notifier.requestPermission()
                                    }
                                    .font(.caption.weight(.semibold))
                                }
                            }
                        }
                    }

                    SectionLabel(text: "通算勝利数の節目")
                        .padding(.horizontal).padding(.top, 12)
                    FormCard {
                        Text(AchievementNotifier.totalWinMilestones.map { "\($0)" }.joined(separator: " ・ "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    SectionLabel(text: "連勝数の節目")
                        .padding(.horizontal).padding(.top, 12)
                    FormCard {
                        Text(AchievementNotifier.winStreakMilestones.map { "\($0)" }.joined(separator: " ・ "))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .bongaNavigationBar(title: "実績通知")
        .onAppear {
            notifier.checkAuthorization()
        }
    }
}

#Preview {
    NavigationStack {
        AchievementSettingsView()
    }
}
