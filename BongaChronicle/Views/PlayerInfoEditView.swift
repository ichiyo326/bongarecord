import SwiftUI
import SwiftData

struct PlayerInfoEditView: View {
    @Environment(\.modelContext) private var context
    @Query private var playerInfos: [PlayerInfo]
    @Query private var mapPrefs: [MapPreference]
    @Query private var charPrefs: [CharacterPreference]
    @Environment(\.dismiss) var dismiss
    // 太さ/色などテーマの変更をこの画面が生きている間もライブ反映するために保持。
    @ObservedObject private var theme = ThemeManager.shared

    @State private var name: String              = ""
    @State private var comment: String           = ""
    @State private var theme_appTheme: AppTheme  = .light
    @State private var favoriteMapIds: [Int]     = [-1, -1, -1]
    @State private var favoriteCharIds: [Int]    = [-1, -1, -1, -1]
    @State private var showSavedAlert            = false
    @State private var loaded                    = false

    // ランク（クラス）記録
    @State private var rankTrackingEnabled       = false
    @State private var rankConfigured            = false      // 初期設定済みか（現在ランクが設定済み）
    @State private var selectedRank: PlayerRank  = .superstarC
    @State private var showSetupConfirm          = false
    @State private var showPromoteConfirm        = false
    @State private var rankInfoMessage: String?  = nil

