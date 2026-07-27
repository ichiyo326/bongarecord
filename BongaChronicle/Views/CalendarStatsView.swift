import SwiftUI
import SwiftData

/// 月カレンダー形式の戦績ヒートマップ。
///
/// 親（BattleStatsView）から渡されるマップ／キャラ／ロールのフィルタは尊重するが、
/// 日付範囲はこのビューが表示中の月で独立に取り直す（月送りのため）。
/// 日付セルをタップすると `onSelectDay` でその日を親へ通知し、親側でリストへドリルダウンする。
struct CalendarStatsView: View {
    // 太さ/色などテーマの変更をこの画面が生きている間もライブ反映するために保持。
    @ObservedObject private var theme = ThemeManager.shared
    let mapIds: Set<Int>
    let characterIds: Set<Int>
    let roles: Set<CharacterRole>
    var onSelectDay: (Date) -> Void

    @Environment(\.modelContext) private var context
    @Query private var playerInfos: [PlayerInfo]

    /// 表示中の月（その月の1日 0:00 に正規化して保持）
    @State private var month: Date = {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }()

    /// 日(1〜31) → 集計
    @State private var dayStats: [Int: DayStat] = [:]

    /// その月のランク変動（昇格・降格）
    @State private var transitions: [RankTransition] = []

    /// 各日セルに「n戦」を表示するか（永続化）
    @AppStorage("calendar.showGameCount") private var showGameCount = true

    private var rankEnabled: Bool { playerInfos.first?.rankTrackingEnabled == true }

    enum RankChangeKind { case promotion, demotion, start }

    struct RankTransition: Identifiable {
        let id = UUID()
        let day: Int
        let to: PlayerRank
        let kind: RankChangeKind
    }

