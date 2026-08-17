import SwiftUI
import SwiftData

/// キャラの並び替え・非表示・追加・削除を行う管理画面。
struct CharacterManagementView: View {
    // 太さ/色などテーマの変更をこの画面が生きている間もライブ反映するために保持。
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.modelContext) private var context
    @Query private var prefs: [CharacterPreference]

    @State private var items: [DisplayCharacter] = []
    @State private var showAddSheet = false
    @State private var editMode: EditMode = .inactive

    // ナビゲーションバーの「？」で出す注釈
    @State private var showHelp = false

    private var visibleItems: [DisplayCharacter] { items.filter { !$0.isHidden } }
    private var hiddenItems:  [DisplayCharacter] { items.filter {  $0.isHidden } }

    var body: some View {
        ZStack {
            PuzzleBackground()
            List {
                Section {
                    Text("ドラッグで並び替え、目のアイコンで表示/非表示。使わないキャラは非表示にできます。右側の「ランク」欄にゲーム内のキャラランクを記入できます。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        // 背景画像の上では透けて読めなくなっていたため、行自体に不透明な
                        // 背景を持たせる（listRowBackgroundをColor.clearのままにはしない）。
                        .padding(.vertical, 4)
                        .listRowBackground(Color(uiColor: .secondarySystemBackground))
                }

                // ── 表示中 ──
                Section {
                    ForEach(visibleItems) { char in
                        charRow(char)
                    }
                    .onMove(perform: moveVisible)
                    .onDelete(perform: deleteVisible)
                } header: {
                    Text("表示中（\(visibleItems.count)件）")
                }

                // ── 非表示 ──
                if !hiddenItems.isEmpty {
                    Section {
                        ForEach(hiddenItems) { char in
                            charRow(char)
                        }
                        .onDelete(perform: deleteHidden)
                    } header: {
                        Text("非表示（\(hiddenItems.count)件）")
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .bongaNavigationBar(title: "キャラ管理")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.white)
                }
                .accessibilityLabel("この画面について")
                .popover(isPresented: $showHelp, arrowEdge: .top) {
                    helpContent
                        .presentationCompactAdaptation(.popover)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        withAnimation { editMode = editMode == .active ? .inactive : .active }
                    } label: {
                        Label(editMode == .active ? "並び替え終了" : "並び替え",
                              systemImage: "arrow.up.arrow.down")
                    }
                    Button { showAddSheet = true } label: {
                        Label("キャラを追加", systemImage: "plus")
                    }
                    Divider()
                    Button { sortByRole() } label: {
                        Label("ロール順にソート", systemImage: "person.3")
                    }
                    Button { sortByName() } label: {
                        Label("名前順にソート", systemImage: "textformat")
                    }
                    Button { sortByDefault() } label: {
                        Label("初期順に戻す", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.white)
                }
                .accessibilityLabel("キャラクターの並び替え・追加メニュー")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddCharacterSheet { name, role in
                addCustomChar(name: name, role: role)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: prefs) { _, _ in reload() }
    }

    // MARK: - 画面の注釈（？ボタンで表示）

    private var helpContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("この画面について")
                .font(.headline)
            helpRow("ドラッグで並び替え、目のアイコンで表示/非表示を切り替えられます。")
            helpRow("使わないキャラは非表示にしておくと、登録時の選択肢を絞れます。")
            helpRow("「ガールランク」欄でゲーム内の公式ランク（1〜150）を選べます。プロフィール画面でキャラ名をタップして選ぶのと同じデータです。")
            helpRow("右上の「…」からキャラの追加、ロール順/名前順/初期順への並び替えができます。")
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
    }

    private func helpRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("・")
            Text(text)
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    // MARK: - Row

    private func charRow(_ char: DisplayCharacter) -> some View {
        HStack(spacing: 12) {
            Button {
                toggleHidden(char)
            } label: {
                Image(systemName: char.isHidden ? "eye.slash" : "eye")
                    .foregroundColor(char.isHidden ? .secondary : .bongaCyan)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(char.isHidden ? "\(char.name)を表示する" : "\(char.name)を非表示にする")

            Image(systemName: char.role.iconName)
                .foregroundColor(.bongaPurple)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(char.name)
                    .foregroundColor(char.isHidden ? .secondary : .primary)
                    .strikethrough(char.isHidden)
                Text(char.role.label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()

            // ガールランク（ゲーム内の公式ランク。1〜150から選択。未設定なら1）
            VStack(alignment: .trailing, spacing: 1) {
                Text("ガールランク")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Picker("", selection: girlRankIntBinding(for: char.id)) {
                    ForEach(1...150, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 64)
            }

            if char.isCustom {
                Text("追加")
                    .font(.caption2)
                    .foregroundColor(Color.bongaCyanLight.readableForeground)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.bongaCyanLight)
                    .cornerRadius(4)
            }
        }
    }

    /// キャラごとのガールランクを直接読み書きするBinding（未登録なら初回選択時に作成）。
    /// 数値入力ではなく1〜150から選ぶ方式（実際の伸び幅が小さいため選択式の方が扱いやすい）。
    private func girlRankIntBinding(for charId: Int) -> Binding<Int> {
        Binding<Int>(
            get: {
                let raw = prefs.first(where: { $0.characterId == charId })?.girlRank
                return Int(raw ?? "") ?? 1
            },
            set: { newValue in
                let p = preference(for: charId)
                p.girlRank = String(min(max(newValue, 1), 150))
                save()
            }
        )
    }

    // MARK: - データ操作

    private func reload() {
        items = Catalog.resolvedCharacters(prefs: prefs, includeHidden: true)
    }

    private func preference(for charId: Int) -> CharacterPreference {
        if let p = prefs.first(where: { $0.characterId == charId }) { return p }
        let p = CharacterPreference(characterId: charId)
        context.insert(p)
        return p
    }

    private func toggleHidden(_ char: DisplayCharacter) {
        let p = preference(for: char.id)
        p.isHidden.toggle()
        save()
        reload()
    }

    private func moveVisible(from source: IndexSet, to destination: Int) {
        var visible = visibleItems
        visible.move(fromOffsets: source, toOffset: destination)
        for (index, item) in visible.enumerated() {
            let p = preference(for: item.id)
            p.sortOrder = index
            if item.isCustom { p.isCustom = true }
        }
        save()
        reload()
    }

    private func deleteVisible(at offsets: IndexSet) {
        let targets = offsets.map { visibleItems[$0] }
        deleteItems(targets)
    }

    private func deleteHidden(at offsets: IndexSet) {
        let targets = offsets.map { hiddenItems[$0] }
        deleteItems(targets)
    }

    private func deleteItems(_ targets: [DisplayCharacter]) {
        for item in targets {
            guard item.isCustom else { continue }
            if let p = prefs.first(where: { $0.characterId == item.id }) {
                context.delete(p)
            }
        }
        save()
        reload()
    }

    private func addCustomChar(name: String, role: CharacterRole) {
        let newId = Catalog.nextCustomCharId(existing: prefs)
        let maxOrder = (prefs.map { $0.sortOrder }.max() ?? items.count) + 1
        let p = CharacterPreference(characterId: newId,
                                    sortOrder: maxOrder,
                                    isHidden: false,
                                    isCustom: true,
                                    customName: name,
                                    customRoleRaw: role.rawValue)
        context.insert(p)
        save()
        reload()
    }

    private func sortByRole() {
        let sorted = items.sorted {
            $0.role.rawValue != $1.role.rawValue
            ? $0.role.rawValue < $1.role.rawValue
            : $0.name < $1.name
        }
        applyOrder(sorted)
    }

    private func sortByName() {
        applyOrder(items.sorted { $0.name < $1.name })
    }

    private func applyOrder(_ sorted: [DisplayCharacter]) {
        for (index, item) in sorted.enumerated() {
            let p = preference(for: item.id)
            p.sortOrder = index
            if item.isCustom { p.isCustom = true }
        }
        save()
        reload()
    }

    private func sortByDefault() {
        for p in prefs where !p.isCustom {
            p.sortOrder = p.characterId
        }
        save()
        reload()
    }

    private func save() { try? context.save() }
}

// MARK: - キャラ追加シート

private struct AddCharacterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role: CharacterRole = .bomber
    let onAdd: (String, CharacterRole) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("キャラ名") {
                    TextField("例：新キャラ", text: $name)
                }
                Section("ロール") {
                    Picker("ロール", selection: $role) {
                        ForEach(CharacterRole.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("キャラを追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        onAdd(name.trimmingCharacters(in: .whitespaces), role)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
