import SwiftUI
import SwiftData

struct BattleStatsView: View {
    // 太さ/色などテーマの変更をこの画面が生きている間もライブ反映するために保持。
    // これが無いと、SwiftUIはこの画面のbodyを再評価するきっかけを持てず、
    // 一度表示した後にテーマ設定を変えても、この画面に戻るまで反映されなかった。
    @ObservedObject private var theme = ThemeManager.shared
    @Environment(\.modelContext) private var context
    @Query private var mapPrefs: [MapPreference]
    @Query private var charPrefs: [CharacterPreference]
    @Query private var playerInfos: [PlayerInfo]

    private var rankEnabled: Bool { playerInfos.first?.rankTrackingEnabled == true }

    @State private var startDate: Date?         = nil
    @State private var endDate: Date?           = nil

    // 複数選択フィルタ（空 = 指定なし）
    @State private var filterMapIds: Set<Int>       = []
    @State private var filterCharacterIds: Set<Int> = []
    @State private var filterRoles: Set<CharacterRole> = []
    @State private var filterRanks: Set<PlayerRank> = []

    @State private var totalGames: Int = 0
    @State private var totalWins: Int  = 0
    @State private var totalLosses: Int = 0
    @State private var totalDraws: Int = 0
    @State private var aggregated: [AggregatedStat] = []
    @State private var roleStats: [RoleStat] = []
    @State private var hasSearched = false
    @State private var didAutoLoad = false

    /// 検索条件フォームの開閉。デフォルトは閉じて結果を広く見せる
    @State private var showFilter = false

    // 結果の表示形式
    enum ViewMode: String, CaseIterable, Identifiable {
        case list     = "リスト"
        case calendar = "カレンダー"
        var id: String { rawValue }
    }
    @State private var viewMode: ViewMode = .list

    // 結果の集計単位
    enum GroupUnit: String, CaseIterable, Identifiable {
        case character    = "ガール別"
        case map          = "マップ別"
        case characterMap = "ガール×マップ"
        case rank         = "ランク別"
        var id: String { rawValue }
    }
    @State private var groupUnit: GroupUnit = .character

    // 結果テーブルの並び替え
    enum SortKey: String, CaseIterable, Identifiable {
        case name    = "名前順"
        case winRate = "勝率順"
        case games   = "試合数順"
        case diff    = "差分順"
        var id: String { rawValue }
    }
    @State private var sortKey: SortKey = .name

    enum QuickRange { case today, week, month, all }

    // MARK: - Value型

