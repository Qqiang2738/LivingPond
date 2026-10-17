import Foundation

@main
struct FrameMeterTests {
    static func main() {
        let meter = NativeFrameMeter()
        var t: Double = 0
        meter.sample(t)
        for _ in 0..<3600 {
            t += 1.0/60.0
            meter.sample(t)
            meter.recordUpdateWork(2.3)
        }
        assert(meter.totalFrames == 3600)
        assert(meter.sampleCount == 3600)
        assert(meter.slow50Total == 0)
        var report = meter.report(mode:"test", nodeCount:206, viewPreferredFPS:60)
        assert(report.contains("约 60.0 FPS"), report)
        assert(report.contains("约 60.0 秒"), report)
        // The 3601st sample overwrites one slot rather than allocating/shifting.
        t += 0.12
        meter.sample(t)
        assert(meter.totalFrames == 3601)
        assert(meter.sampleCount == 3600)
        assert(meter.slow50Total == 1)
        assert(meter.slow100Total == 1)
        let firstBatch=meter.drainSlowEvents()
        assert(firstBatch.events.count == 1)
        assert(firstBatch.events[0].gapMS > 100)
        assert(firstBatch.omitted == 0)
        assert(meter.drainSlowEvents().events.isEmpty)
        // Suspended system clock gaps should be reported but never included as slow frames.
        t += 10
        meter.sample(t)
        assert(meter.clockDiscontinuities == 1)
        assert(meter.slow100Total == 1)
        meter.markInterruption()
        t += 15
        meter.sample(t)
        assert(meter.slow100Total == 1)
        assert(meter.clockDiscontinuities == 2)
        meter.droppedSimulationTime()
        report = meter.report(mode:"test", nodeCount:206, viewPreferredFPS:60)
        assert(report.contains("模拟补偿超额：1 次"), report)
        // A long event contains the preceding frame's update-work duration.
        meter.reset()
        var t2: Double = 0
        meter.sample(t2)
        t2 += 1.0/60.0
        meter.sample(t2)
        meter.recordUpdateWork(0.87)
        meter.recordScenePhase(1.32)
        t2 += 0.2
        meter.sample(t2, context: "pond=still")
        let trace=meter.drainSlowEvents()
        assert(trace.events.count == 1)
        assert(trace.events[0].context == "pond=still")
        assert(abs(trace.events[0].precedingWorkMS-0.87) < 0.001)
        assert(abs(trace.events[0].precedingScenePhaseMS-1.32) < 0.001)
        // Buffer cap: many consecutive slow frames must not grow without bound.
        meter.reset()
        var t3: Double = 0
        meter.sample(t3)
        for _ in 0..<700 {
            t3 += 0.07
            meter.sample(t3, context: "extended stress")
        }
        let many=meter.drainSlowEvents()
        assert(many.events.count == 512)
        assert(many.omitted == 188)
        assert(meter.drainSlowEvents().events.isEmpty)
        meter.reset()
        assert(meter.totalFrames == 0)
        assert(meter.sampleCount == 0)
        assert(meter.slow100Total == 0)
        print("PASS FrameMetrics: 60s bounded ring, long frames, clock discontinuities, reset")
    }
}
