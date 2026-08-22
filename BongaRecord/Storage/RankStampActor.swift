import Foundation
import SwiftData

// MARK: - ランク初期設定 専用ModelActor
//
// ランク機能を初めてONにしたとき、「過去の全記録に現在ランクをスタンプする」
// 処理を行う。`BattleRecord`は100万行保持を想定した設計のため、件数次第では
// MainActor上での同期forループがUIを固まらせうる。CSVインポートと同じ理由で、
// バックグラウンドactorに逃がす。
//
// **重要な実測結果（実機・件数2000〜20000で検証）**:
// 当初はCSVインポートと同じ「batchSizeごとにsave」を行っていたが、
// これは逆効果だった。CSVインポートは「新規オブジェクトをinsertする」重い
// 処理なのでバッチsaveによる1トランザクションの負荷分散が効くが、
// ランクスタンプは「既存オブジェクトのプロパティを1個書き換えるだけ」の
// 軽い処理。そこにsave呼び出しを何十回も挟むと、save自体のオーバーヘッドが
// 負荷分散のメリットを上回ってしまい、Legacy(全件更新→save1回)より
// 遅くなった（2万件で実測+35%）。
// 「バッチsave = 速い」という前提が常に成り立つわけではなく、1件あたりの
// 書き込みコストが重い処理（insert等）でだけ効く、という反証。
// そのため、ここでは全件更新後に1回だけsaveする形に留める。
// actorに逃がすことでMainActorを塞がないメリットはそのまま残る。
@ModelActor
actor RankStampActor {

    /// 全戦績の`rankRaw`を`rank`で一括上書きする。更新できた件数を返す。
    func stampAll(rank: Int) throws -> Int {
        let all = try modelContext.fetch(FetchDescriptor<BattleRecord>())
        for r in all { r.rankRaw = rank }
        try modelContext.save()
        return all.count
    }
}
