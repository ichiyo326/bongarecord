import SwiftUI
import SwiftData

/// マップの並び替え・非表示・追加・削除を行う管理画面。
struct MapManagementView: View {
    // 太さ/色などテーマの変更をこの画面が生きている間もライブ反映するために保持。
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.modelContext) private var context
    @Query private var prefs: [MapPreference]

    @State private var items: [DisplayMap] = []
    @State private var showAddSheet = false
    @State private var editMode: EditMode = .inactive

    private var visibleItems: [DisplayMap] { items.filter { !$0.isHidden } }
    private var hiddenItems:  [DisplayMap] { items.filter {  $0.isHidden } }

    var body: some View {
        ZStack {
            PuzzleBackground()
            List {
                Section {
                    Text("ドラッグで並び替え、目のアイコンで表示/非表示を切り替えできます。来ないステージは非表示に。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        // 背景画像の上では透けて読めなくなっていたため、行自体に不透明な
                        // 背景を持たせる（listRowBackgroundをColor.clearのままにはしない）。
                        .padding(.vertical, 4)
                        .listRowBackground(Color(uiColor: .secondarySystemBackground))
                }

                // ── 表示中 ──
                Section {
                    ForEach(visibleItems) { map in
                        mapRow(map)
                    }
                    .onMove(perform: moveVisible)
                    .onDelete(perform: deleteVisible)
                } header: {
                    Text("表示中（\(visibleItems.count)件）")
                }

                // ── 非表示 ──
                if !hiddenItems.isEmpty {
                    Section {
                        ForEach(hiddenItems) { map in
                            mapRow(map)
                        }
                        .onDelete(perform: deleteHidden)
                    } header: {
                        Text("非表示（\(hiddenItems.count)件）")
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .bongaNavigationBar(title: "マップ管理")
        .environment(\.editMode, $editMode)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        withAnimation { editMode = editMode == .active ? .inactive : .active }
                    } label: {
                        Label(editMode == .active ? "並び替え終了" : "並び替え",
                              systemImage: "arrow.up.arrow.down")
                    }
                    Button { showAddSheet = true } label: {
                        Label("マップを追加", systemImage: "plus")
                    }
                    Divider()
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
                .accessibilityLabel("マップの並び替え・追加メニュー")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddMapSheet { name, group in
                addCustomMap(name: name, group: group)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: prefs) { _, _ in reload() }
    }

    // MARK: - Row

    private func mapRow(_ map: DisplayMap) -> some View {
        HStack(spacing: 12) {
            Button {
                toggleHidden(map)
            } label: {
                Image(systemName: map.isHidden ? "eye.slash" : "eye")
                    .foregroundColor(map.isHidden ? .secondary : .bongaCyan)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(map.isHidden ? "\(map.name)を表示する" : "\(map.name)を非表示にする")

            VStack(alignment: .leading, spacing: 2) {
                Text(map.name)
                    .foregroundColor(map.isHidden ? .secondary : .primary)
                    .strikethrough(map.isHidden)
                Text(map.group)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if map.isCustom {
                Text("追加")
                    .font(.caption2)
                    .foregroundColor(Color.bongaCyanLight.readableForeground)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.bongaCyanLight)
                    .cornerRadius(4)
            }
        }
    }

    // MARK: - データ操作

    private func reload() {
        items = Catalog.resolvedMaps(prefs: prefs, includeHidden: true)
    }

    private func preference(for mapId: Int) -> MapPreference {
        if let p = prefs.first(where: { $0.mapId == mapId }) { return p }
        let p = MapPreference(mapId: mapId)
        context.insert(p)
        return p
    }

    private func toggleHidden(_ map: DisplayMap) {
        let p = preference(for: map.id)
        p.isHidden.toggle()
        if p.isCustom == false && map.isCustom { p.isCustom = true }
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

    private func deleteItems(_ targets: [DisplayMap]) {
        for item in targets {
            guard item.isCustom else { continue }
            if let p = prefs.first(where: { $0.mapId == item.id }) {
                context.delete(p)
            }
        }
        save()
        reload()
    }

    private func addCustomMap(name: String, group: String) {
        let newId = Catalog.nextCustomMapId(existing: prefs)
        let maxOrder = (prefs.map { $0.sortOrder }.max() ?? items.count) + 1
        let p = MapPreference(mapId: newId,
                              sortOrder: maxOrder,
                              isHidden: false,
                              isCustom: true,
                              customName: name,
                              customGroup: group.isEmpty ? "カスタム" : group)
        context.insert(p)
        save()
        reload()
    }

    private func sortByName() {
        let sorted = items.sorted { $0.name < $1.name }
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
            p.sortOrder = p.mapId
        }
        save()
        reload()
    }

    private func save() { try? context.save() }
}

// MARK: - マップ追加シート

private struct AddMapSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var group = ""
    let onAdd: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("マップ名") {
                    TextField("例：新マップ1", text: $name)
                }
                Section("グループ（任意）") {
                    TextField("例：新エリア", text: $group)
                }
            }
            .navigationTitle("マップを追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        onAdd(name.trimmingCharacters(in: .whitespaces), group)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
