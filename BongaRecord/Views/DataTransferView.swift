import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataTransferView: View {
    @Environment(\.modelContext) private var context
    @Query private var playerInfos: [PlayerInfo]
    // バックアップCSVでカスタムマップ/キャラの名前を正しく解決するために必要。
    @Query private var mapPrefs: [MapPreference]
    @Query private var charPrefs: [CharacterPreference]
    // 太さ/色などテーマの変更をこの画面が生きている間もライブ反映するために保持。
    @ObservedObject private var theme = ThemeManager.shared

    @State private var fileName: String  = ""
    @State private var showExporter      = false
    @State private var showImporter      = false
    @State private var showImportConfirm = false
    @State private var pendingImportURL: URL?

    @State private var alertTitle        = ""
    @State private var alertMessage      = ""
    @State private var showAlert         = false

    @State private var exportDocument: CSVDocument?
    @State private var isProcessing      = false
    @State private var importProgress    = 0
    @State private var importTotal       = 0

    var body: some View {
        ZStack {
            PuzzleBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {

                    // 作成（エクスポート）
                    HStack(spacing: 8) {
                        TextField("ファイル名（拡張子不要）", text: $fileName)
                            .padding(.vertical, 10).padding(.horizontal, 12)
                            .background(Color(uiColor: .systemBackground))
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(Color(uiColor: .systemGray4)),
                                alignment: .bottom
                            )
                        Button("作成") { beginExport() }
                            .font(.headline).foregroundColor(.white)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(Color.bongaPurple).cornerRadius(4)
                    }
                    .padding(.horizontal).padding(.top, 12)

                    // 取込（インポート）
                    HStack(spacing: 8) {
                        Text("引継ぎデータ取り込み")
                            .padding(.vertical, 12).padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .systemBackground))
                            .overlay(
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(Color(uiColor: .systemGray4)),
                                alignment: .bottom
                            )
                        Button("取込") { showImporter = true }
                            .font(.headline).foregroundColor(.white)
                            .padding(.horizontal, 20).padding(.vertical, 12)
                            .background(Color.bongaPurple).cornerRadius(4)
                    }
                    .padding(.horizontal)

                    // 背景画像の上でも警告文が確実に読めるよう、不透明な下地を追加。
                    VStack(alignment: .leading, spacing: 2) {
                        Text("引継ぎデータを取り込むと")
                        Text("現在の戦績記録は削除されます!!")
                    }
                    .font(.bongaEmphasis(.callout))
                    .foregroundColor(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .systemBackground))
                    .cornerRadius(8)
                    .padding(.horizontal).padding(.top, 8)

                    if isProcessing {
                        if importTotal > 0 {
                            ProgressView(value: Double(importProgress), total: Double(importTotal))
                                .padding(.horizontal).padding(.top, 8)
                            Text("\(importProgress) / \(importTotal) 件")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        } else {
                            ProgressView("処理中...")
                                .padding(.horizontal).padding(.top, 8)
                        }
                    }

                    Spacer().frame(height: 200)
                }
            }
        }
        .bongaNavigationBar(title: "引継ぎデータ作成／取込")
        .fileExporter(isPresented: $showExporter,
                      document: exportDocument,
                      contentType: .commaSeparatedText,
                      defaultFilename: fileName.isEmpty ? "BongaRecord" : fileName) { result in
            switch result {
            case .success:
                alertTitle = "作成完了"
                alertMessage = "ファイルを保存しました"
            case .failure(let error):
                alertTitle = "保存失敗"
                alertMessage = error.localizedDescription
            }
            showAlert = true
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.commaSeparatedText, .plainText, .text],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                pendingImportURL = url
                showImportConfirm = true
            case .failure(let error):
                alertTitle = "選択失敗"
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
        .alert("取り込みを実行しますか？",
               isPresented: $showImportConfirm,
               presenting: pendingImportURL) { url in
            Button("取り込む", role: .destructive) {
                Task { await runImport(url: url) }
            }
            Button("キャンセル", role: .cancel) { }
        } message: { _ in
            Text("現在の戦績記録はすべて削除され、CSVの内容に置換されます。\nこの操作は取り消せません。")
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Export

    private func beginExport() {
        Task {
            isProcessing = true
            defer { isProcessing = false }
            do {
                let descriptor = FetchDescriptor<BattleRecord>(
                    sortBy: [SortDescriptor(\.dateTimestamp, order: .reverse)]
                )
                let records = try context.fetch(descriptor)
                let pi = playerInfos.first
                let csv = CSVManager.makeCSV(records: records,
                                             playerInfo: pi,
                                             mapPrefs: mapPrefs,
                                             charPrefs: charPrefs)
                exportDocument = CSVDocument(text: csv)
                showExporter = true
            } catch {
                alertTitle = "書き出し失敗"
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }

    // MARK: - Import（バックグラウンドactorでバッチ削除＋バッチinsert）

    private func runImport(url: URL) async {
        isProcessing = true
        importProgress = 0
        importTotal = 0
        defer { isProcessing = false }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = try CSVManager.parseCSV(text)
            importTotal = parsed.records.count

            // ランク機能ON時は、取り込んだ全件に現在のランクをスタンプ
            let pi = playerInfos.first
            let stampRaw: Int = (pi?.rankTrackingEnabled == true) ? pi!.currentRankRaw : -1

            // 実際の削除・挿入・保存はMainActorから切り離したactorで行う。
            // ここでは進捗（処理済み件数）を受け取ってUIに反映するだけ。
            let importer = CSVImportActor(modelContainer: context.container)
            for try await done in importer.importAll(parsed.records, rankStampRaw: stampRaw) {
                importProgress = done
            }

            // 別actor（別ModelContext）で行った変更をこの画面のcontextへ
            // 反映させる。SwiftDataは変更を自動で追跡し直すが、@Queryの
            // 表示元となるcontextを明示的に最新化しておくと確実。
            try? context.save()

            // 勝敗コードの解釈（painyaunta 0=負け/1=勝ち という前提）が正しいか、
            // 取り込み直後に内訳を見て目視確認できるようにする。
            let wins   = parsed.records.filter { $0.result == .win }.count
            let losses = parsed.records.filter { $0.result == .lose }.count
            let draws  = parsed.records.filter { $0.result == .draw }.count

            alertTitle = "取り込み完了"
            var message = "戦績 \(parsed.records.count) 件を取り込みました\n"
                + "（勝ち\(wins) / 負け\(losses) / 引分け\(draws)）"
            if parsed.skipped > 0 {
                message += "\n（未対応のキャラ／マップ等で \(parsed.skipped) 行をスキップ）"
            }
            alertMessage = message
            showAlert = true
        } catch {
            alertTitle = "取り込み失敗"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }
}

// MARK: - CSV Document（fileExporter用）

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let s = String(data: data, encoding: .utf8) {
            self.text = s
        } else {
            self.text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}
