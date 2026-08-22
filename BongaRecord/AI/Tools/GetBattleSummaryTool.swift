import Foundation
import FoundationModels

/// 指示書 7章 Tool 1 / 10章のサンプルに対応する最初のTool。
///
/// ユーザー自身の戦績から、指定条件の試合数・勝敗数・勝率を取得する。
/// 数値計算は`BattleAnalyticsService`（Swift側の確定ロジック）が行い、
/// LLMは「意図解釈」「Tool選択」「結果の説明」のみを担当する（指示書1章）。
///
/// - Note: `Tool.Output`は総称型で、`String`または`Generable`型を直接返す
///   （`ToolOutput`という専用ラッパー型は現行のFoundationModelsには存在しない。
///   指示書10章のサンプルコードはベータ版当時のAPIを参照しており、
///   `func call(arguments:) async throws -> String` が現行の正しいシグネチャ）。
struct GetBattleSummaryTool: Tool {
    let name = "getBattleSummary"

    let description = """
    ユーザー自身のボンガレコード戦績から、指定期間・キャラクター・ロール・ステージ条件の
    試合数、勝敗数、勝率を取得します。
    戦績（試合数・勝率など）に関する数値を回答するときは、推測せず必ずこのToolを使用してください。
    """

    @Generable
    struct Arguments {
        @Guide(description: "集計対象の期間。例: today, thisWeek, thisMonth, lastMonth, thisYear, recent30, all")
        var period: String

        @Guide(description: "キャラクター名（例: セピア）。指定がなければ空文字")
        var character: String

        @Guide(description: "ロール名（ボマー/アタッカー/シューター/ブロッカー）。指定がなければ空文字")
        var role: String

        @Guide(description: "ステージ（マップ）名。指定がなければ空文字")
        var stage: String
    }

    /// `ModelContext`を直接持たず、Facade経由でのみSwiftDataへ触れる（指示書6章）。
    /// これによりToolの単体テストでは`analytics`をin-memoryなものに差し替えるだけでよい。
    let analytics: BattleAnalyticsService

    func call(arguments: Arguments) async throws -> String {
        var query = BattleQuery(period: BattleQuery.period(fromToolString: arguments.period))

        if !arguments.character.isEmpty {
            // ユーザーカスタム名の解決はPhase 1メモ記載の既知の制約により未対応。
            // まずはMasterDataの標準名で解決する。
            query.characterId = MasterData.character(byName: arguments.character)?.id
        }
        if !arguments.role.isEmpty {
            query.roleFilter = CharacterRole.allCases.first { $0.label == arguments.role }
        }
        if !arguments.stage.isEmpty {
            query.mapId = MasterData.map(byName: arguments.stage)?.id
        }

        let result = try analytics.summary(query: query)

        return """
        試合数: \(result.totalMatches)
        勝利: \(result.wins)
        敗北: \(result.losses)
        引分: \(result.draws)
        勝率: \(result.winRate)%
        """
    }
}
