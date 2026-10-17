import Foundation

/// Metrics for SpriteKit update callbacks (not GPU presentation timestamps).
/// Bounded, preallocated storage: sampling does not grow memory or shift arrays.
/// Significant update-callback gaps, buffered in RAM until the next periodic log write.
/// The preceding update work is useful context but is NOT a GPU/present timing.
struct LongFrameEvent {
    let occurredAt: Date
    let gapMS: Double
    let precedingWorkMS: Double
    let precedingScenePhaseMS: Double
    let context: String
}

final class NativeFrameMeter {
    private let capacity = 3600 // up to ~60 seconds at 60 Hz
    private var samples = [Double](repeating: 0, count: 3600)
    private var nextIndex = 0
    private var used = 0
    private var previous: TimeInterval?
    private(set) var totalFrames = 0
    private(set) var catchUpDrops = 0
    private(set) var clockDiscontinuities = 0
    private(set) var slow33Total = 0
    private(set) var slow50Total = 0
    private(set) var slow100Total = 0
    private(set) var worstEverMS: Double = 0
    private var workMilliseconds: Double = 0
    private var workSamples = 0
    private var lastUpdateWorkMS: Double = 0
    private var lastScenePhaseMS: Double = 0
    private var scenePhaseWorkTotal: Double = 0
    private var scenePhaseSamples = 0
    private var slowEvents: [LongFrameEvent] = []
    private let slowEventLimit = 512
    private var slowEventsOmitted = 0

    func sample(_ now: TimeInterval, context: @autoclosure () -> String = "") {
        defer { previous = now }
        guard let before = previous else { return }
        let ms = (now - before) * 1000
        guard ms > 0, ms < 2500 else {
            clockDiscontinuities += 1
            return
        }
        samples[nextIndex] = ms
        nextIndex = (nextIndex + 1) % capacity
        used = min(capacity, used + 1)
        totalFrames += 1
        worstEverMS = max(worstEverMS, ms)
        if ms > 33.4 { slow33Total += 1 }
        if ms > 50 { slow50Total += 1 }
        if ms > 100 { slow100Total += 1 }
        if ms > 50 {
            if slowEvents.count < slowEventLimit {
                slowEvents.append(LongFrameEvent(occurredAt: Date(), gapMS: ms,
                                                 precedingWorkMS: lastUpdateWorkMS,
                                                 precedingScenePhaseMS: lastScenePhaseMS,
                                                 context: context()))
            } else {
                slowEventsOmitted += 1
            }
        }
    }

    func recordUpdateWork(_ ms: Double) {
        guard ms.isFinite, ms >= 0, ms < 10000 else { return }
        workMilliseconds += ms
        workSamples += 1
        lastUpdateWorkMS = ms
    }

    /// From SKScene.update entry through SKScene.didFinishUpdate callback.
    /// This is scene-stage CPU elapsed time, NOT GPU submission/presentation time.
    func recordScenePhase(_ ms: Double) {
        guard ms.isFinite, ms >= 0, ms < 10000 else { return }
        lastScenePhaseMS = ms
        scenePhaseWorkTotal += ms
        scenePhaseSamples += 1
    }

    /// Drain only once per minute or when the recording ends. No per-frame disk IO.
    func drainSlowEvents() -> (events: [LongFrameEvent], omitted: Int) {
        let result = (events: slowEvents, omitted: slowEventsOmitted)
        slowEvents.removeAll(keepingCapacity: true)
        slowEventsOmitted = 0
        return result
    }

    func droppedSimulationTime() { catchUpDrops += 1 }

    /// Exclude clock leaps caused by system sleep, screen changes or Space switches.
    /// Lifetime slow-frame counters remain intact for the stability log.
    func markInterruption() {
        previous = nil
        clockDiscontinuities += 1
    }

    func reset() {
        previous = nil
        nextIndex = 0
        used = 0
        totalFrames = 0
        catchUpDrops = 0
        clockDiscontinuities = 0
        slow33Total = 0
        slow50Total = 0
        slow100Total = 0
        worstEverMS = 0
        workMilliseconds = 0
        workSamples = 0
        lastUpdateWorkMS = 0
        lastScenePhaseMS = 0
        scenePhaseWorkTotal = 0
        scenePhaseSamples = 0
        slowEvents.removeAll(keepingCapacity: true)
        slowEventsOmitted = 0
    }

    var sampleCount: Int { used }

    func report(mode: String, nodeCount: Int, viewPreferredFPS: Int) -> String {
        guard used > 10 else { return "采样不足：在当前模式运行至少 30 秒，再查看报告。" }
        let window = Array(samples.prefix(used))
        let sorted = window.sorted()
        let mean = window.reduce(0, +) / Double(used)
        let median = sorted[used / 2]
        let p95 = sorted[min(used - 1, Int(Double(used - 1) * 0.95))]
        let worst = sorted.last ?? 0
        let slow33 = window.filter { $0 > 33.4 }.count
        let slow50 = window.filter { $0 > 50 }.count
        let slow100 = window.filter { $0 > 100 }.count
        let sampledSeconds = window.reduce(0, +) / 1000
        let work = workSamples > 0 ? workMilliseconds / Double(workSamples) : 0
        let phaseWork = scenePhaseSamples > 0 ? scenePhaseWorkTotal / Double(scenePhaseSamples) : 0
        return String(format: "渲染模式：SpriteKit / macOS 原生\n窗口：%@\n目标帧率：%d FPS\n\n近期样本：%d 帧（约 %.1f 秒）\n平均帧间隔：%.1f ms（约 %.1f FPS）\n中位帧间隔：%.1f ms\nP95 帧间隔：%.1f ms\n近期最长帧：%.1f ms\n近期慢帧 >33.4/50/100ms：%d / %d / %d\n\n本次诊断累计：%d 帧\n累计慢帧 >33.4/50/100ms：%d / %d / %d\n累计最长帧：%.1f ms\n模拟补偿超额：%d 次\n时钟中断/重置：%d 次\n平均 update 逻辑耗时：%.2f ms\n平均场景阶段耗时：%.2f ms（不含 GPU 呈现）\n场景节点：%d\n\n注意：以上是 SpriteKit update 回调间隔，不能替代屏幕最终呈现帧率；切换桌面和录屏也可能影响体感。",
            mode, viewPreferredFPS, used, sampledSeconds, mean, 1000 / mean, median, p95, worst,
            slow33, slow50, slow100, totalFrames, slow33Total, slow50Total, slow100Total,
            worstEverMS, catchUpDrops, clockDiscontinuities, work, phaseWork, nodeCount)
    }
}
