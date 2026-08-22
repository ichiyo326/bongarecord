import SwiftUI

// MARK: - 配信連携（OBS）設定画面

/// 「本日/このセッションの勝敗数・勝率」「直近の連勝／連敗」を
/// OBSのBrowser Sourceへリアルタイム反映するための設定画面。
///
/// v3: Firebaseの作成もoverlay.htmlの編集も、外部サイトへのホスティングも不要。
/// アプリが専用HTMLファイルをその場で生成する。ユーザーがここで行うのは
/// 「ファイルを書き出してOBSのパソコンに送る」→「配信を開始」だけ。
struct StreamSettingsView: View {
    @ObservedObject private var sync = StreamOverlaySync.shared
    @State private var shareItem: ShareFile?
    @State private var showRegenerateConfirm = false
    @State private var showExportError = false

    var body: some View {
        ZStack {
            PuzzleBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // MARK: ベータ機能の注記
                    if !FeatureFlags.obsStreamingReleased {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .foregroundColor(.bongaPurple)
                            Text("この機能は開発中のベータ版です。今後の更新で仕様が変わる場合があります。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.bongaPurple, lineWidth: 1)
                        )
                        .padding(.horizontal).padding(.top, 8)
                    }

                    // MARK: 使い方（4ステップだけ）
                    SectionLabel(text: "使い方")
                        .padding(.horizontal).padding(.top, 8)
                    FormCard {
                        VStack(alignment: .leading, spacing: 14) {
                            StepRow(number: 1,
                                    title: "下の「OBS用ファイルを書き出す」を押す",
                                    detail: "あなた専用のオーバーレイHTMLファイルがその場で作られます。Firebaseの登録や他のファイルの編集は不要です。")
                            StepRow(number: 2,
                                    title: "OBSを使うパソコンに送る",
                                    detail: "共有シートから「AirDrop」でMacに送る、または「ファイルに保存」してiCloud Drive経由でパソコンへ、などお好きな方法で。")
                            StepRow(number: 3,
                                    title: "OBSの「ローカルファイル」で指定",
                                    detail: "OBSの「ソース」→「＋」→「ブラウザ」→「ローカルファイル」にチェックを入れて、送ったファイルを選ぶ。幅420・高さ160程度でOK。透過背景なので好きな位置に配置できます。")
                            StepRow(number: 4,
                                    title: "配信本番での使い方",
                                    detail: "配信前にこのページで「配信を開始」を押す（その時点から勝敗を数え直します）→ 試合ごとにいつも通り「戦績登録」で記録 → 自動でOBSに反映 → 終わったら「配信を終了」。")
                        }
                    }

                    SectionLabel(text: "OBS用ファイル")
                        .padding(.horizontal).padding(.top, 12)
                    FormCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("ボタンを押すたびに最新の設定でファイルを作り直します。トークンを再発行した場合は、ここから作り直してOBSに送り直してください。")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button {
                                if let url = sync.writeOverlayHTMLFile() {
                                    shareItem = ShareFile(url: url)
                                } else {
                                    showExportError = true
                                }
                            } label: {
                                Text("OBS用ファイルを書き出す")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("トークンを再発行", role: .destructive) {
                                showRegenerateConfirm = true
                            }
                            .font(.caption)
                        }
                    }

                    SectionLabel(text: "配信状態")
                        .padding(.horizontal).padding(.top, 12)
                    FormCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Circle()
                                    .fill(sync.isStreaming ? Color.green : Color.gray)
                                    .frame(width: 10, height: 10)
                                Text(sync.isStreaming ? "配信中（このセッションの戦績を送信しています）" : "停止中")
                                    .font(.subheadline)
                            }
                            if sync.isStreaming {
                                Text("集計開始: \(sync.sessionStartDate.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let last = sync.lastSyncedAt {
                                Text("最終送信: \(last.formatted(date: .omitted, time: .standard))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let error = sync.lastError {
                                Text("⚠️ \(error)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        if sync.isStreaming {
                            PrimaryButton(title: "配信を終了", action: { sync.stopStreaming() }, background: .gray)
                        } else {
                            PrimaryButton(title: "配信を開始（集計をリセット）") {
                                sync.startStreaming()
                            }
                        }
                    }
                    .padding(.horizontal).padding(.top, 16)
                }
            }
        }
        .bongaNavigationBar(title: "配信連携（OBS）")
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(items: [item.url])
        }
        .alert("ファイルの書き出しに失敗しました", isPresented: $showExportError) {
            Button("OK") { }
        } message: {
            Text("もう一度お試しください。")
        }
        .alert("トークンを再発行しますか？", isPresented: $showRegenerateConfirm) {
            Button("キャンセル", role: .cancel) { }
            Button("再発行する", role: .destructive) {
                sync.regenerateToken()
            }
        } message: {
            Text("今までのOBS用ファイルは使えなくなります。「OBS用ファイルを書き出す」から作り直して、OBSに送り直してください。")
        }
    }
}

// MARK: - 手順ステップ1行分（番号バッジ＋タイトル＋説明）

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundColor(.bongaOnAccent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.bongaPurple))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - 標準の共有シート（AirDrop / ファイルに保存 / メール などをまとめて出す）

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// `.sheet(item:)` に渡すための小さなラッパー（毎回新規生成するファイルURLをそのまま
/// Identifiableにすると衝突しやすいため、書き出しごとに新しいIDを振る）。
private struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

#Preview {
    NavigationStack {
        StreamSettingsView()
    }
}
