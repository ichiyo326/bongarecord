import XCTest
import SwiftData
@testable import BongaRecord_Project

final class ParallelismDiagnosticsTests: XCTestCase {

    // MARK: - H7: 利用可能コア数の確認

    func testDiagnostic_H7_AvailableCoreCount() {
        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        print("[Diagnostic/H7] activeProcessorCount = \(coreCount)")
        // 記録するだけ。poolSize=4を選んだ根拠がそもそも妥当だったかの前提情報。
        XCTAssertGreaterThan(coreCount, 0)
    }

    // MARK: - H4: actor生成コストの寄与を切り分ける

    /// 「fetchを一切せず、actorをN個生成するだけ」のコストを単独計測する。
    /// これが全体の所要時間に対してどれくらいの割合を占めるかを見る。
    func testDiagnostic_H4_ActorCreationOverheadAlone() async throws {
        let container = try PerformanceTestSupport.makeSeededContainer(
            recordCount: 200_000, characterCount: 34
        )

        await PerformanceTestSupport.benchmark(
            label: "H4/actor生成のみ(fetch無し)/poolSize=4",
            iterations: 5
        ) {
            _ = (0..<4).map { _ in ProficiencyCalculator(modelContainer: container) }
        }
    }

    /// 同一データ・同一並列数で「毎回actorを作り直す版」と「使い回す版」を比較する。
    /// 差が縮まる/消えるなら、前回の"Poolが遅い"という結果の相当部分は
    /// actor生成コストが原因だったと言える。
    func testDiagnostic_H4_PerCallPoolVsPersistentPool() async throws {
        let container = try PerformanceTestSupport.makeSeededContainer(
            recordCount: 200_000, characterCount: 34
        )
        let charIds = Array(0..<34)

        try await PerformanceTestSupport.benchmark(
            label: "H4/毎回生成するPool(size=4)/200,000件",
            iterations: 5
        ) {
            _ = try await ProficiencyCalculatorPool.computeAll(
                container: container, charIds: charIds, poolSize: 4
            )
        }

        // 使い回すactorを事前に1回だけ生成し、以降5回ともそれを使う。
        let persistentPool = PersistentProficiencyPool(container: container, poolSize: 4)
        try await PerformanceTestSupport.benchmark(
            label: "H4/使い回しPool(size=4)/200,000件",
            iterations: 5
        ) {
            _ = try await persistentPool.computeAll(charIds: charIds)
        }
    }

    // MARK: - H5: 実際に並列実行されているかの直接観測

    /// TaskGroup内の各タスクが「同時に何個動いていたか」を実測する。
    /// poolSize=4で本当に4並列に近い値が出るか、それとも1(=実質直列)しか
    /// 出ないかを確認する。データ量を多めにして、各タスクの実行時間を
    /// 観測可能な長さまで引き伸ばしている。
    func testDiagnostic_H5_ActualConcurrencyDegree() async throws {
        let container = try PerformanceTestSupport.makeSeededContainer(
            recordCount: 500_000, characterCount: 34
        )
        let charIds = Array(0..<34)

        let pool = PersistentProficiencyPool(container: container, poolSize: 4)
        let probe = ConcurrencyProbe()

        _ = try await pool.computeAllProbed(charIds: charIds, probe: probe)

        let peak = await probe.peakObserved
        print("[Diagnostic/H5] 実測された最大同時実行数(poolSize=4に対して) = \(peak)")
        // アサーションはあえて緩く。1のままでも「直列だった」という
        // 立派な発見なので、テスト失敗ではなく観測値として記録する。
    }

    // MARK: - H6: CPU時間 vs 経過時間

    /// Legacy(直列)とPool(並列)それぞれで、経過時間とCPU時間(全コア合計)を
    /// 両方測る。並列実行で複数コアが同時に働いていれば
    /// 「CPU時間 > 経過時間」になるはず。CPU時間が経過時間とほぼ同じなら、
    /// 実際には1コアが順番にこなしていただけだったと分かる。
    func testDiagnostic_H6_CPUTimeVsWallTime() async throws {
        let container = try PerformanceTestSupport.makeSeededContainer(
            recordCount: 500_000, characterCount: 34
        )
        let charIds = Array(0..<34)
        let legacyContext = ModelContext(container)

        // Legacy(直列)
        do {
            let wallStart = CFAbsoluteTimeGetCurrent()
            let cpuStart = CPUTimeProbe.currentCPUTimeMs()
            _ = try LegacyProficiencyCalculator.computeAll(context: legacyContext, charIds: charIds)
            let wallMs = (CFAbsoluteTimeGetCurrent() - wallStart) * 1000
            let cpuMs = CPUTimeProbe.currentCPUTimeMs() - cpuStart
            print(String(format: "[Diagnostic/H6] Legacy: wall=%.1fms cpu=%.1fms 比率(cpu/wall)=%.2f",
                         wallMs, cpuMs, cpuMs / max(wallMs, 0.001)))
        }

        // Pool(size=4, 使い回し)
        do {
            let pool = PersistentProficiencyPool(container: container, poolSize: 4)
            let wallStart = CFAbsoluteTimeGetCurrent()
            let cpuStart = CPUTimeProbe.currentCPUTimeMs()
            _ = try await pool.computeAll(charIds: charIds)
            let wallMs = (CFAbsoluteTimeGetCurrent() - wallStart) * 1000
            let cpuMs = CPUTimeProbe.currentCPUTimeMs() - cpuStart
            print(String(format: "[Diagnostic/H6] Pool(4): wall=%.1fms cpu=%.1fms 比率(cpu/wall)=%.2f",
                         wallMs, cpuMs, cpuMs / max(wallMs, 0.001)))
            print("[Diagnostic/H6] 比率が1に近ければ実質1コア、4に近いほど複数コアがフル活用されている")
        }
    }

    // MARK: - H7: 実ディスクI/Oでの再検証

    /// in-memoryではなく実際にファイルへ書き出すストアで、Legacy vs Poolを
    /// 再比較する。ディスクI/O待ちが並列化の効果を生むかどうかを見る。
    func testDiagnostic_H7_DiskBackedStoreComparison() async throws {
        let (container, storeURL) = try PerformanceTestSupport.makeDiskBackedContainer(
            recordCount: 300_000, characterCount: 34
        )
        defer { PerformanceTestSupport.cleanupDiskBackedStore(at: storeURL) }

        let charIds = Array(0..<34)
        let legacyContext = ModelContext(container)

        try await PerformanceTestSupport.benchmark(
            label: "H7/Legacy/ディスク上300,000件",
            iterations: 3
        ) {
            _ = try LegacyProficiencyCalculator.computeAll(context: legacyContext, charIds: charIds)
        }

        let pool = PersistentProficiencyPool(container: container, poolSize: 4)
        try await PerformanceTestSupport.benchmark(
            label: "H7/Pool(size=4, 使い回し)/ディスク上300,000件",
            iterations: 3
        ) {
            _ = try await pool.computeAll(charIds: charIds)
        }
    }
}
