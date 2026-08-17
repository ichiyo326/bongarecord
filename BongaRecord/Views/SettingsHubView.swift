import SwiftUI

// MARK: - 設定（マップ／キャラ管理・引継ぎデータ・ライブアクティビティ・実績通知）

/// トップメニューにあった「マップ／キャラ管理」と「引継ぎデータ作成／取込」に加え、
/// 新機能の「ライブアクティビティ」「実績通知」の入口もここにまとめている。
/// 各遷移先の中身は既存のものと同じで、ここでは入口をまとめるだけに留めている。
struct SettingsHubView: View {
    @State private var showCatalog = false
    @State private var showDataTransfer = false
    @State private var showLiveActivity = false
    @State private var showAchievements = false
    #if DEBUG
    @State private var showDeveloperBenchmark = false
    #endif

    var body: some View {
        ZStack {
            PuzzleBackground()
            ScrollView {
                VStack(spacing: 16) {
                    menuButton("マップ／キャラ管理") { showCatalog = true }
                        .navigationDestination(isPresented: $showCatalog) { CatalogHubView() }

                    menuButton("引継ぎデータ作成／取込") { showDataTransfer = true }
                        .navigationDestination(isPresented: $showDataTransfer) { DataTransferView() }

                    menuButton("ライブアクティビティ") { showLiveActivity = true }
                        .navigationDestination(isPresented: $showLiveActivity) { LiveActivitySettingsView() }

                    menuButton("実績通知") { showAchievements = true }
                        .navigationDestination(isPresented: $showAchievements) { AchievementSettingsView() }

                    #if DEBUG
                    // 開発者専用。#if DEBUGで囲んでいるため、Release(App Store配布)
                    // ビルドではこのボタンごとコンパイル対象から除外され、
                    // ユーザーの手元には一切表示されない。
                    menuButton("🛠️ 開発者ベンチマーク（DEBUG限定）") { showDeveloperBenchmark = true }
                        .navigationDestination(isPresented: $showDeveloperBenchmark) { DeveloperBenchmarkView() }
                    #endif
                }
                .padding()
            }
        }
        .bongaNavigationBar(title: "設定")
    }

    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.bongaOnAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(Color.bongaPurple)
                .cornerRadius(6)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsHubView()
    }
}
