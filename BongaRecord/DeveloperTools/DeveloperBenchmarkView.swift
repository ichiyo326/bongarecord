#if DEBUG
import SwiftUI
import SwiftData

/// 開発者専用: 実機上で「Legacy(直列)」と「Pool(ModelActor並列)」を
/// 実際のBattleRecordデータに対して計測できる画面。
///
/// **なぜこれが必要か**:
/// これまでのXCTestベースの計測は全てシミュレータ(=Macのコア数・
/// スケジューリング特性)で行っていた。実機のCPU構成やiOSの電力管理下
/// では結果が変わる可能性が高く、その場で確認できる手段が要る。
///
/// **書き込みは一切行わない**: 既存の本物の戦績データに対して
/// `fetchCount`(読み取り専用)を投げるだけなので、実データを壊す
/// リスクはない。
///
/// **開発者専用である理由**:
/// このファイル全体が`#if DEBUG`で囲まれているため、Xcodeの
/// Releaseビルド構成(App Store提出用アーカイブを含む)では
/// コンパイル対象から完全に除外される。ユーザーの手元に届く配布版
/// バイナリには、この画面のコードそのものが含まれない。
struct DeveloperBenchmarkView: View {
    @Environment(\.modelContext) private var context
    @Query private var allRecords: [BattleRecord]

    @State private var isRunning = false
    @State private var resultLines: [String] = []
    @State private var iterations = 5

    @State private var isRunningWrite = false
    @State private var writeResultLines: [String] = []
    @State private var writeIterations = 3
    @State private var writeRecordCount = 2000