    struct AggregatedStat: Identifiable {
        let id = UUID()
        let characterId: Int?
        let role: CharacterRole?
        let primary: String          // 主ラベル（ガール名 or マップ名）
        let secondary: String?       // 副ラベル（ガール×マップ時のマップ名）
        let games: Int
        let wins: Int
        let losses: Int
        var sortHint: Int = 0        // 名前順での並び基準（ランク別はランク強度。大きいほど上）
        var draws: Int { max(0, games - wins - losses) }
        var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }
        var diff: Int { wins - losses }
    }

    struct RoleStat: Identifiable {
        let id = UUID()
        let role: CharacterRole
        let games: Int
        let wins: Int
        let losses: Int
        var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }
        var diff: Int { wins - losses }
    }

    var body: some View {
        ZStack {
            PuzzleBackground()

            VStack(spacing: 0) {
                // 検索条件の開閉トグルバー
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showFilter.toggle() }
                } label: {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .accessibilityHidden(true)
                        Text("検索条件").font(.bongaEmphasis(.subheadline))
                        Spacer()
                        Image(systemName: showFilter ? "chevron.up" : "chevron.down")
                            .accessibilityHidden(true)
                    }
                    .foregroundColor(.bongaPurple)
                    .padding(.horizontal).padding(.vertical, 12)
                    .background(Color(uiColor: .secondarySystemBackground))
                }
                .accessibilityLabel("検索条件")
                .accessibilityValue(showFilter ? "展開中" : "折りたたみ中")

                if showFilter {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            // クイック期間
                            quickRangeBar
                                .padding(.horizontal).padding(.top, 8)

                            // 日付期間
                            SectionLabel(text: "日付")
                                .padding(.horizontal).padding(.top, 4)
                            HStack(spacing: 8) {
                                FormCard {
                                    OptionalDateField(date: $startDate, placeholder: "タップして日付入力")
                                }
                                Text("〜").foregroundColor(.secondary)
                                FormCard {
                                    OptionalDateField(date: $endDate, placeholder: "タップして日付入力")
                                }
                            }
                            .padding(.horizontal)

                            // 対戦マップ（複数選択）
                            SectionLabel(text: "対戦マップ（複数選択可）")
                                .padding(.horizontal).padding(.top, 6)
                            FormCard {
                                let maps = Catalog.resolvedMaps(prefs: mapPrefs)
                                let groups = Catalog.resolvedMapGroups(maps)
                                Menu {
                                    Button {
                                        filterMapIds.removeAll()
                                    } label: {
                                        Label("すべて解除", systemImage: filterMapIds.isEmpty ? "checkmark" : "")
                                    }
                                    ForEach(groups, id: \.self) { group in
                                        Section(header: Text(group)) {
                                            ForEach(maps.filter { $0.group == group }) { m in
                                                Button {
                                                    toggle(&filterMapIds, m.id)
                                                } label: {
                                                    Label(m.name,
                                                          systemImage: filterMapIds.contains(m.id) ? "checkmark" : "")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    filterMenuLabel(
                                        selectedCount: filterMapIds.count,
                                        noneText: "（指定なし）",
                                        oneText: filterMapIds.count == 1
                                            ? Catalog.mapName(byId: filterMapIds.first!, prefs: mapPrefs)
                                            : nil)
                                }
                            }
                            .padding(.horizontal)

                            // 使用キャラ（複数選択）
                            SectionLabel(text: "使用キャラ（複数選択可）")
                                .padding(.horizontal).padding(.top, 6)
                            FormCard {
                                let chars = Catalog.resolvedCharacters(prefs: charPrefs)
                                Menu {
                                    Button {
                                        filterCharacterIds.removeAll()
                                    } label: {
                                        Label("すべて解除", systemImage: filterCharacterIds.isEmpty ? "checkmark" : "")
                                    }
                                    ForEach(CharacterRole.allCases) { role in
                                        let inRole = chars.filter { $0.role == role }
                                        if !inRole.isEmpty {
                                            Section(header: Text(role.label)) {
                                                ForEach(inRole) { c in
                                                    Button {
                                                        toggle(&filterCharacterIds, c.id)
                                                    } label: {
                                                        Label(c.name,
                                                              systemImage: filterCharacterIds.contains(c.id) ? "checkmark" : "")
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    filterMenuLabel(
                                        selectedCount: filterCharacterIds.count,
                                        noneText: "（指定なし）",
                                        oneText: filterCharacterIds.count == 1
                                            ? Catalog.charName(byId: filterCharacterIds.first!, prefs: charPrefs)
                                            : nil)
                                }
                            }
                            .padding(.horizontal)

                            // ロール限定（複数選択）
                            SectionLabel(text: "ロールで限定")
                                .padding(.horizontal).padding(.top, 6)
                            FormCard {
                                Menu {
                                    Button {
                                        filterRoles.removeAll()
                                    } label: {
                                        Label("すべて解除", systemImage: filterRoles.isEmpty ? "checkmark" : "")
                                    }
                                    ForEach(CharacterRole.allCases) { role in
                                        Button {
                                            toggleRole(role)
                                        } label: {
                                            Label(role.label,
                                                  systemImage: filterRoles.contains(role) ? "checkmark" : "")
                                        }
                                    }
                                } label: {
                                    filterMenuLabel(
                                        selectedCount: filterRoles.count,
                                        noneText: "（指定なし）",
                                        oneText: filterRoles.count == 1 ? filterRoles.first!.label : nil)
                                }
                            }
                            .padding(.horizontal)

                            // ランクで限定（複数選択・ランク機能ON時のみ）
                            if rankEnabled {
                                SectionLabel(text: "ランクで限定（複数選択可）")
                                    .padding(.horizontal).padding(.top, 6)
                                FormCard {
                                    Menu {
                                        Button {
                                            filterRanks.removeAll()
                                        } label: {
                                            Label("すべて解除", systemImage: filterRanks.isEmpty ? "checkmark" : "")
                                        }
                                        ForEach(PlayerRank.allCases.reversed()) { rank in
                                            Button {
                                                toggleRank(rank)
                                            } label: {
                                                Label(rank.label,
                                                      systemImage: filterRanks.contains(rank) ? "checkmark" : "")
                                            }
                                        }
                                    } label: {
                                        filterMenuLabel(
                                            selectedCount: filterRanks.count,
                                            noneText: "（指定なし）",
                                            oneText: filterRanks.count == 1 ? filterRanks.first!.label : nil)
                                    }
                                }
                                .padding(.horizontal)
                            }

                        }
                        .padding(.vertical, 8)
                        // フィルタフォーム全体を不透明な地に乗せる。個々のSectionLabelだけ
                        // 直しても「他にも透けている場所」がいたちごっこになるため、
                        // フォーム領域ごとまとめて不透明化して背景画像の影響を断つ。
                        .background(Color(uiColor: .systemBackground))
                    }

                    PrimaryButton(title: "戦績を検索") {
                        runSearch()
                        withAnimation(.easeInOut(duration: 0.2)) { showFilter = false }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }

                Divider()

                // 下部：結果（独立スクロール）
                if hasSearched {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            summaryView
                                .padding(.top, 10).padding(.horizontal)

                            viewModeBar
                                .padding(.top, 10).padding(.horizontal)

                            switch viewMode {
                            case .list:
                                if !roleStats.isEmpty {
                                    roleStatsView
                                        .padding(.top, 10).padding(.horizontal)
                                }

                                groupUnitBar
                                    .padding(.top, 10).padding(.horizontal)

                                sortBar
                                    .padding(.top, 8).padding(.horizontal)

                                resultsTable
                                    .padding(.top, 8)

                            case .calendar:
                                CalendarStatsView(
                                    mapIds: filterMapIds,
                                    characterIds: filterCharacterIds,
                                    roles: filterRoles,
                                    onSelectDay: { day in
                                        startDate = day
                                        endDate = day
                                        viewMode = .list
                                        runSearch()
                                    }
                                )
                                .padding(.top, 16)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                } else {
                    VStack(spacing: 8) {
                        Text("「戦績を検索」で結果を表示")
                            .font(.subheadline)
                        Text("条件変更は上部の「検索条件」をタップ")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .bongaNavigationBar(title: "戦績表示")
        .onAppear {
            // 初回表示時は「今日」をデフォルトで自動検索
            if !didAutoLoad {
                didAutoLoad = true
                setRange(.today)
            }
        }
    }

    // MARK: - フィルタ補助

    private func toggle(_ set: inout Set<Int>, _ id: Int) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }
    private func toggleRole(_ role: CharacterRole) {
        if filterRoles.contains(role) { filterRoles.remove(role) } else { filterRoles.insert(role) }
    }
    private func toggleRank(_ rank: PlayerRank) {
        if filterRanks.contains(rank) { filterRanks.remove(rank) } else { filterRanks.insert(rank) }
    }

    @ViewBuilder
    private func filterMenuLabel(selectedCount: Int, noneText: String, oneText: String?) -> some View {
        HStack {
            Text(selectedCount == 0 ? noneText
                 : (selectedCount == 1 ? (oneText ?? "1件選択") : "\(selectedCount)件選択"))
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.down").foregroundColor(.secondary)
        }
    }

    // MARK: - クイック期間

    private var quickRangeBar: some View {
        HStack(spacing: 8) {
            quickButton("今日",  .today)
            quickButton("今週",  .week)
            quickButton("今月",  .month)
            quickButton("全期間", .all)
        }
    }

    private func quickButton(_ title: String, _ kind: QuickRange) -> some View {
        Button {
            setRange(kind)
            withAnimation(.easeInOut(duration: 0.2)) { showFilter = false }
        } label: {
            Text(title)
                .font(.bongaEmphasis(.caption))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.bongaPurple.opacity(0.22))
                .foregroundColor(.bongaPurple)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.bongaPurple.opacity(0.5), lineWidth: 1)
                )
                .cornerRadius(8)
        }
    }

    private func setRange(_ kind: QuickRange) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        switch kind {
        case .today:
            startDate = today
            endDate = today
        case .week:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)
            startDate = cal.date(from: comps) ?? today
            endDate = today
        case .month:
            let comps = cal.dateComponents([.year, .month], from: today)
            startDate = cal.date(from: comps) ?? today
            endDate = today
        case .all:
            startDate = nil
            endDate = nil
        }
        runSearch()
    }

    // MARK: - Search

    private func runSearch() {
        var startTs: Int64 = .min
        var endTs:   Int64 = .max
        let cal = Calendar.current
        if let s = startDate {
            startTs = Int64(cal.startOfDay(for: s).timeIntervalSince1970)
        }
        if let e = endDate {
            let nextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: e)) ?? e
            endTs = Int64(nextDay.timeIntervalSince1970)
        }

        // 日付だけSQLで絞る（複数選択・ロールはメモリ側で。フィルタ後は少件数の前提）
        let predicate: Predicate<BattleRecord> = #Predicate { r in
            r.dateTimestamp >= startTs && r.dateTimestamp < endTs
        }
        let descriptor = FetchDescriptor<BattleRecord>(predicate: predicate)
        var matched = (try? context.fetch(descriptor)) ?? []

        if !filterMapIds.isEmpty {
            matched = matched.filter { filterMapIds.contains($0.mapId) }
        }
        if !filterCharacterIds.isEmpty {
            matched = matched.filter { filterCharacterIds.contains($0.characterId) }
        }
        if !filterRoles.isEmpty {
            matched = matched.filter { r in
                guard let role = MasterData.character(byId: r.characterId)?.role else { return false }
                return filterRoles.contains(role)
            }
        }
        if !filterRanks.isEmpty {
            matched = matched.filter { r in
                guard let rank = r.rank else { return false }
                return filterRanks.contains(rank)
            }
        }

        rebuildAggregation(from: matched)

        // ロール別集計
        var roleAgg: [CharacterRole: (games: Int, wins: Int, losses: Int)] = [:]
        for r in matched {
            guard let role = MasterData.character(byId: r.characterId)?.role else { continue }
            var e = roleAgg[role] ?? (games: 0, wins: 0, losses: 0)
            e.games += 1
            switch r.result {
            case .win:  e.wins += 1
            case .lose: e.losses += 1
            case .draw: break
            }
            roleAgg[role] = e
        }
        roleStats = CharacterRole.allCases.compactMap { role in
            guard let e = roleAgg[role], e.games > 0 else { return nil }
            return RoleStat(role: role, games: e.games, wins: e.wins, losses: e.losses)
        }

        totalGames  = matched.count
        totalWins   = matched.filter { $0.result == .win }.count
        totalLosses = matched.filter { $0.result == .lose }.count
        totalDraws  = matched.filter { $0.result == .draw }.count
        hasSearched = true
    }

    /// 現在の集計単位 `groupUnit` に従って matched を集計し直す
    private func rebuildAggregation(from matched: [BattleRecord]) {
        struct Bucket { var cid: Int?; var role: CharacterRole?; var primary: String; var secondary: String?; var games = 0; var wins = 0; var losses = 0; var sortHint = 0 }
        var groups: [String: Bucket] = [:]

        for r in matched {
            let key: String
            var seed: Bucket
            switch groupUnit {
            case .character:
                key = "c\(r.characterId)"
                seed = Bucket(cid: r.characterId,
                              role: MasterData.character(byId: r.characterId)?.role,
                              primary: Catalog.charName(byId: r.characterId, prefs: charPrefs) ?? "不明",
                              secondary: nil)
            case .map:
                key = "m\(r.mapId)"
                seed = Bucket(cid: nil, role: nil,
                              primary: Catalog.mapName(byId: r.mapId, prefs: mapPrefs) ?? "不明",
                              secondary: nil)
            case .characterMap:
                key = "c\(r.characterId)-m\(r.mapId)"
                seed = Bucket(cid: r.characterId,
                              role: MasterData.character(byId: r.characterId)?.role,
                              primary: Catalog.charName(byId: r.characterId, prefs: charPrefs) ?? "不明",
                              secondary: Catalog.mapName(byId: r.mapId, prefs: mapPrefs) ?? "不明")
            case .rank:
                if let rank = r.rank {
                    key = "r\(rank.rawValue)"
                    seed = Bucket(cid: nil, role: nil, primary: rank.label, secondary: nil, sortHint: rank.rawValue)
                } else {
                    key = "r-none"
                    seed = Bucket(cid: nil, role: nil, primary: "ランク未記録", secondary: nil, sortHint: -1)
                }
            }
            var entry = groups[key] ?? seed
            entry.games += 1
            switch r.result {
            case .win:  entry.wins += 1
            case .lose: entry.losses += 1
            case .draw: break
            }
            groups[key] = entry
        }

        aggregated = groups.values.map {
            AggregatedStat(characterId: $0.cid, role: $0.role,
                           primary: $0.primary, secondary: $0.secondary,
                           games: $0.games, wins: $0.wins, losses: $0.losses,
                           sortHint: $0.sortHint)
        }
        applySorting()
    }

    private func applySorting() {
        switch sortKey {
        case .name:
            aggregated.sort {
                if $0.sortHint != $1.sortHint { return $0.sortHint > $1.sortHint }
                return ($0.primary, $0.secondary ?? "") < ($1.primary, $1.secondary ?? "")
            }
        case .winRate:
            aggregated.sort { $0.winRate > $1.winRate }
        case .games:
            aggregated.sort { $0.games > $1.games }
        case .diff:
            aggregated.sort { $0.diff > $1.diff }
        }
    }

    // MARK: - Summary

    private var summaryView: some View {
        let winRate = totalGames > 0 ? Double(totalWins) / Double(totalGames) * 100 : 0
        let diff = totalWins - totalLosses
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 16) {
                Text("試合数：\(totalGames)")
                Text("\(totalWins)勝 \(totalLosses)敗" + (totalDraws > 0 ? " \(totalDraws)分" : ""))
            }
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("差分：")
                    Text(diffText(diff)).foregroundColor(diffColor(diff)).bongaBold()
                }
                Text(String(format: "勝率：%.1f%%", winRate))
            }
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(10)
    }

    // MARK: - 表示形式バー

    private var viewModeBar: some View {
        Picker("表示形式", selection: $viewMode) {
            ForEach(ViewMode.allCases) { m in Text(m.rawValue).tag(m) }
        }
        .pickerStyle(.segmented)
        // segmentedスタイルのPickerは未選択セグメントの地が半透明で、背景画像が
        // そのまま透けて文字が読みにくくなっていた（写真は場所によって明暗がバラバラなため、
        // ライト/ダークの自動切り替えだけでは対処しきれない）。不透明なカードで包むことで、
        // 背景画像の内容に関わらず常に読める状態にする。
        .padding(4)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(10)
    }

    // MARK: - ロール別勝率

    private var roleStatsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ロール別")
                .font(.bongaEmphasis(.subheadline))
                .foregroundColor(.bongaPurple)
            ForEach(roleStats) { rs in
                HStack {
                    Image(systemName: rs.role.iconName)
                        .foregroundColor(.bongaIcon)
                        .frame(width: 20)
                    Text(rs.role.label)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 84, alignment: .leading)
                    Text("\(rs.games)戦")
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 44, alignment: .trailing)
                    Text("\(rs.wins)勝")
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 40, alignment: .trailing)
                    Text(diffText(rs.diff))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 44, alignment: .trailing)
                        .foregroundColor(diffColor(rs.diff))
                    Text(String(format: "%.1f%%", rs.winRate * 100))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .foregroundColor(.bongaPurple)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - 集計単位バー

    private var primaryColumnTitle: String {
        switch groupUnit {
        case .map:  return "マップ"
        case .rank: return "ランク"
        default:    return "ガール"
        }
    }

    private var availableGroupUnits: [GroupUnit] {
        rankEnabled ? GroupUnit.allCases : GroupUnit.allCases.filter { $0 != .rank }
    }

    private var groupUnitBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("集計単位").font(.caption).foregroundColor(.secondary)
            Picker("集計単位", selection: $groupUnit) {
                ForEach(availableGroupUnits) { u in Text(u.rawValue).tag(u) }
            }
            .pickerStyle(.segmented)
            .onChange(of: groupUnit) { _, _ in
                if hasSearched { runSearch() }
            }
            .onAppear {
                // ランクOFFなのに ランク別 が選ばれていたら補正
                if !rankEnabled && groupUnit == .rank { groupUnit = .character }
            }
        }
        .padding(10)
        // 未選択セグメントの地が半透明で背景画像が透けて見にくくなる問題への対策
        // （viewModeBarと同様）。ラベルごと不透明カードに収める。
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(10)
    }

    // MARK: - 並び替えバー

    private var sortBar: some View {
        HStack {
            Text("並び替え").font(.caption).foregroundColor(.secondary)
            Picker("並び替え", selection: $sortKey) {
                ForEach(SortKey.allCases) { key in
                    Text(key.rawValue).tag(key)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: sortKey) { _, _ in applySorting() }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(10)
    }

    // MARK: - 差分表示ヘルパー

    private func diffText(_ diff: Int) -> String {
        if diff > 0 { return "+\(diff)" }
        if diff < 0 { return "\(diff)" }
        return "±0"
    }
    private func diffColor(_ diff: Int) -> Color {
        if diff > 0 { return .green }
        if diff < 0 { return .red }
        return .secondary
    }

    // MARK: - Results Table

    private var resultsTable: some View {
        let showSecondary = (groupUnit == .characterMap)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(primaryColumnTitle)
                    .frame(width: showSecondary ? 72 : 100, alignment: .leading)
                if showSecondary {
                    Text("マップ").frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("試合").frame(width: 40, alignment: .trailing)
                if !showSecondary {
                    Text("勝").frame(width: 36, alignment: .trailing)
                }
                Text("差分").frame(width: 46, alignment: .trailing)
                Text("勝率").frame(width: 54, alignment: .trailing)
            }
            .font(.bongaEmphasis(.caption))
            .foregroundColor(Color.bongaCyanLight.readableForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.bongaCyanLight)

            if aggregated.isEmpty {
                Text("該当データなし")
                    .foregroundColor(.secondary)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(aggregated) { stat in
                    HStack(spacing: 0) {
                        Text(stat.primary)
                            .frame(width: showSecondary ? 72 : 100, alignment: .leading)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        if showSecondary {
                            Text(stat.secondary ?? "")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Text("\(stat.games)").frame(width: 40, alignment: .trailing)
                        if !showSecondary {
                            Text("\(stat.wins)").frame(width: 36, alignment: .trailing)
                        }
                        Text(diffText(stat.diff))
                            .frame(width: 46, alignment: .trailing)
                            .foregroundColor(diffColor(stat.diff))
                        Text(String(format: "%.1f%%", stat.winRate * 100))
                            .frame(width: 54, alignment: .trailing)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    Divider()
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }
}
