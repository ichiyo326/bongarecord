import SwiftUI
import SwiftData

struct BattleEditView: View {
    @Environment(\.modelContext) private var context
    @Query private var mapPrefs: [MapPreference]
    @Query private var charPrefs: [CharacterPreference]
    // 太さ/色などテーマの変更をこの画面が生きている間もライブ反映するために保持。
    @ObservedObject private var theme = ThemeManager.shared

    @State private var filterDate: Date?         = nil
    @State private var filterCharacterId: Int?   = nil    // nil = 指定なし
    @State private var searchResults: [BattleRecord] = []
    @State private var hasSearched = false

    var body: some View {
        ZStack {
            PuzzleBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    SectionLabel(text: "日付")
                        .padding(.horizontal).padding(.top, 8)
                    FormCard {
                        OptionalDateField(date: $filterDate,
                                          placeholder: "タップして日付入力")
                    }

                    SectionLabel(text: "使用キャラ")
                        .padding(.horizontal).padding(.top, 12)
                    FormCard {
                        let chars = Catalog.resolvedCharacters(prefs: charPrefs)
                        Menu {
                            Button("（指定なし）") { filterCharacterId = nil }
                            ForEach(CharacterRole.allCases) { role in
                                let inRole = chars.filter { $0.role == role }
                                if !inRole.isEmpty {
                                    Section(header: Text(role.label)) {
                                        ForEach(inRole) { c in
                                            Button(c.name) { filterCharacterId = c.id }
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(filterCharacterId
                                     .flatMap { Catalog.charName(byId: $0, prefs: charPrefs) }
                                     ?? "（指定なし）")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.down").foregroundColor(.secondary)
                            }
                        }
                    }

                    PrimaryButton(title: "検索") {
                        runSearch()
                    }
                    .padding(.horizontal).padding(.top, 16)

                    if hasSearched {
                        resultsTable.padding(.top, 16)
                    }
                }
            }
        }
        .bongaNavigationBar(title: "戦績修正")
    }

    // MARK: - Search（SQL層でフィルタ）

    private func runSearch() {
        // 日付フィルタを Timestamp 範囲に変換
        var startTs: Int64 = .min
        var endTs:   Int64 = .max
        if let d = filterDate {
            let cal = Calendar.current
            let start = cal.startOfDay(for: d)
            let end   = cal.date(byAdding: .day, value: 1, to: start) ?? start
            startTs = Int64(start.timeIntervalSince1970)
            endTs   = Int64(end.timeIntervalSince1970)
        }
        let charId = filterCharacterId   // ローカルにキャプチャ

        let predicate: Predicate<BattleRecord>
        if let charId {
            predicate = #Predicate {
                $0.dateTimestamp >= startTs &&
                $0.dateTimestamp <  endTs   &&
                $0.characterId == charId
            }
        } else {
            predicate = #Predicate {
                $0.dateTimestamp >= startTs &&
                $0.dateTimestamp <  endTs
            }
        }

