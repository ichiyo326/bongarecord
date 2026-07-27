import SwiftUI
import SwiftData

// MARK: - 練度基準の設定モデル

struct ProficiencyCriteria: Codable {
    var sGames: Int = 50;  var sRate: Int = 70
    var aGames: Int = 30;  var aRate: Int = 60
    var bGames: Int = 15;  var bRate: Int = 50
    var cGames: Int = 5

    static func load() -> ProficiencyCriteria {
        guard let data = UserDefaults.standard.data(forKey: "proficiencyCriteria"),
              let c = try? JSONDecoder().decode(ProficiencyCriteria.self, from: data)
        else { return ProficiencyCriteria() }
        return c
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "proficiencyCriteria")
        }
    }

    func rank(games: Int, wins: Int) -> String {
        guard games > 0 else { return "D" }
        let rate = Double(wins) / Double(games) * 100
        if games >= sGames && rate >= Double(sRate) { return "S" }
        if games >= aGames && rate >= Double(aRate) { return "A" }
        if games >= bGames && rate >= Double(bRate) { return "B" }
        if games >= cGames { return "C" }
        return "D"
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    // 太さ/色などテーマの変更をこの画面が生きている間もライブ反映するために保持。
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.modelContext) private var context
    @Query private var playerInfos: [PlayerInfo]
    @Query private var charPrefs: [CharacterPreference]
    @Query private var mapPrefs: [MapPreference]

    @State private var roleUsage: [CharacterRole: Double] = [:]
    @State private var displayChars: [DisplayCharacter] = []
    @State private var proficiencyMap: [Int: String] = [:]
    @State private var criteria = ProficiencyCriteria()
    @State private var showCriteriaSheet = false

    private var playerInfo: PlayerInfo {
        playerInfos.first ?? PlayerInfo()
    }

    var body: some View {
        ZStack {
            PuzzleBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // ── 上部：名前 + レーダー ──
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "プレイヤー名")
                            Text(playerInfo.name)
                                .font(.bongaEmphasis(.title2))
                                .padding(.bottom, 4)

                            Text(playerInfo.comment)
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color(uiColor: .systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color(uiColor: .systemGray4), lineWidth: 0.5)
                                )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(spacing: 4) {
                            SectionLabel(text: "ロール選択傾向")
                            RadarChartView(values: roleUsage)
                                .frame(width: 180, height: 180)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                                .background(Color(uiColor: .systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color(uiColor: .systemGray4), lineWidth: 0.5)
                                )
                        }
                    }
                    .padding(.horizontal).padding(.top, 8)

                    // ── お気に入りキャラ ──
                    let favChars = playerInfo.favoriteCharIds.filter { $0 != -1 }
                    if !favChars.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "お気に入りキャラ")
                            HStack(spacing: 12) {
                                ForEach(favChars, id: \.self) { charId in
                                    let name = Catalog.charName(byId: charId, prefs: charPrefs) ?? "?"
                                    let role = MasterData.character(byId: charId)?.role
                                    VStack(spacing: 4) {
                                        Image(systemName: role?.iconName ?? "questionmark")
                                            .font(.title3)
                                            .foregroundColor(.bongaPurple)
                                        Text(name)
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color(uiColor: .secondarySystemBackground))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // ── お気に入りマップ ──
                    let favMaps = playerInfo.favoriteMapIds.filter { $0 != -1 }
                    if !favMaps.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(text: "お気に入りマップ")
                            ForEach(favMaps, id: \.self) { mapId in
                                let name = Catalog.mapName(byId: mapId, prefs: mapPrefs) ?? "不明"
                                HStack {
                                    Image(systemName: "map")
                                        .foregroundColor(.bongaCyan)
                                    Text(name).font(.subheadline)
                                }
                                .padding(.vertical, 6).padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemBackground))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                    }

                    // ── キャラクター練度 ──
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SectionLabel(text: "キャラクター練度")
                            Spacer()
                            Button {
                                showCriteriaSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "gearshape")
                                    Text("基準設定")
                                }
                                .font(.caption)
                                .foregroundColor(.bongaPurple)
                            }
                        }
                        .padding(.horizontal)

                        // 現在の基準を表示
                        HStack(spacing: 10) {
                            criteriaLabel("S", "\(criteria.sGames)戦 \(criteria.sRate)%↑")
                            criteriaLabel("A", "\(criteria.aGames)戦 \(criteria.aRate)%↑")
                            criteriaLabel("B", "\(criteria.bGames)戦 \(criteria.bRate)%↑")
                            criteriaLabel("C", "\(criteria.cGames)戦↑")
                        }
                        .padding(.horizontal)

                        proficiencyGrid
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .bongaNavigationBar(title: "プロフィール")
        .task {
            criteria = ProficiencyCriteria.load()
            await computeStats()
        }
        .sheet(isPresented: $showCriteriaSheet) {
            ProficiencyCriteriaSheet(criteria: $criteria) {
                criteria.save()
                Task { await computeStats() }
            }
        }
    }

    // MARK: - Criteria Label

    private func criteriaLabel(_ rank: String, _ desc: String) -> some View {
        HStack(spacing: 2) {
            Text(rank)
                .font(.bongaEmphasis(.caption2))
                .foregroundColor(rankColor(rank))
            Text(desc)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        // 太字テキスト設定（Bold Text）が有効だと文字幅が広がり、4項目を並べたときに
        // 右端が画面外にはみ出したり折り返して崩れたりするため、各項目を均等幅にして
        // 収まらない場合は縮小するようにしておく。
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // SectionLabelと同じ理由（背景画像が透けて読みにくくなるのを防ぐため）不透明な下地を追加。
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(6)
    }

    // MARK: - Grid

    private var proficiencyGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 4)
        return LazyVGrid(columns: columns, spacing: 1) {
            ForEach(displayChars) { char in
                VStack(spacing: 0) {
                    Text(char.name)
                        .font(.caption2)
                        .foregroundColor(Color.bongaCyanLight.readableForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color.bongaCyanLight)
                    Text(proficiencyMap[char.id] ?? "D")
                        .font(.bongaEmphasis(.caption))
                        .foregroundColor(rankColor(proficiencyMap[char.id] ?? "D"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color(uiColor: .systemBackground))
                }
                .overlay(
                    Rectangle()
                        .stroke(Color(uiColor: .systemGray5), lineWidth: 0.5)
                )
            }
        }
    }

    private func rankColor(_ rank: String) -> Color {
        switch rank {
        case "S": return .yellow
        case "A": return .orange
        case "B": return .green
        case "C": return .bongaCyan
        default:  return .secondary
        }
    }

    // MARK: - Stats

    @MainActor
    private func computeStats() async {
        let chars = Catalog.resolvedCharacters(prefs: charPrefs)
        displayChars = chars

        var profMap: [Int: String] = [:]
        var roleCounts: [CharacterRole: Int] = [:]
        var grandTotal = 0

        for char in chars {
            let charId = char.id
            let totalDesc = FetchDescriptor<BattleRecord>(
                predicate: #Predicate { $0.characterId == charId }
            )
            let games = (try? context.fetchCount(totalDesc)) ?? 0

            let winsDesc = FetchDescriptor<BattleRecord>(
                predicate: #Predicate { $0.characterId == charId && $0.resultRaw == 0 }
            )
            let wins = (try? context.fetchCount(winsDesc)) ?? 0

            profMap[charId] = criteria.rank(games: games, wins: wins)
            roleCounts[char.role, default: 0] += games
            grandTotal += games
        }

        var usage: [CharacterRole: Double] = [:]
        if grandTotal > 0 {
            for role in CharacterRole.allCases {
                usage[role] = Double(roleCounts[role] ?? 0) / Double(grandTotal)
            }
        }

        proficiencyMap = profMap
        roleUsage = usage
    }
}

