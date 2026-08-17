import SwiftUI
import SwiftData

// MARK: - 戦績シェア画面
//
// 「今日」の勝敗数・勝率・連勝連敗をカード画像にして共有できる画面。
// あわせて、配信タイトルにそのまま使えるテキストも自動生成する。
struct ShareStatsView: View {
    @Query(sort: \BattleRecord.dateTimestamp, order: .reverse) private var allRecords: [BattleRecord]
    @State private var renderedImage: UIImage?
    @State private var showCopiedToast = false

    private var snapshot: BattleStatsSnapshot {
        BattleStatsSnapshot.today(from: allRecords)
    }

    private var dateText: String {
        Date().formatted(date: .abbreviated, time: .omitted)
    }

    /// 配信タイトルにそのまま貼れる文言
    private var suggestedTitle: String {
        var text = "【本日\(snapshot.wins)勝\(snapshot.losses)敗"
        if snapshot.totalGames > 0 {
            text += "・勝率\(String(format: "%.0f", snapshot.winRate))%"
        }
        text += "】"
        if !snapshot.streakText.isEmpty {
            text += snapshot.streakText + " "
        }
        text += "ボンバーガール配信"
        return text
    }

    var body: some View {
        ZStack {
            PuzzleBackground()
            ScrollView {
                VStack(spacing: 16) {
                    if snapshot.totalGames == 0 {
                        Text("今日はまだ戦績が記録されていません。1件登録すると、ここにカードが表示されます。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    }

                    cardPreview
                        .padding(.top, 8)

                    if let renderedImage {
                        ShareLink(
                            item: Image(uiImage: renderedImage),
                            preview: SharePreview("本日の戦績", image: Image(uiImage: renderedImage))
                        ) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("画像をシェア／保存")
                            }
                            .font(.headline)
                            .foregroundColor(.bongaOnAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.bongaPurple)
                            .cornerRadius(8)
                        }
                        .padding(.horizontal)
                    }

                    SectionLabel(text: "配信タイトル用の文言（自動生成）")
                        .padding(.horizontal).padding(.top, 8)
                    FormCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(suggestedTitle)
                                .font(.subheadline)
                                .textSelection(.enabled)
                            Button("コピー") {
                                UIPasteboard.general.string = suggestedTitle
                                showCopiedToast = true
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .bongaNavigationBar(title: "戦績をシェア")
        .onAppear {
            renderedImage = renderImage()
        }
        .onChange(of: allRecords) { _, _ in
            renderedImage = renderImage()
        }
        .alert("コピーしました", isPresented: $showCopiedToast) {
            Button("OK") { }
        }
    }

    private var cardPreview: some View {
        Group {
            if let renderedImage {
                Image(uiImage: renderedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 280)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            } else {
                ShareCardView(snapshot: snapshot, dateText: dateText)
                    .scaleEffect(280 / ShareCardView.size)
                    .frame(width: 280, height: 280)
                    .cornerRadius(16)
            }
        }
    }

    @MainActor
    private func renderImage() -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(snapshot: snapshot, dateText: dateText))
        renderer.scale = 3
        return renderer.uiImage
    }
}

#Preview {
    NavigationStack {
        ShareStatsView()
    }
}