        var descriptor = FetchDescriptor<BattleRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.dateTimestamp, order: .reverse)]
        )
        // 100万件想定でも初回表示は200件まで（必要に応じて拡張）
        descriptor.fetchLimit = 200

        searchResults = (try? context.fetch(descriptor)) ?? []
        hasSearched = true
    }

    // MARK: - Results Table

    private var resultsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("使用ガール").frame(width: 80, alignment: .leading)
                Text("マップ").frame(maxWidth: .infinity, alignment: .leading)
                Text("勝敗").frame(width: 56, alignment: .leading)
                Spacer().frame(width: 60)
            }
            .font(.bongaEmphasis(.caption))
            .foregroundColor(Color.bongaCyanLight.readableForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.bongaCyanLight)

            if searchResults.isEmpty {
                Text("該当データなし")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(searchResults) { record in
                    HStack {
                        Text(Catalog.charName(byId: record.characterId, prefs: charPrefs) ?? "不明")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: 80, alignment: .leading)
                        Text(Catalog.mapName(byId: record.mapId, prefs: mapPrefs) ?? "不明")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(record.result.label)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: 56, alignment: .leading)
                        NavigationLink {
                            BattleRecordEditForm(record: record) {
                                runSearch()
                            }
                        } label: {
                            Text("編集")
                                .font(.footnote)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color(uiColor: .systemGray5))
                                .cornerRadius(4)
                        }
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    Divider()
                }
                if searchResults.count >= 200 {
                    Text("…他にも結果があります（先頭200件のみ表示）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}

// MARK: - Optional Date Field

struct OptionalDateField: View {
    @Binding var date: Date?
    let placeholder: String

    @State private var showSheet = false
    @State private var tempDate = Date()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        Button {
            tempDate = date ?? Date()
            showSheet = true
        } label: {
            HStack {
                Text(date.map { Self.formatter.string(from: $0) } ?? placeholder)
                    .foregroundColor(date == nil ? .secondary : .primary)
                Spacer()
                if date != nil {
                    Button {
                        date = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("日付をクリア")
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            NavigationStack {
                DatePicker("日付選択", selection: $tempDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("キャンセル") { showSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("OK") {
                                date = tempDate
                                showSheet = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Edit Form

struct BattleRecordEditForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) var dismiss

    @Bindable var record: BattleRecord
    let onChange: () -> Void

    @State private var selectedMapId: Int = 0
    @State private var selectedCharacterId: Int = 0
    @State private var result: BattleResult = .win
    @State private var selectedDate: Date = Date()
    @State private var showDeleteConfirm = false
    @State private var saveError: String?

    var body: some View {
        ZStack {
            PuzzleBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    SectionLabel(text: "対戦マップ")
                        .padding(.horizontal).padding(.top, 8)
                    FormCard {
                        MapPickerField(selectionId: $selectedMapId)
                    }

                    SectionLabel(text: "使用キャラ")
                        .padding(.horizontal).padding(.top, 12)
                    FormCard {
                        CharacterPickerField(selectionId: $selectedCharacterId)
                    }

                    SectionLabel(text: "勝敗")
                        .padding(.horizontal).padding(.top, 12)
                    HStack(spacing: 24) {
                        ForEach(BattleResult.allCases) { r in
                            RadioButton(label: r.label, isSelected: result == r) {
                                result = r
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal).padding(.vertical, 12)

                    SectionLabel(text: "試合日")
                        .padding(.horizontal).padding(.top, 12)
                    FormCard {
                        RecordDateField(date: $selectedDate)
                    }

                    HStack(spacing: 12) {
                        PrimaryButton(title: "修正") {
                            saveChanges()
                        }
                        PrimaryButton(title: "削除", action: { showDeleteConfirm = true }, background: .red)
                    }
                    .padding(.horizontal).padding(.top, 16)
                }
            }
        }
        .bongaNavigationBar(title: "戦績修正")
        .onAppear {
            selectedMapId = record.mapId
            selectedCharacterId = record.characterId
            result = record.result
            selectedDate = record.date
        }
        .alert("このレコードを削除しますか？", isPresented: $showDeleteConfirm) {
            Button("削除", role: .destructive) {
                deleteRecord()
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("この操作は取り消せません。")
        }
        .alert("保存できませんでした", isPresented: .constant(saveError != nil), presenting: saveError) { _ in
            Button("OK") { saveError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func saveChanges() {
        record.mapId = selectedMapId
        record.characterId = selectedCharacterId
        record.resultRaw = result.rawValue
        record.date = selectedDate

        do {
            try context.save()
            onChange()
            dismiss()
        } catch {
            context.rollback()
            saveError = error.localizedDescription
        }
    }

    private func deleteRecord() {
        context.delete(record)
        do {
            try context.save()
            onChange()
            dismiss()
        } catch {
            context.rollback()
            saveError = error.localizedDescription
        }
    }
}
