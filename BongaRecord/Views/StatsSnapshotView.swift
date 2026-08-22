import SwiftUI

// MARK: - 戦績表スクリーンショット用View
//
// 通常のOSスクリーンショットだと、ステータスバー／ナビバー／ホームインジケータが
// 写り込んだり、結果がスクロール領域からはみ出て途中で切れたりする。
// このViewは画面には表示せず`ImageRenderer`でラスタライズする専用に、
// 「試合数〜ロール別〜集計テーブル」を1枚の非スクロールViewとして組み直したもの。
// 高さは内容に応じて自動で決まるため、行数がいくら多くても切れない。
struct StatsSnapshotView: View {
    let periodText: String
    let totalGames: Int
    let totalWins: Int
    let totalLosses: Int
    let totalDraws: Int
    let roleStats: [BattleStatsView.RoleStat]
    let groupTitle: String
    let primaryColumnTitle: String
    let showSecondary: Bool
    let aggregated: [BattleStatsView.AggregatedStat]

    private var winRate: Double { totalGames > 0 ? Double(totalWins) / Double(totalGames) * 100 : 0 }
    private var diff: Int { totalWins - totalLosses }

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー帯（アプリのナビバーと同じ配色にして、単体で見ても
            // 何のアプリの戦績かひと目でわかるようにする）
            HStack {
                Text("BONGA RECORD")
                    .font(.system(.caption, design: .rounded)).bold()
                    .tracking(1)
                Spacer()
                Text(periodText)
                    .font(.system(.caption, design: .rounded))
            }
            .foregroundColor(.bongaOnAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.bongaPurple)

            VStack(alignment: .leading, spacing: 10) {
                summary

                if !roleStats.isEmpty {
                    roleTable
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(groupTitle)
                        .font(.bongaEmphasis(.subheadline))
                        .foregroundColor(.bongaPurple)
                    resultsTable
                }
            }
            .padding(14)
            .background(Color(uiColor: .systemBackground))
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - Summary（BattleStatsView.summaryViewと同内容）

