import SwiftUI
import SwiftData

struct BattleRegistrationView: View {
    @Environment(\.modelContext) private var context
    @Query private var mapPrefs: [MapPreference]
    @Query private var charPrefs: [CharacterPreference]
    @Query private var playerInfos: [PlayerInfo]
    // 太さ/色などテーマの変更をこの画面が生きている間もライブ反映するために保持。
    @ObservedObject private var theme = ThemeManager.shared

    @State private var selectedMapId: Int       = MasterData.maps.first?.id       ?? 0
    @State private var selectedCharacterId: Int = MasterData.characters.first?.id ?? 0
    @State private var result: BattleResult     = .win
    @State private var showSavedAlert           = false
    @State private var saveError: String?       = nil

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

                    PrimaryButton(title: "登録") {
                        saveRecord()
                    }
                    .padding(.horizontal).padding(.top, 12)
                }
            }
        }
        .bongaNavigationBar(title: "勝敗登録")
        .onAppear {
            // 選択中が非表示/不在なら、表示中の先頭に補正
            let maps = Catalog.resolvedMaps(prefs: mapPrefs)
            if !maps.contains(where: { $0.id == selectedMapId }), let first = maps.first {
                selectedMapId = first.id
            }
            let chars = Catalog.resolvedCharacters(prefs: charPrefs)
            if !chars.contains(where: { $0.id == selectedCharacterId }), let first = chars.first {
                selectedCharacterId = first.id
            }
        }
        .alert("登録しました", isPresented: $showSavedAlert) {
            Button("OK") { }
        }
        .alert("登録失敗", isPresented: .constant(saveError != nil), presenting: saveError) { _ in
            Button("OK") { saveError = nil }
        } message: { message in
            Text(message)
        }
    }

    private func saveRecord() {
        // ランク機能ON時は、記録時点の現在ランクをスタンプ
        let pi = playerInfos.first
        let stampRank: PlayerRank? = (pi?.rankTrackingEnabled == true) ? pi?.currentRank : nil

        let record = BattleRecord(date: Date(),
                                   mapId: selectedMapId,
                                   characterId: selectedCharacterId,
                                   result: result,
                                   rank: stampRank)
        context.insert(record)
        do {
            try context.save()
            showSavedAlert = true
        } catch {
            saveError = error.localizedDescription
        }
    }
}

// MARK: - Map Picker Field（カスタマイズ反映：非表示除外・並び順尊重）

struct MapPickerField: View {
    @Binding var selectionId: Int
    @Query private var mapPrefs: [MapPreference]

    var body: some View {
        let maps = Catalog.resolvedMaps(prefs: mapPrefs)        // 非表示除外＆並び順済み
        let groups = Catalog.resolvedMapGroups(maps)
        Menu {
            ForEach(groups, id: \.self) { groupName in
                let mapsInGroup = maps.filter { $0.group == groupName }
                Section(header: Text(groupName)) {
                    ForEach(mapsInGroup) { map in
                        Button(map.name) { selectionId = map.id }
                    }
                }
            }
        } label: {
            HStack {
                Text(Catalog.mapName(byId: selectionId, prefs: mapPrefs) ?? "未選択")
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Character Picker Field（カスタマイズ反映：非表示除外・並び順尊重）

struct CharacterPickerField: View {
    @Binding var selectionId: Int
    @Query private var charPrefs: [CharacterPreference]

    var body: some View {
        let chars = Catalog.resolvedCharacters(prefs: charPrefs)
        Menu {
            ForEach(CharacterRole.allCases) { role in
                let inRole = chars.filter { $0.role == role }
                if !inRole.isEmpty {
                    Section(header: Text(role.label)) {
                        ForEach(inRole) { char in
                            Button {
                                selectionId = char.id
                            } label: {
                                Label(char.name, systemImage: char.role.iconName)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack {
                if let name = Catalog.charName(byId: selectionId, prefs: charPrefs) {
                    let customRaw = charPrefs.first(where: { $0.characterId == selectionId })?.customRoleRaw ?? 0
                    let role = MasterData.character(byId: selectionId)?.role
                        ?? CharacterRole(rawValue: customRaw)
                        ?? .bomber
                    Image(systemName: role.iconName)
                        .foregroundColor(.secondary)
                    Text(name)
                        .foregroundColor(.primary)
                } else {
                    Text("未選択").foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundColor(.secondary)
            }
        }
    }
}