    var body: some View {
        ZStack {
            PuzzleBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    SectionLabel(text: "プレイヤーネーム")
                        .padding(.horizontal).padding(.top, 8)
                    FormCard {
                        TextField("プレイヤー名を入力", text: $name)
                            .keyboardType(.default)
                            .disableAutocorrection(true)
                    }

                    SectionLabel(text: "コメント")
                        .padding(.horizontal).padding(.top, 12)
                    FormCard {
                        TextField("コメントを入力", text: $comment, axis: .vertical)
                            .lineLimit(2...5)
                            .keyboardType(.default)
                            .disableAutocorrection(true)
                    }

                    SectionLabel(text: "テーマパターン")
                        .padding(.horizontal).padding(.top, 12)
                    HStack(spacing: 24) {
                        ForEach(AppTheme.allCases) { t in
                            RadioButton(label: t.label, isSelected: theme_appTheme == t) {
                                theme_appTheme = t
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal).padding(.vertical, 12)

                    // ── お気に入りマップ（3枠）──
                    SectionLabel(text: "お気に入りマップ")
                        .padding(.horizontal).padding(.top, 4)
                    ForEach(0..<3, id: \.self) { i in
                        FormCard {
                            let maps = Catalog.resolvedMaps(prefs: mapPrefs)
                            let groups = Catalog.resolvedMapGroups(maps)
                            Menu {
                                Button("（指定なし）") { favoriteMapIds[i] = -1 }
                                ForEach(groups, id: \.self) { group in
                                    Section(header: Text(group)) {
                                        ForEach(maps.filter { $0.group == group }) { m in
                                            Button(m.name) { favoriteMapIds[i] = m.id }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(Catalog.mapName(byId: favoriteMapIds[i], prefs: mapPrefs)
                                         ?? "お気に入り \(i+1) を選択")
                                        .foregroundColor(Catalog.mapName(byId: favoriteMapIds[i], prefs: mapPrefs) == nil
                                                         ? .secondary : .primary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    // ── お気に入りキャラ（4枠）──
                    SectionLabel(text: "お気に入りキャラ")
                        .padding(.horizontal).padding(.top, 12)
                    ForEach(0..<4, id: \.self) { i in
                        FormCard {
                            let chars = Catalog.resolvedCharacters(prefs: charPrefs)
                            Menu {
                                Button("（指定なし）") { favoriteCharIds[i] = -1 }
                                ForEach(CharacterRole.allCases) { role in
                                    let inRole = chars.filter { $0.role == role }
                                    if !inRole.isEmpty {
                                        Section(header: Text(role.label)) {
                                            ForEach(inRole) { c in
                                                Button(c.name) { favoriteCharIds[i] = c.id }
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(Catalog.charName(byId: favoriteCharIds[i], prefs: charPrefs)
                                         ?? "お気に入り \(i+1) を選択")
                                        .foregroundColor(Catalog.charName(byId: favoriteCharIds[i], prefs: charPrefs) == nil
                                                         ? .secondary : .primary)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    // ── ランク（クラス）記録 ──
                    SectionLabel(text: "ランク記録（任意）")
                        .padding(.horizontal).padding(.top, 20)
                    FormCard {
                        rankSection
                    }
                    .padding(.horizontal)

                    PrimaryButton(title: "更新") {
                        save()
                    }
                    .padding(.horizontal).padding(.top, 16).padding(.bottom, 16)
                }
            }
        }
        .bongaNavigationBar(title: "プレイヤー情報")
        .onAppear {
            guard !loaded else { return }
            let pi = context.ensurePlayerInfo()
            name = pi.name
            comment = pi.comment
            theme_appTheme = pi.theme
            favoriteMapIds = pi.favoriteMapIds
            favoriteCharIds = pi.favoriteCharIds
            rankTrackingEnabled = pi.rankTrackingEnabled
            rankConfigured = (pi.currentRankRaw >= 0)
            selectedRank = pi.currentRank ?? .superstarC
            loaded = true
        }
        .alert("更新しました", isPresented: $showSavedAlert) {
            Button("OK") { }
        }
        .alert("過去の記録に反映しますか？", isPresented: $showSetupConfirm) {
            Button("反映する") { setupRank() }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("これまでに記録した全試合を「\(selectedRank.label)」として記録します。以降の新しい記録には、その時点のランクが付きます。")
        }
        .alert("ランクを変更しますか？", isPresented: $showPromoteConfirm) {
            Button("変更する") { changeRank() }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("現在のランクを「\(selectedRank.label)」に変更します。過去の記録はそのまま、以降の記録が新しいランクになります。")
        }
        .alert("ランク記録", isPresented: .constant(rankInfoMessage != nil), presenting: rankInfoMessage) { _ in
            Button("OK") { rankInfoMessage = nil }
        } message: { msg in
            Text(msg)
        }
    }

    // MARK: - ランクセクション

    @ViewBuilder
    private var rankSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("ランクを記録する", isOn: $rankTrackingEnabled)
                .onChange(of: rankTrackingEnabled) { _, on in
                    let pi = context.ensurePlayerInfo()
                    pi.rankTrackingEnabled = on
                    try? context.save()
                }

            if rankTrackingEnabled {
                Divider()

                // ランク選択
                HStack {
                    Text(rankConfigured ? "現在のランク" : "現在のランクは？")
                        .font(.subheadline)
                    Spacer()
                    Menu {
                        ForEach(PlayerRank.allCases.reversed()) { rank in
                            Button(rank.label) { selectedRank = rank }
                        }
                    } label: {
                        HStack {
                            Text(selectedRank.label).foregroundColor(.primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                if !rankConfigured {
                    Button {
                        showSetupConfirm = true
                    } label: {
                        Text("設定して過去の記録に反映")
                            .font(.bongaEmphasis(.subheadline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.bongaPurple)
                            .foregroundColor(.bongaOnAccent)
                            .cornerRadius(6)
                    }
                } else {
                    if let current = currentRankValue {
                        Text("現在：\(current.label)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button {
                        showPromoteConfirm = true
                    } label: {
                        Text("ランクを変更")
                            .font(.bongaEmphasis(.subheadline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(canChange ? Color.bongaPurple : Color.gray.opacity(0.4))
                            .foregroundColor(.bongaOnAccent)
                            .cornerRadius(6)
                    }
                    .disabled(!canChange)
                }

                Text("ランクを変更すると、以降の記録に反映されます（過去の記録は変わりません）。昇格・降格どちらも変更できます。")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var currentRankValue: PlayerRank? {
        playerInfos.first?.currentRank
    }

    /// 選択中ランクが現在のランクと違うか（変更として意味があるか）
    private var canChange: Bool {
        (playerInfos.first?.currentRankRaw ?? -1) != selectedRank.rawValue
    }

    /// 初期設定：現在ランクを設定し、過去の全記録をそのランクで埋める
    private func setupRank() {
        let pi = context.ensurePlayerInfo()
        pi.rankTrackingEnabled = true
        pi.setRank(to: selectedRank)

        let all = (try? context.fetch(FetchDescriptor<BattleRecord>())) ?? []
        for r in all { r.rankRaw = selectedRank.rawValue }
        try? context.save()

        rankConfigured = true
        rankInfoMessage = "過去 \(all.count) 件を「\(selectedRank.label)」として記録しました。"
    }

    /// ランク変更（昇格・降格）：現在ランクのみ更新（過去記録はそのまま）
    private func changeRank() {
        let pi = context.ensurePlayerInfo()
        pi.setRank(to: selectedRank)
        try? context.save()
        rankInfoMessage = "現在のランクを「\(selectedRank.label)」に変更しました。"
    }

    private func save() {
        let pi = context.ensurePlayerInfo()
        pi.name = name
        pi.comment = comment
        pi.theme = theme_appTheme
        pi.favoriteMapIds = favoriteMapIds
        pi.favoriteCharIds = favoriteCharIds
        pi.lastModified = Date()
        try? context.save()
        showSavedAlert = true
    }
}