    private let cal = Calendar.current
    private let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    struct DayStat {
        var games: Int
        var wins: Int
        var losses: Int
        var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }
        var diff: Int { wins - losses }
    }

    var body: some View {
        VStack(spacing: 12) {
            controls
            // weekdayHeaderは単なるTextの並びで不透明な下地を持たないため、
            // 背景画像の上では曜日が読みにくくなっていた。月送りヘッダーと
            // まとめて1枚のカードにして解消する。
            VStack(spacing: 8) {
                header
                weekdayHeader
            }
            .padding(.horizontal, 4).padding(.vertical, 8)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(8)
            grid
            legend
            if rankEnabled && !transitions.isEmpty {
                rankTimeline
            }
        }
        .padding(.horizontal)
        .onAppear { load() }
        .onChange(of: month) { _, _ in load() }
    }

    // MARK: - ヘッダー（月送り）

    private var header: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left").font(.headline)
            }
            .accessibilityLabel("前の月")
            Spacer()
            Text(monthTitle)
                .font(.bongaEmphasis(.headline))
                .foregroundColor(.bongaPurple)
            Spacer()
            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right").font(.headline)
            }
            .disabled(isCurrentMonthOrLater)
            .opacity(isCurrentMonthOrLater ? 0.3 : 1)
            .accessibilityLabel("次の月")
        }
    }

    private var controls: some View {
        Toggle(isOn: $showGameCount) {
            Label("各日に試合数を表示", systemImage: showGameCount ? "eye" : "eye.slash")
                .font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(8)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                Text(weekdaySymbols[i])
                    .font(.bongaEmphasis(.caption2))
                    .frame(maxWidth: .infinity)
                    .foregroundColor(i == 0 ? .red : (i == 6 ? .blue : .secondary))
            }
        }
    }

    // MARK: - グリッド

    /// 月初の空白セルと日付セルをまとめた列挙。
    /// 以前は `ForEach(0..<leadingBlanks, id: \.self)` と `ForEach(1...daysInMonth, id: \.self)` を
    /// LazyVGrid内で並べていたが、両者のidが同じInt空間（例：leadingBlanks=5なら0〜4、日付は1〜31）で
    /// 重複してしまい、SwiftUIが空白セルと日付セル（特に月初の数日）を同一視して
    /// 表示が消える／更新されないバグの原因になっていた。id空間を完全に分離することで解消する。
    private enum GridCell: Hashable {
        case blank(Int)
        case day(Int)
    }

    private var gridCells: [GridCell] {
        (0..<leadingBlanks).map { GridCell.blank($0) } + (1...daysInMonth).map { GridCell.day($0) }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(gridCells, id: \.self) { cell in
                switch cell {
                case .blank:
                    Color.clear
                        .frame(height: 52)
                        .frame(maxWidth: .infinity)
                case .day(let day):
                    dayCell(day)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let stat = dayStats[day]
        let hasData = (stat?.games ?? 0) > 0
        Button {
            if hasData, let date = date(forDay: day) {
                onSelectDay(date)
            }
        } label: {
            VStack(spacing: 1) {
                Text("\(day)")
                    .font(.caption2)
                    .foregroundColor(isToday(day) ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 1)
                    .background(isToday(day) ? Color.bongaPurple : Color.clear)
                    .clipShape(Capsule())
                if let s = stat, hasData {
                    if showGameCount {
                        Text("\(s.games)戦")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    Text(diffText(s.diff))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(diffColor(s.diff))
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            // cellBackground()は勝率に応じた半透明色（グラデーション表現のためopacityを
            // 持たせている）なので、そのまま背景画像の上に置くと画像の透け具合次第で
            // 日付や戦績の文字が読みにくくなっていた。不透明な下地を先に敷いてから
            // 半透明の色を重ねることで、画像を透けさせずに色の濃淡表現だけを保つ。
            .background(
                ZStack {
                    Color(uiColor: .systemBackground)
                    cellBackground(stat)
                }
            )
            .cornerRadius(6)
            .overlay(alignment: .topTrailing) {
                if rankEnabled, let kind = transitionKind(forDay: day) {
                    // 色（緑=昇格／赤=降格／紫=開始）だけで判別させると色覚特性によっては
                    // 見分けがつかないため、タイムライン側と同じ▲▼●の「形」も併記する。
                    Text(kindSymbol(kind))
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(kindColor(kind))
                        .padding(2)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!hasData)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibilityLabel(day: day, stat: stat, hasData: hasData))
    }

    /// VoiceOver用に、日付・戦績・ランク変動をまとめて1つの説明文にする。
    /// （数字バッジやランクの色分けだけに頼らず、内容を音声でも伝えるため）
    private func dayAccessibilityLabel(day: Int, stat: DayStat?, hasData: Bool) -> String {
        var parts = ["\(monthNumber)月\(day)日"]
        if let s = stat, hasData {
            parts.append("\(s.games)戦\(s.wins)勝\(s.losses)敗")
            parts.append("差分\(diffText(s.diff))")
        } else {
            parts.append("記録なし")
        }
        if rankEnabled, let kind = transitionKind(forDay: day),
           let t = transitions.first(where: { $0.day == day }) {
            parts.append("\(t.to.label)\(kindWord(kind))")
        }
        return parts.joined(separator: "、")
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendChip(color: heatColor(rate: 0.0, games: 3), label: "負け多")
            legendChip(color: heatColor(rate: 0.5, games: 3), label: "五分")
            legendChip(color: heatColor(rate: 1.0, games: 3), label: "勝ち多")
            Spacer()
            Text("日タップで詳細")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(8)
    }

    // MARK: - ランク変動

    private var rankTimeline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ランク変動")
                .font(.bongaEmphasis(.subheadline))
                .foregroundColor(.bongaPurple)
            ForEach(transitions) { t in
                HStack(spacing: 8) {
                    Text(kindSymbol(t.kind))
                        .foregroundColor(kindColor(t.kind))
                        .font(.bongaEmphasis(.caption))
                        .frame(width: 16)
                    Text("\(monthNumber)/\(t.day)")
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .leading)
                    Text("\(t.to.label) \(kindWord(t.kind))")
                    Spacer()
                }
                .font(.caption)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(8)
    }

    private func transitionKind(forDay day: Int) -> RankChangeKind? {
        transitions.first(where: { $0.day == day })?.kind
    }

    private func kindSymbol(_ kind: RankChangeKind) -> String {
        switch kind {
        case .promotion: return "▲"
        case .demotion:  return "▼"
        case .start:     return "●"
        }
    }

    private func kindColor(_ kind: RankChangeKind) -> Color {
        switch kind {
        case .promotion: return .green
        case .demotion:  return .red
        case .start:     return .bongaPurple
        }
    }

    private func kindWord(_ kind: RankChangeKind) -> String {
        switch kind {
        case .promotion: return "に昇格"
        case .demotion:  return "に降格"
        case .start:     return "から記録開始"
        }
    }

    private var monthNumber: Int {
        cal.component(.month, from: month)
    }

    private func legendChip(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 14, height: 14)
            Text(label).font(.system(size: 10)).foregroundColor(.secondary)
        }
    }

    // MARK: - セルの見た目

    private func cellBackground(_ stat: DayStat?) -> Color {
        guard let s = stat, s.games > 0 else {
            return Color(uiColor: .secondarySystemBackground).opacity(0.4)
        }
        return heatColor(rate: s.winRate, games: s.games)
    }

    /// 勝率で赤(0.0)→黄(0.5)→緑(1.0)。試合数が多いほど濃く。
    private func heatColor(rate: Double, games: Int) -> Color {
        let hue = 0.33 * rate                       // 0=赤, 0.33=緑
        let intensity = min(Double(games), 6.0) / 6.0
        return Color(hue: hue, saturation: 0.65, brightness: 0.95)
            .opacity(0.22 + 0.45 * intensity)
    }

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

    // MARK: - 日付計算

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年 M月"
        return f.string(from: month)
    }

    private var firstOfMonth: Date {
        let comps = cal.dateComponents([.year, .month], from: month)
        return cal.date(from: comps) ?? month
    }

    /// 月初の前に入る空白セル数（0=日曜始まり）
    private var leadingBlanks: Int {
        cal.component(.weekday, from: firstOfMonth) - 1
    }

    private var daysInMonth: Int {
        cal.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30
    }

    private func date(forDay day: Int) -> Date? {
        cal.date(byAdding: .day, value: day - 1, to: firstOfMonth)
    }

    private func isToday(_ day: Int) -> Bool {
        guard let d = date(forDay: day) else { return false }
        return cal.isDateInToday(d)
    }

    private var isCurrentMonthOrLater: Bool {
        let now = cal.dateComponents([.year, .month], from: Date())
        let cur = cal.dateComponents([.year, .month], from: month)
        if let ny = now.year, let nm = now.month, let cy = cur.year, let cm = cur.month {
            return (cy, cm) >= (ny, nm)
        }
        return false
    }

    private func shiftMonth(_ delta: Int) {
        if let m = cal.date(byAdding: .month, value: delta, to: month) {
            month = m
        }
    }

    // MARK: - データ取得

    private func load() {
        let start = firstOfMonth
        guard let nextMonth = cal.date(byAdding: .month, value: 1, to: start) else { return }
        let startTs = Int64(start.timeIntervalSince1970)
        let endTs   = Int64(nextMonth.timeIntervalSince1970)

        let predicate: Predicate<BattleRecord> = #Predicate { r in
            r.dateTimestamp >= startTs && r.dateTimestamp < endTs
        }
        // 当月の全記録（未フィルタ）。ランク時系列はプレイヤー単位なのでフィルタ非適用。
        let monthRecords = (try? context.fetch(FetchDescriptor<BattleRecord>(predicate: predicate))) ?? []

        // 戦績ヒートマップ用はマップ／キャラ／ロールで絞る
        var matched = monthRecords
        if !mapIds.isEmpty {
            matched = matched.filter { mapIds.contains($0.mapId) }
        }
        if !characterIds.isEmpty {
            matched = matched.filter { characterIds.contains($0.characterId) }
        }
        if !roles.isEmpty {
            matched = matched.filter { r in
                guard let role = MasterData.character(byId: r.characterId)?.role else { return false }
                return roles.contains(role)
            }
        }

        var buckets: [Int: DayStat] = [:]
        for r in matched {
            let day = cal.component(.day, from: r.date)
            var s = buckets[day] ?? DayStat(games: 0, wins: 0, losses: 0)
            s.games += 1
            switch r.result {
            case .win:  s.wins += 1
            case .lose: s.losses += 1
            case .draw: break
            }
            buckets[day] = s
        }
        dayStats = buckets

        loadRankTransitions(monthRecords: monthRecords, startTs: startTs)
    }

    /// 当月のランク変動を算出。各日の「最後の記録のランク」を順に追い、
    /// 直前のランクと変われば昇格／降格として記録する。
    /// 月初の基準には、月をまたいで直前のランク付き記録を1件だけ取得する。
    private func loadRankTransitions(monthRecords: [BattleRecord], startTs: Int64) {
        guard rankEnabled else { transitions = []; return }

        // 各日の最終ランク（タイムスタンプ昇順で上書き＝その日の最後が残る）
        var dayRank: [Int: Int] = [:]
        for r in monthRecords.sorted(by: { $0.dateTimestamp < $1.dateTimestamp }) where r.rankRaw >= 0 {
            dayRank[cal.component(.day, from: r.date)] = r.rankRaw
        }

        // 月初時点の基準ランク（直前のランク付き記録）
        var desc = FetchDescriptor<BattleRecord>(
            predicate: #Predicate { $0.dateTimestamp < startTs && $0.rankRaw >= 0 },
            sortBy: [SortDescriptor(\.dateTimestamp, order: .reverse)]
        )
        desc.fetchLimit = 1
        var running = (try? context.fetch(desc))?.first?.rankRaw ?? -1

        var result: [RankTransition] = []
        for day in 1...daysInMonth {
            guard let raw = dayRank[day], let to = PlayerRank(rawValue: raw) else { continue }
            if raw != running {
                let kind: RankChangeKind
                if running < 0      { kind = .start }
                else if raw > running { kind = .promotion }
                else                  { kind = .demotion }
                result.append(RankTransition(day: day, to: to, kind: kind))
                running = raw
            }
        }
        transitions = result
    }
}
