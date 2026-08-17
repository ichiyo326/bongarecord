import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - ライブアクティビティの見た目（Widget Extensionターゲット用）
//
// このファイルは「アプリ本体」ではなく、新しく追加する「Widget Extension」ターゲットに
// 追加するファイルです。追加手順は同梱の「ライブアクティビティ_セットアップ手順.md」を
// 参照してください。`BongaRecordActivityAttributes.swift`（アプリ本体にある）を、
// このターゲットからも参照できるようTarget Membershipにチェックを入れる必要があります。

struct BongaRecordWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BongaRecordActivityAttributes.self) { context in
            // ロック画面／通知センターでの見た目
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("BONGA RECORD")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.purple)
                        Text("\(context.state.wins)勝\(context.state.losses)敗\(context.state.draws)分")
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(winRateText(context.state))
                            .font(.headline)
                            .foregroundColor(.teal)
                        if !streakText(context.state).isEmpty {
                            Text(streakText(context.state))
                                .font(.caption2)
                                .foregroundColor(streakColor(context.state))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
                }
            } compactLeading: {
                Text("\(context.state.wins)W")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.purple)
            } compactTrailing: {
                Text("\(context.state.losses)L")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.pink)
            } minimal: {
                Text("\(context.state.wins)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.purple)
            }
        }
    }
}

// MARK: - ロック画面用ビュー

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<BongaRecordActivityAttributes>

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("BONGA RECORD")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.purple.opacity(0.9))
                Text("\(context.state.wins)勝 \(context.state.losses)敗 \(context.state.draws)分")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(winRateText(context.state))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.teal)
                if !streakText(context.state).isEmpty {
                    Text(streakText(context.state))
                        .font(.caption)
                        .foregroundColor(streakColor(context.state))
                }
            }
        }
        .padding(16)
    }
}

// MARK: - 共通の表示ヘルパー

private func winRateText(_ state: BongaRecordActivityAttributes.ContentState) -> String {
    (state.wins + state.losses) > 0 ? "勝率 \(state.winRate)%" : "-"
}

private func streakText(_ state: BongaRecordActivityAttributes.ContentState) -> String {
    switch state.streakType {
    case "win":  return "\(state.streakCount)連勝中"
    case "lose": return "\(state.streakCount)連敗中"
    default:     return ""
    }
}

private func streakColor(_ state: BongaRecordActivityAttributes.ContentState) -> Color {
    state.streakType == "win" ? .teal : .pink
}
