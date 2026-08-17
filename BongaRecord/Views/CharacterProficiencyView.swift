import SwiftUI
import SwiftData

/// キャラクター練度を一覧表示する独立画面
struct CharacterProficiencyView: View {
    @Environment(\.modelContext) private var context
    @Query private var charPrefs: [CharacterPreference]
    // 太さ/色などテーマの変更をこの画面が生きている間もライブ反映するために保持。
    @ObservedObject private var theme = ThemeManager.shared

    @State private var proficiencyMap: [Int: String] = [:]
    @State private var displayChars: [DisplayCharacter] = []

    var body: some View {
        ZStack {
            PuzzleBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // ── 説明 ──
                    VStack(alignment: .leading, spacing: 6) {
                        Text("戦績データから各キャラの練度をランク表示します。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 12) {
                            rankLabel("S", "50戦以上 & 勝率70%↑")
                            rankLabel("A", "30戦以上 & 勝率60%↑")
                        }
                        HStack(spacing: 12) {
                            rankLabel("B", "15戦以上 & 勝率50%↑")
                            rankLabel("C", "5戦以上")
                        }
                        HStack(spacing: 12) {
                            rankLabel("D", "それ以外")
                            Spacer()
                        }
                    }
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(8)
                    .padding(.horizontal).padding(.top, 8)

                    // ── 練度グリッド ──
                    proficiencyGrid
                        .padding(.horizontal)
                }
                .padding(.bottom, 16)
            }
        }
        .bongaNavigationBar(title: "キャラクター練度")
        .task {
            await computeProficiency()
        }
    }

    // MARK: - Rank Label

    private func rankLabel(_ rank: String, _ desc: String) -> some View {
        HStack(spacing: 4) {
            Text(rank)
                .font(.bongaEmphasis(.caption))
                .foregroundColor(.bongaCyan)
                .frame(width: 20)
            Text(desc)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .foregroundColor(.bongaCyan)
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

    // MARK: - Compute

    @MainActor
    private func computeProficiency() async {
        let chars = Catalog.resolvedCharacters(prefs: charPrefs)
        displayChars = chars

        var profMap: [Int: String] = [:]
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

            profMap[charId] = rank(games: games, wins: wins)
        }
        proficiencyMap = profMap
    }

    private func rank(games: Int, wins: Int) -> String {
        guard games > 0 else { return "D" }
        let rate = Double(wins) / Double(games)
        switch (games, rate) {
        case (50..., 0.7...): return "S"
        case (30..., 0.6...): return "A"
        case (15..., 0.5...): return "B"
        case (5...,  _):      return "C"
        default:              return "D"
        }
    }
}
