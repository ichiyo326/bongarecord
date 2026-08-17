import Foundation
import SwiftData
@testable import BongaRecord_Project

// MARK: - CPU時間 vs 経過時間の計測

/// プロセス全体のユーザー時間+システム時間(ms)を取得する。
/// 経過時間(wall time)と比較することで「本当に複数コアが働いたか」を
/// 判定できる: 並列実行で複数コアが同時に動けば、CPU時間の合計は
/// 経過時間を上回る(例: 4コアがフル稼働すれば理論上 最大4倍)。
/// 逆に、並列に"見えて"実際は1コアが順番にこなしているだけなら、
/// CPU時間はほぼ経過時間と一致する。
enum CPUTimeProbe {
    static func currentCPUTimeMs() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let userMs = Double(usage.ru_utime.tv_sec) * 1000 + Double(usage.ru_utime.tv_usec) / 1000
        let sysMs  = Double(usage.ru_stime.tv_sec) * 1000 + Double(usage.ru_stime.tv_usec) / 1000
        return userMs + sysMs
    }
}

// MARK: - 実際の並行実行度を観測するプローブ

/// TaskGroup内の各タスクが「同時に何個、実行中だったか」を記録するactor。
/// enter()/exit()で囲むだけで、実測の最大同時実行数(peak)が分かる。
/// これにより「並列化コードを書いた」ことと「実際に並列実行された」ことの
/// ギャップを直接確認できる。
actor ConcurrencyProbe {
    private var current = 0
    private(set) var peakObserved = 0
    private(set) var totalEnters = 0

    func enter() {
        current += 1
        totalEnters += 1
        if current > peakObserved { peakObserved = current }
    }

    func exit() {
        current -= 1
    }
}

// MARK: - 「使い回し型」プール(actor生成コストを比較から除外するため)

/// `ProficiencyCalculatorPool`は呼び出すたびに新しいModelActorを生成する。
/// このPersistentProficiencyPoolはactorを一度だけ生成し、以降は使い回す。
/// 両者を比較することで「並列化そのものの効果」と「actor生成コスト」を
/// 切り分けられる。
actor PersistentProficiencyPool {
    private let calculators: [ProficiencyCalculator]

    init(container: ModelContainer, poolSize: Int) {
        self.calculators = (0..<max(1, poolSize)).map { _ in
            ProficiencyCalculator(modelContainer: container)
        }
    }

    func computeAll(charIds: [Int]) async throws -> [ProficiencyCalculator.CharacterStat] {
        let groups = Self.split(charIds, into: calculators.count)
        return try await withThrowingTaskGroup(of: [ProficiencyCalculator.CharacterStat].self) { group in
            for (index, chunk) in groups.enumerated() where !chunk.isEmpty {
                let calculator = calculators[index]
                group.addTask {
                    try await calculator.stats(for: chunk)
                }
            }
            var merged: [ProficiencyCalculator.CharacterStat] = []
            merged.reserveCapacity(charIds.count)
            for try await partial in group {
                merged.append(contentsOf: partial)
            }
            return merged
        }
    }

    /// 各タスクの前後でConcurrencyProbeに出入りを記録しながら計算する版。
    /// 実際の並行実行度を観測する専用エントリポイント。
    func computeAllProbed(
        charIds: [Int],
        probe: ConcurrencyProbe
    ) async throws -> [ProficiencyCalculator.CharacterStat] {
        let groups = Self.split(charIds, into: calculators.count)
        return try await withThrowingTaskGroup(of: [ProficiencyCalculator.CharacterStat].self) { group in
            for (index, chunk) in groups.enumerated() where !chunk.isEmpty {
                let calculator = calculators[index]
                group.addTask {
                    await probe.enter()
                    do {
                        let result = try await calculator.stats(for: chunk)
                        await probe.exit()
                        return result
                    } catch {
                        await probe.exit()
                        throw error
                    }
                }
            }
            var merged: [ProficiencyCalculator.CharacterStat] = []
            for try await partial in group {
                merged.append(contentsOf: partial)
            }
            return merged
        }
    }

    private static func split(_ ids: [Int], into n: Int) -> [[Int]] {
        guard n > 1 else { return [ids] }
        var groups: [[Int]] = Array(repeating: [], count: n)
        for (index, id) in ids.enumerated() {
            groups[index % n].append(id)
        }
        return groups
    }
}

// MARK: - ディスク上のストアを使うための拡張

extension PerformanceTestSupport {

    /// in-memoryではなく実ファイルに書き出すModelContainerを生成する。
    /// SQLiteの実I/Oが並行読み取りにどう影響するかを見るためのもの。
    /// 呼び出し側が使い終わったらファイルを削除すること。
    static func makeDiskBackedContainer(
        recordCount: Int,
        characterCount: Int = 34
    ) throws -> (container: ModelContainer, storeURL: URL) {
        let schema = Schema([
            BattleRecord.self,
            PlayerInfo.self,
            MapPreference.self,
            CharacterPreference.self
        ])

        let tempDir = FileManager.default.temporaryDirectory
        let storeURL = tempDir.appendingPathComponent("perf_test_\(UUID().uuidString).sqlite")

        let config = ModelConfiguration(
            schema: schema,
            url: storeURL
        )
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let batchSize = 2000
        for i in 0..<recordCount {
            let record = BattleRecord(
                date: Date(),
                mapId: i % 48,
                characterId: i % characterCount,
                result: (i % 3 == 0) ? .win : .lose
            )
            context.insert(record)
            if i % batchSize == 0 {
                try context.save()
            }
        }
        try context.save()

        return (container, storeURL)
    }

    /// makeDiskBackedContainerで作った一時ファイル(および付随するWAL/SHM)を削除する。
    static func cleanupDiskBackedStore(at storeURL: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            try? fm.removeItem(at: url)
        }
    }
}
