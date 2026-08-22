import Foundation
import SwiftData

/// 引継ぎデータ用のCSV入出力。
///
/// **取り込み（インポート）対応フォーマット**（別アプリが出力する引継ぎCSV）:
/// ```
/// 2025-08-08,10,32,1
/// 2025-08-14,24,57,1
/// ```
/// - ヘッダー行なし・4列固定
/// - 列順: 日付, ガールNo, マップNo, 勝敗
/// - 日付: yyyy-MM-dd
/// - 勝敗: 0=負け, 1=勝ち, 2=引分け
/// - 文字コード: UTF-8 / 改行: LF
/// - ガールNo・マップNo は **別アプリ側の公式No**。
///   本アプリ内部のID体系とは異なるため、`TransferTable` で
///   No → 名前 → 本アプリMasterDataのID へ変換する。
/// - 取り込めないNo（本アプリに存在しないキャラ/マップ）の行はスキップ。
/// - 完全に同一内容の行も、それぞれ1試合として全件取り込む（重複排除しない）。
enum CSVManager {

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    // MARK: - Export（自前バックアップ用。人間可読の名前ベース）

    /// - Note: マップ名・キャラ名は`Catalog.mapName/charName(byId:prefs:)`で解決する。
    ///   これにより、カスタム追加したマップ・キャラも名前付きで書き出せる
    ///   （`BattleRecord.mapName`/`.characterName`はMasterDataしか見ないため、
    ///   カスタム分だと「不明」になってしまう）。
    static func makeCSV(records: [BattleRecord],
                        playerInfo: PlayerInfo?,
                        mapPrefs: [MapPreference] = [],
                        charPrefs: [CharacterPreference] = []) -> String {
        var lines: [String] = []
        lines.reserveCapacity(records.count + 4)
        lines.append("# BongaRecord CSV v1")
        lines.append("date,map,character,result")
        for r in records {
            let dateStr = dateFormatter.string(from: r.date)
            let mapName = Catalog.mapName(byId: r.mapId, prefs: mapPrefs) ?? "不明"
            let charName = Catalog.charName(byId: r.characterId, prefs: charPrefs) ?? "不明"
            lines.append([dateStr,
                          escape(mapName),
                          escape(charName),
                          r.result.label].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Import

    /// 取り込んだ1行分の下書き。`BattleRecord`（`@Model`でSendable非準拠）を
    /// バックグラウンドactorへ直接渡すのは避け、この軽量な値型で受け渡す。
    /// actor側（`CSVImportActor`）でこのDraftから`BattleRecord`を生成しinsertする。
    struct ImportedBattleDraft: Sendable {
        let date: Date
        let mapId: Int
        let characterId: Int
        let result: BattleResult
    }

    struct ImportResult {
        /// 取り込めた戦績（まだ`ModelContext`にはinsertされていない下書き）
        var records: [ImportedBattleDraft]
        /// 行はあったが、未知のNo・不正な値でスキップした件数
        var skipped: Int
    }

    enum ImportError: LocalizedError {
        case decodingFailed
        var errorDescription: String? {
            switch self {
            case .decodingFailed: return "ファイルの読み込みに失敗しました"
            }
        }
    }

    /// 別アプリの引継ぎCSV（ヘッダーなし4列）を解析する。
    static func parseCSV(_ text: String) throws -> ImportResult {
        // LF / CRLF どちらでも分割できるようにCRを除去
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
                             .replacingOccurrences(of: "\r", with: "\n")
        let rawLines = normalized.split(separator: "\n", omittingEmptySubsequences: false)

        var records: [ImportedBattleDraft] = []
        records.reserveCapacity(rawLines.count)
        var skipped = 0

        for raw in rawLines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") { continue }       // コメント行は無視

            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
                           .map { $0.trimmingCharacters(in: .whitespaces) }

            // 4列に満たない行はスキップ
            guard cols.count >= 4 else { skipped += 1; continue }

            // 自前バックアップCSVのヘッダー行 "date,map,character,result" は無視
            if cols[0] == "date" { continue }

            // 1) 日付
            guard let date = dateFormatter.date(from: cols[0]) else { skipped += 1; continue }

            // 2) ガールNo → 名前 → 本アプリのキャラID
            guard let girlNo = Int(cols[1]),
                  let charName = TransferTable.characterName(forGirlNo: girlNo),
                  let character = MasterData.character(byName: charName) else {
                skipped += 1; continue
            }

            // 3) マップNo → 名前 → 本アプリのマップID
            guard let mapNo = Int(cols[2]),
                  let mapName = TransferTable.mapName(forMapNo: mapNo),
                  let map = MasterData.map(byName: mapName) else {
                skipped += 1; continue
            }

            // 4) 勝敗 0=負け / 1=勝ち / 2=引分け
            guard let resultCode = Int(cols[3]),
                  let result = TransferTable.battleResult(forCode: resultCode) else {
                skipped += 1; continue
            }

            records.append(ImportedBattleDraft(date: date,
                                                mapId: map.id,
                                                characterId: character.id,
                                                result: result))
        }

        return ImportResult(records: records, skipped: skipped)
    }

    // MARK: - Helpers

    private static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return s
    }
}