// MARK: - 基準設定シート

private struct ProficiencyCriteriaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var criteria: ProficiencyCriteria
    let onSave: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Sランク") {
                    HStack {
                        Text("試合数")
                        Spacer()
                        TextField("50", value: $criteria.sGames, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("戦以上")
                    }
                    HStack {
                        Text("勝率")
                        Spacer()
                        TextField("70", value: $criteria.sRate, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("% 以上")
                    }
                }
                Section("Aランク") {
                    HStack {
                        Text("試合数")
                        Spacer()
                        TextField("30", value: $criteria.aGames, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("戦以上")
                    }
                    HStack {
                        Text("勝率")
                        Spacer()
                        TextField("60", value: $criteria.aRate, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("% 以上")
                    }
                }
                Section("Bランク") {
                    HStack {
                        Text("試合数")
                        Spacer()
                        TextField("15", value: $criteria.bGames, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("戦以上")
                    }
                    HStack {
                        Text("勝率")
                        Spacer()
                        TextField("50", value: $criteria.bRate, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("% 以上")
                    }
                }
                Section("Cランク") {
                    HStack {
                        Text("試合数")
                        Spacer()
                        TextField("5", value: $criteria.cGames, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("戦以上")
                    }
                }
                Section {
                    Text("Dランク：上記に該当しないキャラ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("練度基準の設定")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }
}
