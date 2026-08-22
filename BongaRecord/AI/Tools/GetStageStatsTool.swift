import Foundation
import FoundationModels

/// 指示書 7章 Tool 5 / 26章 Case 5「苦手なステージは？」に対応するTool。
///
/// `getBattleSummary`は単一条件の集計しかできず、「複数ステージを横並びで
/// 比較して苦手/得意を判定する」ことはできない。このToolが無いままだと、
/// LLMは（実際に確認済みの通り）存在しないステージ名を作文してしまう。
struct GetStageStatsTool: Tool {
    let name = "getStageStats"

    let description = """
    ユーザー自身のボンガレコード戦績から、ステージ（マップ）別の試合数・勝敗数・勝率を
    ランキング形式で取得します。「苦手なステージ」「得意なステージ」「勝率が低い/高いステージ」
    のように複数ステージを比較する質問には、必ずこのToolを使用してください。
    存在するステージ名はこのToolの結果に含まれるものだけです。結果に無いステージ名を
    自分で作り出してはいけません。
    """

    @Generable
    struct Arguments {
        @Guide(description: "集計対象の期間。例: today, thisWeek, thisMonth, lastMonth, thisYear, recent30, all")
        var period: String

        @Guide(description: "キャラクター名で絞り込む場合に指定（例: セピア）。指定がなければ空文字")
        var character: String

        @Guide(description: "ロール名で絞り込む場合に指定（ボマー/アタッカー/シューター/ブロッカー）。指定がなければ空文字")
        var role: String

        @Guide(description: "この試合数未満のステージはランキングから除外する。1戦だけで苦手/得意と断定しないための下限。未指定なら3を使う", .range(0...100))
        var minimumMatches: Int

        @Guide(description: "上位何件返すか。未指定なら5", .range(1...20))
        var limit: Int

        @Guide(description: "勝率が高い順に見たい(得意ステージ探し)ならtrue、低い順(苦手ステージ探し)ならfalse")
        var sortByWinRateDescending: Bool
    }

    let analytics: BattleAnalyticsService

    func call(arguments: Arguments) async throws -> String {
        var query = BattleQuery(period: BattleQuery.period(fromToolString: arguments.period))
        if !arguments.character.isEmpty {
            query.characterId = MasterData.character(byName: arguments.character)?.id
        }
        if !arguments.role.isEmpty {
            query.roleFilter = CharacterRole.allCases.first { $0.label == arguments.role }
        }

        // LLMが0や極端な値を渡してきた場合の安全側デフォルト。
        let minimumMatches = arguments.minimumMatches > 0 ? arguments.minimumMatches : 3
        let limit = arguments.limit > 0 ? arguments.limit : 5

        let stats = try analytics.stageStats(
            query: query,
            minimumMatches: minimumMatches,
            limit: limit,
            sortByWinRateDescending: arguments.sortByWinRateDescending
        )

        guard !stats.isEmpty else {
            return "条件に合うステージがありません（試合数\(minimumMatches)戦以上のステージが見つかりませんでした）。"
        }

        let lines = stats.map { stat in
            "\(stat.name): \(stat.statistics.totalMatches)戦 \(stat.statistics.wins)勝\(stat.statistics.losses)敗 勝率\(stat.statistics.winRate)%"
        }
        return lines.joined(separator: "\n")
    }
}