    private var deviceCoreCount: Int {
        ProcessInfo.processInfo.activeProcessorCount
    }

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    var body: some View {
        ZStack {
            PuzzleBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    infoCard
                    controlCard
                    if !resultLines.isEmpty {
                        resultCard
                    }
                    writeControlCard
                    if !writeResultLines.isEmpty {
                        writeResultCard
                    }
                }
                .padding()
            }
        }
        .bongaNavigationBar(title: "開発者ベンチマーク")
    }

    // MARK: - 情報カード

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("実行環境")
                .font(.headline)
            Text("実行先: \(isSimulator ? "シミュレータ" : "実機")")
            Text("利用可能コア数: \(deviceCoreCount)")
            Text("戦績データ件数: \(allRecords.count)件")
            if isSimulator {
                Text("⚠️ シミュレータ実行中。コア数はホストMacの値であり、実機とは異なります。")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color.bongaPurple.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - 操作カード

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("試行回数: \(iterations)", value: $iterations, in: 1...20)

            Button {
                runBenchmark()
            } label: {
                HStack {
                    if isRunning {
                        ProgressView()
                    }
                    Text(isRunning ? "実行中…" : "ベンチマーク実行")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.bongaPurple)
                .foregroundColor(.bongaOnAccent)
                .cornerRadius(6)
            }
            .disabled(isRunning || allRecords.isEmpty)

            if allRecords.isEmpty {
                Text("戦績データが無いため計測できません。まず何件か登録してください。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.bongaPurple.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - 結果カード

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("結果")
                .font(.headline)
            ForEach(resultLines, id: \.self) { line in
                Text(line)
                    .font(.system(.footnote, design: .monospaced))
            }
        }
        .padding()
        .background(Color.bongaPurple.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - 実行（読み取り専用：実データを使う）

    private func runBenchmark() {
        isRunning = true
        resultLines = []

        let charIds = Array(Set(allRecords.map(\.characterId))).sorted()
        let container = context.container
        let n = iterations
        let records = allRecords

        Task {
            var lines: [String] = []
            lines.append("対象キャラ数: \(charIds.count) / 総戦績: \(records.count)件")

            // Legacy(直列)。既存のcontextをそのまま使い回す。
            let legacyContext = ModelContext(container)
            var legacySamples: [Double] = []
            for _ in 0..<n {
                let start = CFAbsoluteTimeGetCurrent()
                _ = try? DeveloperLegacyCalculator.computeAll(context: legacyContext, charIds: charIds)
                legacySamples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            lines.append(format("練度集計 Legacy(直列)", legacySamples))

            // Pool(size=4、使い回し)
            var poolSamples: [Double] = []
            let calculators = (0..<4).map { _ in ProficiencyCalculator(modelContainer: container) }
            for _ in 0..<n {
                let start = CFAbsoluteTimeGetCurrent()
                _ = try? await runPooled(charIds: charIds, calculators: calculators)
                poolSamples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            lines.append(format("練度集計 Pool(size=4)", poolSamples))

            // Snapshot集計: 旧5パス vs 新1パス（試合登録のたびに毎回呼ばれる処理）
            var legacySnapshotSamples: [Double] = []
            for _ in 0..<n {
                let start = CFAbsoluteTimeGetCurrent()
                _ = DeveloperLegacyCalculator.legacySnapshotCompute(from: records, since: 0)
                legacySnapshotSamples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            lines.append(format("Snapshot集計 旧(5パス)", legacySnapshotSamples))

            var newSnapshotSamples: [Double] = []
            for _ in 0..<n {
                let start = CFAbsoluteTimeGetCurrent()
                _ = BattleStatsSnapshot.compute(from: records, since: 0)
                newSnapshotSamples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            lines.append(format("Snapshot集計 新(1パス)", newSnapshotSamples))

            await MainActor.run {
                resultLines = lines
                isRunning = false
            }
        }
    }

    private func runPooled(
        charIds: [Int],
        calculators: [ProficiencyCalculator]
    ) async throws -> [ProficiencyCalculator.CharacterStat] {
        let groupCount = calculators.count
        var groups: [[Int]] = Array(repeating: [], count: groupCount)
        for (index, id) in charIds.enumerated() {
            groups[index % groupCount].append(id)
        }

        return try await withThrowingTaskGroup(of: [ProficiencyCalculator.CharacterStat].self) { group in
            for (index, chunk) in groups.enumerated() where !chunk.isEmpty {
                let calculator = calculators[index]
                group.addTask {
                    try await calculator.stats(for: chunk)
                }
            }
            var merged: [ProficiencyCalculator.CharacterStat] = []
            for try await partial in group {
                merged.append(contentsOf: partial)
            }
            return merged
        }
    }

    // MARK: - 書き込み系ベンチマーク（ダミーデータのみ使用。実データには一切触れない）

    /// CSV取込・ランクスタンプは「書き込み」を伴うため、実データを使う訳にはいかない。
    /// ここだけ専用のin-memory `ModelContainer`を毎回新規に作り、ダミーレコードで
    /// 計測する。コンテナ生成・ダミー投入のコストは計測区間の外に置き、
    /// 「実際に削除・挿入・保存（またはfetch・更新・保存）にかかった時間」だけを測る。
    private var writeControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("書き込み系ベンチマーク（ダミーデータ・実データ非破壊）")
                .font(.headline)
            Stepper("件数: \(writeRecordCount)", value: $writeRecordCount, in: 500...20000, step: 500)
            Stepper("試行回数: \(writeIterations)", value: $writeIterations, in: 1...10)

            Button {
                runWriteBenchmark()
            } label: {
                HStack {
                    if isRunningWrite {
                        ProgressView()
                    }
                    Text(isRunningWrite ? "実行中…" : "書き込みベンチマーク実行")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.bongaPurple)
                .foregroundColor(.bongaOnAccent)
                .cornerRadius(6)
            }
            .disabled(isRunningWrite)

            Text("ここはダミーのin-memoryコンテナ上でのみ計測するため、実際の戦績データには一切触れません。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.bongaPurple.opacity(0.1))
        .cornerRadius(8)
    }

    private var writeResultCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("書き込み系 結果")
                .font(.headline)
            ForEach(writeResultLines, id: \.self) { line in
                Text(line)
                    .font(.system(.footnote, design: .monospaced))
            }
        }
        .padding()
        .background(Color.bongaPurple.opacity(0.1))
        .cornerRadius(8)
    }

    private func makeDummySchema() -> Schema {
        Schema([BattleRecord.self, PlayerInfo.self, MapPreference.self, CharacterPreference.self])
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: makeDummySchema(), configurations: config)
    }

    private func makeDummyDrafts(count: Int) -> [CSVManager.ImportedBattleDraft] {
        let mapIds = MasterData.maps.map(\.id)
        let charIds = MasterData.characters.map(\.id)
        let results: [BattleResult] = [.win, .lose, .draw]
        var drafts: [CSVManager.ImportedBattleDraft] = []
        drafts.reserveCapacity(count)
        for i in 0..<count {
            drafts.append(CSVManager.ImportedBattleDraft(
                date: Date(timeIntervalSince1970: TimeInterval(i)),
                mapId: mapIds[i % mapIds.count],
                characterId: charIds[i % charIds.count],
                result: results[i % results.count]
            ))
        }
        return drafts
    }

    private func runWriteBenchmark() {
        isRunningWrite = true
        writeResultLines = []
        let n = writeIterations
        let count = writeRecordCount
        let drafts = makeDummyDrafts(count: count)

        Task {
            var lines: [String] = []
            lines.append("ダミー件数: \(count)件 / 試行回数: \(n)回")

            // --- CSV取込: 旧(MainActor同期) vs 新(CSVImportActor) ---
            var legacyImportSamples: [Double] = []
            for _ in 0..<n {
                guard let container = try? makeInMemoryContainer() else { continue }
                let ctx = ModelContext(container)
                let start = CFAbsoluteTimeGetCurrent()
                try? DeveloperLegacyCalculator.legacyImport(drafts, rankStampRaw: -1, context: ctx)
                legacyImportSamples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            lines.append(format("CSV取込 旧(MainActor同期)", legacyImportSamples))

            var actorImportSamples: [Double] = []
            for _ in 0..<n {
                guard let container = try? makeInMemoryContainer() else { continue }
                let importer = CSVImportActor(modelContainer: container)
                let start = CFAbsoluteTimeGetCurrent()
                let stream = await importer.importAll(drafts, rankStampRaw: -1)
                do {
                    for try await _ in stream {}
                } catch {
                    // ベンチマーク用途のため、途中エラーでも計測自体は継続する
                }
                actorImportSamples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            lines.append(format("CSV取込 新(CSVImportActor)", actorImportSamples))

            // --- ランクスタンプ: 旧(MainActor同期) vs 新(RankStampActor) ---
            var legacyStampSamples: [Double] = []
            for _ in 0..<n {
                guard let container = try? makeInMemoryContainer() else { continue }
                let ctx = ModelContext(container)
                for draft in drafts {
                    let r = BattleRecord(date: draft.date, mapId: draft.mapId,
                                          characterId: draft.characterId, result: draft.result)
                    ctx.insert(r)
                }
                try? ctx.save()

                let start = CFAbsoluteTimeGetCurrent()
                _ = try? DeveloperLegacyCalculator.legacyStampAll(rank: PlayerRank.superstarC.rawValue, context: ctx)
                legacyStampSamples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            lines.append(format("ランクスタンプ 旧(MainActor同期)", legacyStampSamples))

            var actorStampSamples: [Double] = []
            for _ in 0..<n {
                guard let container = try? makeInMemoryContainer() else { continue }
                let ctx = ModelContext(container)
                for draft in drafts {
                    let r = BattleRecord(date: draft.date, mapId: draft.mapId,
                                          characterId: draft.characterId, result: draft.result)
                    ctx.insert(r)
                }
                try? ctx.save()

                let stamper = RankStampActor(modelContainer: container)
                let start = CFAbsoluteTimeGetCurrent()
                _ = try? await stamper.stampAll(rank: PlayerRank.superstarC.rawValue)
                actorStampSamples.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            lines.append(format("ランクスタンプ 新(RankStampActor)", actorStampSamples))

            await MainActor.run {
                writeResultLines = lines
                isRunningWrite = false
            }
        }
    }

    private func format(_ label: String, _ samples: [Double]) -> String {
        guard !samples.isEmpty else { return "\(label): データ無し" }
        let avg = samples.reduce(0, +) / Double(samples.count)
        let minV = samples.min() ?? 0
        let maxV = samples.max() ?? 0
        return String(format: "%@: avg=%.1fms min=%.1fms max=%.1fms (n=%d)",
                       label, avg, minV, maxV, samples.count)
    }
}

#Preview {
    NavigationStack {
        DeveloperBenchmarkView()
    }
    .modelContainer(for: [BattleRecord.self, PlayerInfo.self, MapPreference.self, CharacterPreference.self], inMemory: true)
}
#endif
