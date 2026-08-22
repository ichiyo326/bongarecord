import SwiftUI
import SwiftData
import FoundationModels

/// Phase 3: `getBattleSummary`Toolを接続した戦績AI画面。
///
/// Tool無しのPhase 2ではLLMが「戦績」という単語から関係のない話題を
/// 作文してしまう問題があったため、必ずToolの結果だけを根拠に答えるよう
/// instructionsで明示的に縛っている（指示書1章・32章）。
struct BattleAIView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var question: String = ""
    @State private var answer: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            switch BattleAIAvailability.current {
            case .unavailable(let reason):
                unavailableView(reason: reason)
            case .available:
                availableView
            }
        }
        .bongaNavigationBar(title: "戦績AI")
    }

    private func unavailableView(reason: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("AI分析は現在利用できません")
                .font(.bongaEmphasis(.headline))
            Text(reason)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var availableView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !FeatureFlags.battleAIReleased {
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

            ScrollView {
                Text(answer.isEmpty ? "質問を入力してください（例: こんにちは）" : answer)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                TextField("質問を入力…", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isLoading)

                Button {
                    Task { await ask() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text("送信")
                    }
                }
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding()
        }
    }

    /// `getBattleSummary`Toolを渡した質問応答（指示書25章 Phase 3の最初の1つ）。
    private func ask() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let asked = question
        let analytics = BattleAnalyticsService(context: modelContext)

        do {
            let session = LanguageModelSession(
                tools: [
                    GetBattleSummaryTool(analytics: analytics),
                    GetStageStatsTool(analytics: analytics)
                ],
                instructions: """
                あなたはボンガレコードというアプリの戦績アシスタントです。

                ・ユーザーの戦績（試合数・勝率・勝敗など）に関する質問には、必ず
                  getBattleSummaryまたはgetStageStatsツールを呼び出し、
                  その結果の数値・名前だけを根拠に答えてください。
                ・「苦手なステージ」「得意なステージ」のように複数のステージを比較する質問には
                  getStageStatsを使ってください。単一条件（例: 今月の勝率）にはgetBattleSummaryを
                  使ってください。
                ・ツールを使わずに数値やステージ名・キャラ名を作り出してはいけません。
                  ツールの結果に出てこない名前を使わないでください。
                ・今のToolでは答えられない質問（例: キャラ別ランキング、期間比較）が来た場合は、
                  分かったふりをせず「その分析はまだ対応していません」と正直に答えてください。
                ・ボンバーガール（このアプリが記録する対象のゲーム）やユーザーの戦績と
                  無関係な話題（歌手、楽曲、一般知識など）には答えず、
                  「戦績についてお答えできる範囲の質問をお願いします」と返してください。
                ・ツールの結果が0件だった場合は、断定的な評価をせず、
                  データが不足している旨を伝えてください。
                ・簡潔な日本語で答えてください。
                """
            )
            let response = try await session.respond(to: asked)
            answer = response.content
        } catch {
            errorMessage = "応答の取得に失敗しました: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack { BattleAIView() }
        .modelContainer(for: [BattleRecord.self], inMemory: true)
}