    private var summary: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 16) {
                Text("試合数：\(totalGames)")
                Text("\(totalWins)勝 \(totalLosses)敗" + (totalDraws > 0 ? " \(totalDraws)分" : ""))
            }
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("差分：")
                    Text(diffText(diff)).foregroundColor(diffColor(diff)).bongaBold()
                }
                Text(String(format: "勝率：%.1f%%", winRate))
            }
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(10)
    }

    // MARK: - ロール別（BattleStatsView.roleStatsViewと同内容）

    private var roleTable: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("ロール別")
                .font(.bongaEmphasis(.subheadline))
                .foregroundColor(.bongaPurple)
            ForEach(roleStats) { rs in
                HStack {
                    Image(systemName: rs.role.iconName)
                        .foregroundColor(.bongaIcon)
                        .frame(width: 20)
                    Text(rs.role.label)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 84, alignment: .leading)
                    Text("\(rs.games)戦")
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 44, alignment: .trailing)
                    Text("\(rs.wins)勝")
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 40, alignment: .trailing)
                    Text(diffText(rs.diff))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 44, alignment: .trailing)
                        .foregroundColor(diffColor(rs.diff))
                    Text(String(format: "%.1f%%", rs.winRate * 100))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundColor(.bongaPurple)
                }
                .font(.caption)
            }
        }
        .padding(6)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - 集計テーブル（BattleStatsView.resultsTableと同内容）

    private var resultsTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(primaryColumnTitle)
                    .frame(width: showSecondary ? 72 : 100, alignment: .leading)
                if showSecondary {
                    Text("マップ").frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("試合").frame(width: 40, alignment: .trailing)
                if !showSecondary {
                    Text("勝").frame(width: 36, alignment: .trailing)
                }
                Text("差分").frame(width: 46, alignment: .trailing)
                Text("勝率").frame(width: 54, alignment: .trailing)
            }
            .font(.bongaEmphasis(.caption))
            .foregroundColor(Color.bongaCyanLight.readableForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.bongaCyanLight)

            if aggregated.isEmpty {
                Text("該当データなし")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(aggregated) { stat in
                    HStack(spacing: 0) {
                        Text(stat.primary)
                            .frame(width: showSecondary ? 72 : 100, alignment: .leading)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        if showSecondary {
                            Text(stat.secondary ?? "")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Text("\(stat.games)").frame(width: 40, alignment: .trailing)
                        if !showSecondary {
                            Text("\(stat.wins)").frame(width: 36, alignment: .trailing)
                        }
                        Text(diffText(stat.diff))
                            .frame(width: 46, alignment: .trailing)
                            .foregroundColor(diffColor(stat.diff))
                        Text(String(format: "%.1f%%", stat.winRate * 100))
                            .frame(width: 54, alignment: .trailing)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    Divider()
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: - 差分表示ヘルパー（BattleStatsViewと同内容）

    private func diffText(_ diff: Int) -> String {
        if diff > 0 { return "+\(diff)" }
        if diff < 0 { return "\(diff)" }
        return "±0"
    }
    private func diffColor(_ diff: Int) -> Color {
        if diff > 0 { return .green }
        if diff < 0 { return .red }
        return .secondary
    }
}

#Preview {
    StatsSnapshotView(
        periodText: "2026/08/22",
        totalGames: 8, totalWins: 6, totalLosses: 2, totalDraws: 0,
        roleStats: [],
        groupTitle: "ガール別",
        primaryColumnTitle: "ガール",
        showSecondary: false,
        aggregated: []
    )
    .frame(width: 380)
}

// MARK: - スクリーンショットのプレビュー／共有シート
//
// 元々はBattleStatsViewの`.sheet`の中に直接、画像プレビュー＋3つの共有ボタンを
// ベタ書きしていたが、それだと`body`全体の巨大なViewBuilder式の一部として
// まとめて型推論されてしまい、コンパイラの型検査がタイムアウトしていた。
// 独立したView構造体に切り出すことで、型検査の単位を小さく保つ。
struct SnapshotPreviewSheet: View {
    let image: UIImage
    let onSaveToPhotos: () -> Void
    let onShareToX: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 3)

                saveButton
                xShareButton
                otherShareLink
            }
            .bongaNavigationBar(title: "戦績表のスクリーンショット")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる", action: onDismiss)
                }
            }
        }
    }

    private var saveButton: some View {
        Button(action: onSaveToPhotos) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text("写真に保存")
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

    // Xへの投稿。X（旧Twitter）はURLスキームからの画像添付をサポートしていないため
    // （サーバー側でのメディアアップロードAPIが必要になり、OAuth連携・バックエンドが
    // 要る＝本アプリの「外部バックエンドを持たない」方針に反する）、画像をクリップ
    // ボードにコピーした上で投稿画面を開き、本文欄への貼り付けはユーザーの手動操作に委ねる。
    private var xShareButton: some View {
        Button(action: onShareToX) {
            HStack {
                Text("X").font(.headline.bold())
                Text("にシェア")
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.black)
            .cornerRadius(8)
        }
        .padding(.horizontal)
    }

    // 「その他のアプリで開く／AirDrop」などはこちら。
    // `UIImage`自体は`Transferable`に準拠していない（準拠しているのはSwiftUIの
    // `Image`の方）ため、`item`にはSwiftUIの`Image`を渡す必要がある。
    // 写真アプリへの保存は上の「写真に保存」ボタン（PHPhotoLibrary）で
    // 確実に行っているので、ここは他アプリ共有・コピー・AirDrop用と割り切る。
    private var otherShareLink: some View {
        ShareLink(
            item: Image(uiImage: image),
            preview: SharePreview("戦績表", image: Image(uiImage: image))
        ) {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("その他の方法でシェア")
            }
            .font(.subheadline)
            .foregroundColor(.bongaPurple)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .padding(.horizontal)
        .padding(.bottom, 24)
    }
}
