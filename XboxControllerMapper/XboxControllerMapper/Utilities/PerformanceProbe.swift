import Foundation

final class PerformanceProbe {
    static let shared = PerformanceProbe()

    private struct Counters {
        var displayTicks: Int = 0
        var displayNoOpTicks: Int = 0
        var displayApplies: Int = 0
        var displayFieldWrites: Int = 0
        var motionCallbacksRaw: Int = 0
        var motionCallbacksProcessed: Int = 0
    }

    private let lock = NSLock()
    private var counters = Counters()
    private var timer: DispatchSourceTimer?

    private init() {
        guard Config.performanceProbeEnabled else { return }

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.flushInterval()
        }
        timer.resume()
        self.timer = timer
    }

    func recordDisplayTick() {
        mutate { $0.displayTicks += 1 }
    }

    func recordDisplayNoOpTick() {
        mutate { $0.displayNoOpTicks += 1 }
    }

    func recordDisplayApply(fieldWrites: Int) {
        mutate {
            $0.displayApplies += 1
            $0.displayFieldWrites += fieldWrites
        }
    }

    func recordMotionCallback(rawOnly: Bool) {
        mutate {
            $0.motionCallbacksRaw += 1
            if !rawOnly {
                $0.motionCallbacksProcessed += 1
            }
        }
    }

    private func mutate(_ body: (inout Counters) -> Void) {
        guard Config.performanceProbeEnabled else { return }
        lock.lock()
        body(&counters)
        lock.unlock()
    }

    private func flushInterval() {
        let snapshot: Counters = lock.withLock {
            let current = counters
            counters = Counters()
            return current
        }

        NSLog(
            "[PerfProbe] interval scenario=%@ display_ticks=%d display_noop_ticks=%d display_applies=%d display_field_writes=%d motion_callbacks_raw=%d motion_callbacks_processed=%d",
            Config.performanceScenarioLabel,
            snapshot.displayTicks,
            snapshot.displayNoOpTicks,
            snapshot.displayApplies,
            snapshot.displayFieldWrites,
            snapshot.motionCallbacksRaw,
            snapshot.motionCallbacksProcessed
        )
    }
}
