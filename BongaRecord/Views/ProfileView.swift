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
//
// ユーザーが共有した「紙の履歴書」テンプレート（プロフィール記入欄＋キャラをロール別に
// 並べてランクを記す一覧）を参考にしたレイアウト。実在のロゴ・キャラクターイラストは
// 使わず、クリーム紙・黒枠・マスキングテープ風の装飾をSwiftUIの図形描画のみで再現している
// （パーツは Components/PaperCraftComponents.swift）。
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

    // ガールランク（ゲーム内公式ランクの自己記録）をこの画面から直接編集するための状態
    @State private var editingCharId: Int? = nil
    @State private var editingRankValue: Int = 1

    // ナビゲーションバー右端の「？」で出す注釈
    @State private var showHelp = false

    private var playerInfo: PlayerInfo {
        playerInfos.first ?? PlayerInfo()
    }

    /// 「好きなガール」欄：お気に入りキャラ（最大4件）を「、」区切りの一つの回答として見せる
    private var favoriteCharText: String {
        playerInfo.favoriteCharIds
            .filter { $0 != -1 }
            .compactMap { Catalog.charName(byId: $0, prefs: charPrefs) }
            .joined(separator: "、")
    }

    /// 「クラス・レート」欄
    private var classRateText: String {
        var parts: [String] = []
        if !playerInfo.rateText.isEmpty { parts.append(playerInfo.rateText) }
        parts.append(playerInfo.playClassLabel)
        return parts.joined(separator: " / ")
    }

    /// お気に入りキャラのIDセット（キャラクター練度グリッドでハート表示に使う）
    private var favoriteCharIdSet: Set<Int> {
        Set(playerInfo.favoriteCharIds.filter { $0 != -1 })
    }

    var body: some View {
        ZStack {
            PuzzleBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    profileFieldsGrid

                    commentCard

                    HStack(alignment: .top, spacing: 4) {
                        radarCard
                        if !favoriteMapNames.isEmpty {
                            favoriteMapCard
                        }
                    }

                    characterGridCard
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
        }
        .bongaNavigationBar(title: "プロフィール")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.white)
                }
                .accessibilityLabel("このプロフィール画面について")
                .popover(isPresented: $showHelp, arrowEdge: .top) {
                    helpContent
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
        .task {
            criteria = ProficiencyCriteria.load()
            await computeStats()
        }
        .onChange(of: charPrefs) { _, _ in
            Task { await computeStats() }
        }
        .sheet(isPresented: $showCriteriaSheet) {
            ProficiencyCriteriaSheet(criteria: $criteria) {
                criteria.save()
                Task { await computeStats() }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { editingCharId != nil },
                set: { if !$0 { editingCharId = nil } }
            )
        ) {
            GirlRankPickerSheet(charName: editingCharName, rank: $editingRankValue) {
                if let id = editingCharId { saveGirlRank(charId: id, rank: editingRankValue) }
                editingCharId = nil
            } onCancel: {
                editingCharId = nil
            }
            .presentationDetents([.height(280)])
        }
    }

    private var editingCharName: String {
        guard let id = editingCharId else { return "ガールランクを編集" }
        return displayChars.first(where: { $0.id == id })?.name ?? "ガールランクを編集"
    }

    // MARK: - 画面の注釈（？ボタンで表示）

    private var helpContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("この画面について")
                .font(.headline)
            helpRow("プレイヤーネーム・クラス・レート・好きなガール・目標は「編集」→「プレイヤー情報」から変更できます。")
            helpRow("キャラ名をタップすると、そのキャラのガールランク（1〜150）を選べます。")
            helpRow("ハートは「好きなガール」に選んだキャラです。")
            helpRow("カードの背景色はガールランクの節目に応じて変わります。")
            helpRow("バッジ（S/A/B/C/D）は勝率から自動判定される練度です。基準は右上の「基準設定」から調整できます。")
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
    }

    private func helpRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("・")
            Text(text)
        }
        .font(.caption)
        .foregroundColor(.secondary)
    }

    private func beginEditingGirlRank(_ char: DisplayCharacter) {
        editingCharId = char.id
        editingRankValue = Int(char.girlRank) ?? 1
    }

    private func saveGirlRank(charId: Int, rank: Int) {
        let normalized = Catalog.normalizedGirlRank(String(rank))
        if let existing = charPrefs.first(where: { $0.characterId == charId }) {
            existing.girlRank = normalized
        } else {
            let p = CharacterPreference(characterId: charId, girlRank: normalized)
            context.insert(p)
        }
        try? context.save()
        Task { await computeStats() }
    }

    // MARK: - プロフィール記入欄（2×2）

    private var profileFieldsGrid: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                PaperField(label: "プレイヤーネーム", value: playerInfo.name)
                PaperField(label: "クラス・レート", value: classRateText)
            }
            HStack(spacing: 4) {
                PaperField(label: "好きなガール", value: favoriteCharText)
                PaperField(label: "目標", value: playerInfo.goal)
            }
        }
    }

    // MARK: - 何か書いとけ（自由記入）

    private var commentCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            PaperFieldLabel(text: "何か書いとけ", compact: true)
            Text(playerInfo.comment.isEmpty ? "（未入力）" : playerInfo.comment)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.black)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .paperCard(tint: PaperPalette.yellow)
    }

    // MARK: - ロール選択傾向（レーダーチャート）

    private var radarCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            PaperFieldLabel(text: "ロール選択傾向", compact: true)
            RadarChartView(values: roleUsage)
                .frame(height: 100)
                .foregroundColor(.black)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .paperCard()
    }

    // MARK: - お気に入りマップ

    private var favoriteMapNames: [String] {
        playerInfo.favoriteMapIds
            .filter { $0 != -1 }
            .compactMap { Catalog.mapName(byId: $0, prefs: mapPrefs) }
    }

    private var favoriteMapCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            PaperFieldLabel(text: "お気に入りマップ", compact: true)
            VStack(spacing: 2) {
                ForEach(favoriteMapNames, id: \.self) { name in
                    HStack(spacing: 4) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.bongaPurple)
                        Text(name)
                            .font(.system(size: 10))
                            .foregroundColor(.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(PaperPalette.paperShade)
                    .cornerRadius(4)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .paperCard()
    }

    // MARK: - キャラクター練度（ロール別4列・参考画像の並びに寄せた形）
    //
    // 参考にした紙の履歴書は「ロールごとに列を並べる」構成だったため、ロールを
    // セクションとして縦に積むのではなく、4列を横に並べて1枚にまとめている。
    // 列の高さはロールごとの人数で自然に変わる（参考画像の不揃いな列と同じ考え方）。

    private let roleTagColors: [CharacterRole: Color] = [
        .bomber:   Color(red: 0.95, green: 0.47, blue: 0.22),
        .attacker: Color(red: 0.86, green: 0.26, blue: 0.38),
        .shooter:  Color(red: 0.20, green: 0.55, blue: 0.86),
        .blocker:  Color(red: 0.34, green: 0.64, blue: 0.40)
    ]

    private var characterGridCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                PaperFieldLabel(text: "キャラクター練度（ロール別）", compact: true)
                Spacer()
                Button {
                    showCriteriaSheet = true
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "gearshape")
                        Text("基準設定")
                    }
                    .font(.system(size: 9))
                    .foregroundColor(.bongaPurple)
                }
            }

            HStack(spacing: 4) {
                criteriaLabel("S", "\(criteria.sGames)戦\(criteria.sRate)%↑")
                criteriaLabel("A", "\(criteria.aGames)戦\(criteria.aRate)%↑")
                criteriaLabel("B", "\(criteria.bGames)戦\(criteria.bRate)%↑")
                criteriaLabel("C", "\(criteria.cGames)戦↑")
            }

            Text("バッジは勝率から自動判定。キャラ名タップでゲーム内ランクを記録。")
                .font(.system(size: 7.5))
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 4) {
                ForEach(CharacterRole.allCases) { role in
                    roleColumn(role)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .paperCard(tint: PaperPalette.paperShade)
    }

    private func criteriaLabel(_ rank: String, _ desc: String) -> some View {
        HStack(spacing: 2) {
            RankBadgeChip(rank: rank, size: 12)
            Text(desc)
                .font(.system(size: 7.5))
                .foregroundColor(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(4)
    }

    /// ロール1列分（見出しタグ＋キャラを縦に並べたミニカードの積み重ね）。
    /// 並び順は「キャラ管理」でのユーザー並び替えに関わらず、常にマスターの初期順（ID順）。
    @ViewBuilder
    private func roleColumn(_ role: CharacterRole) -> some View {
        let chars = displayChars.filter { $0.role == role }.sorted { $0.id < $1.id }
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Image(systemName: role.iconName)
                    .font(.system(size: 8))
                Text(role.label)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(roleTagColors[role] ?? .bongaPurple)
            .cornerRadius(4)

            ForEach(chars) { char in
                Button {
                    beginEditingGirlRank(char)
                } label: {
                    VStack(spacing: 1) {
                        HStack(spacing: 2) {
                            if favoriteCharIdSet.contains(char.id) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 6))
                                    .foregroundColor(.pink)
                            }
                            Text(char.name)
                                .font(.system(size: 8))
                                .foregroundColor(.black)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                        }
                        HStack(spacing: 2) {
                            RankBadgeChip(rank: proficiencyMap[char.id] ?? "D", size: 12)
                            // ガールランク入力欄（タップで編集）。常に表示し、未設定は1。
                            Text(char.girlRank)
                                .font(.system(size: 7, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.bongaPurple)
                                .cornerRadius(3)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .paperCard(tint: girlRankBandColor(Int(char.girlRank) ?? 1), corner: 3, lineWidth: 0.6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - ガールランクの節目による背景色分け
    //
    // 指定された境目（21, 36, 50, 68, 85, 99, 107, 111, 115, 120, 129, 135, 138, 141,
    // 144, 147, 150）でランクを18段階の帯に分け、段階が上がるほど色が変わっていく。
    // 文字は常に黒（PaperField等と同じ）なので、彩度・明度は読みやすいパステル域に収めている。

    private static let girlRankBandThresholds = [21, 36, 50, 68, 85, 99, 107, 111, 115, 120, 129, 135, 138, 141, 144, 147, 150]

    private func girlRankBandIndex(_ rank: Int) -> Int {
        ProfileView.girlRankBandThresholds.filter { rank >= $0 }.count
    }

    private func girlRankBandColor(_ rank: Int) -> Color {
        let clamped = min(max(rank, 1), 150)
        let maxIndex = Double(ProfileView.girlRankBandThresholds.count) // 17
        let t = Double(girlRankBandIndex(clamped)) / maxIndex           // 0.0 (低ランク) 〜 1.0 (150)

        // 青 → 緑 → 黄 → 橙 → 赤 → ピンク/ゴールドへと色相を回し、
        // 上位帯ほど彩度も少しずつ乗せていく（ただし黒文字が沈まないパステル域まで）。
        let hue = (0.60 - t * 0.68).truncatingRemainder(dividingBy: 1.0)
        let normalizedHue = hue < 0 ? hue + 1.0 : hue
        let saturation = 0.22 + t * 0.45
        let brightness = 0.97 - t * 0.10
        return Color(hue: normalizedHue, saturation: saturation, brightness: brightness)
    }

    // MARK: - Stats

    @MainActor
    private func computeStats() async {
        // プロフィール画面は「キャラ管理」で非表示にしたキャラも含めて練度を見せる
        // （非表示は戦績登録の選択肢を絞るための設定であり、練度一覧からも消す意図ではないため）。
        let chars = Catalog.resolvedCharacters(prefs: charPrefs, includeHidden: true)
        displayChars = chars

        let startedAt = CFAbsoluteTimeGetCurrent()

        // 旧実装: MainActor上でcontext.fetchCountをキャラ数×2回、直列に叩いていた。
        // 新実装: 独立したModelActorのプールに分散し、実際に並列でSQLiteを読む。
        // container自体はMainActor上のcontextから取り出すだけ（これは安全。
        // ModelContainerそのものはSendableで、複数actorから共有してよい設計になっている）。
        let container = context.container
        let charIds = chars.map(\.id)

        let stats: [ProficiencyCalculator.CharacterStat]
        do {
            stats = try await ProficiencyCalculatorPool.computeAll(
                container: container,
                charIds: charIds,
                poolSize: 4
            )
        } catch {
            stats = []
        }

        let elapsedMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        #if DEBUG
        print("[ProfileView] computeStats: \(chars.count)キャラ / \(String(format: "%.1f", elapsedMs))ms")
        #endif

        let statByCharId = Dictionary(uniqueKeysWithValues: stats.map { ($0.charId, $0) })

        var profMap: [Int: String] = [:]
        var roleCounts: [CharacterRole: Int] = [:]
        var grandTotal = 0

        for char in chars {
            let stat = statByCharId[char.id]
            let games = stat?.games ?? 0
            let wins = stat?.wins ?? 0

            profMap[char.id] = criteria.rank(games: games, wins: wins)
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

// MARK: - ガールランク選択シート（数字入力ではなくホイールで選ぶ）

private struct GirlRankPickerSheet: View {
    let charName: String
    @Binding var rank: Int
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Picker("ガールランク", selection: $rank) {
                ForEach(1...150, id: \.self) { n in
                    Text("\(n)").tag(n)
                }
            }
            .pickerStyle(.wheel)
            .navigationTitle(charName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { onSave() }
                }
            }
        }
    }
}
