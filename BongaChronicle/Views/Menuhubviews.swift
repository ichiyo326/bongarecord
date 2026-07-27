import SwiftUI

/// メニュー集約用の共通ラッパー。
///
/// 既存の各画面（登録/修正・マップ/キャラ管理・プロフィール/編集）は一切変更せず、
/// 上部にセグメントコントロールを足して1画面に束ねる。
/// 各子ビューは自前で `.bongaNavigationBar` を持つため、ナビタイトルは選択中のタブに追従する。
private struct SegmentedHub<First: View, Second: View>: View {
    let firstLabel: String
    let secondLabel: String
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    @State private var showSecond = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $showSecond) {
                Text(firstLabel).tag(false)
                Text(secondLabel).tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
            // Pickerの当たり判定が下のコンテンツ（特にList）より確実に手前に来るようにする。
            .zIndex(1)

            // 下のマップ／キャラ管理・修正画面はSwiftUIの`List`（UIKit橋渡し）を使っており、
            // ここでのタブ切り替え（=ビューの丸ごと差し替え）に暗黙のアニメーションがかかると、
            // Listの内部トランジションと競合してタップ後に表示が切り替わらない／数秒固まる
            // ことがあるSwiftUIの既知の挙動があるため、明示的にアニメーションを切っておく。
            Group {
                if showSecond {
                    second()
                } else {
                    first()
                }
            }
            .animation(nil, value: showSecond)
            .transaction { $0.disablesAnimations = true }
        }
    }
}

// MARK: - 戦績登録／修正

struct RecordHubView: View {
    var body: some View {
        SegmentedHub(firstLabel: "登録", secondLabel: "修正") {
            BattleRegistrationView()
        } second: {
            BattleEditView()
        }
    }
}

// MARK: - マップ／キャラ管理

struct CatalogHubView: View {
    var body: some View {
        SegmentedHub(firstLabel: "マップ", secondLabel: "キャラ") {
            MapManagementView()
        } second: {
            CharacterManagementView()
        }
    }
}

// MARK: - プロフィール（表示／編集）

struct ProfileHubView: View {
    var body: some View {
        SegmentedHub(firstLabel: "表示", secondLabel: "編集") {
            ProfileView()
        } second: {
            PlayerInfoEditView()
        }
    }
}
