import SwiftUI

// MARK: - シェア用の戦績カード（正方形・SNS投稿向け）
//
// `ImageRenderer`でこのViewをそのままラスタライズして画像化する前提のため、
// 固定サイズ（600×600pt）にしている。文字サイズなども固定値で組んでいる。
struct ShareCardView: View {
    let snapshot: BattleStatsSnapshot
    let dateText: String

    static let size: CGFloat = 600

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.20, green: 0.0, blue: 0.55), Color(red: 0.05, green: 0.0, blue: 0.20)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )

            VStack(spacing: 28) {
                Spacer(minLength: 0)

                VStack(spacing: 6) {
                    Text("BONGA RECORD")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .tracking(4)
                    Text(dateText)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.55))
                }

                Text("\(snapshot.wins)勝\(snapshot.losses)敗\(snapshot.draws)分")
                    .font(.system(size: 64, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                HStack(spacing: 24) {
                    statChip(label: "勝率", value: snapshot.totalGames > 0 ? String(format: "%.1f%%", snapshot.winRate) : "-")
                    if !snapshot.streakText.isEmpty {
                        statChip(label: "状況", value: snapshot.streakText,
                                 tint: snapshot.streakType == .win ? Color(red: 0.22, green: 0.81, blue: 0.77)
                                                                    : Color(red: 1.0, green: 0.42, blue: 0.5))
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(40)
        }
        .frame(width: Self.size, height: Self.size)
    }

    private func statChip(label: String, value: String, tint: Color = Color(red: 0.22, green: 0.81, blue: 0.77)) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(tint)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(14)
    }
}

#Preview {
    ShareCardView(
        snapshot: BattleStatsSnapshot(wins: 5, losses: 2, draws: 1, streakCount: 3, streakType: .win),
        dateText: "2026/08/07"
    )
}
