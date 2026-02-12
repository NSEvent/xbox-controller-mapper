import SwiftUI
import Combine

class InputLogService: ObservableObject {
    @Published var entries: [InputLogEntry] = []
    
    private var timer: Timer?
    private let retentionDuration: TimeInterval = 3.0 // Items disappear after 3 seconds
    
    // Batching mechanism to handle high-frequency inputs
    private var pendingEntries: [InputLogEntry] = []
    private var isUpdateScheduled = false
    private let lock = NSLock()
    
    func log(buttons: [ControllerButton], type: InputEventType, action: String, isHeld: Bool = false) {
        let entry = InputLogEntry(buttons: buttons, type: type, actionDescription: action)

        lock.lock()
        pendingEntries.append(entry)
        let shouldSchedule = !isUpdateScheduled
        if shouldSchedule {
            isUpdateScheduled = true
        }
        lock.unlock()

        if shouldSchedule {
            // Batch updates every 50ms to prevent UI stutter on spam
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.flushPendingEntries()
            }
        }

        // Show cursor feedback for the action (skip unmapped actions)
        if !action.contains("(unmapped)") {
            Task { @MainActor in
                ActionFeedbackIndicator.shared.show(action: action, type: type, isHeld: isHeld)
            }
        }
    }

    /// Dismiss held action feedback (call when button is released)
    func dismissHeldFeedback() {
        Task { @MainActor in
            ActionFeedbackIndicator.shared.dismissHeld()
        }
    }
    
    private func flushPendingEntries() {
        lock.lock()
        let newItems = pendingEntries
        pendingEntries.removeAll()
        isUpdateScheduled = false
        lock.unlock()

        guard !newItems.isEmpty else { return }

        // Update entries without blocking animation - let the view handle animations
        // New items come in chronological order [Event 1, Event 2, Event 3]
        // We want newest at the top/left: [Event 3, Event 2, Event 1, Old...]

        if newItems.count >= 8 {
            // If we have a flood of new items, just take the newest 8
            self.entries = Array(newItems.suffix(8)).reversed()
        } else {
            // Insert new items at the start
            self.entries.insert(contentsOf: newItems.reversed(), at: 0)

            // Trim excess
            if self.entries.count > 8 {
                self.entries = Array(self.entries.prefix(8))
            }
        }
        self.scheduleCleanup()
    }
    
    private func scheduleCleanup() {
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                self?.cleanup()
            }
        }
    }
    
    private func cleanup() {
        guard !entries.isEmpty else {
            timer?.invalidate()
            timer = nil
            return
        }

        let now = Date()
        let threshold = now.addingTimeInterval(-retentionDuration)

        // Optimization: Only check the last item (oldest) since the list is sorted.
        // If the oldest hasn't expired, nothing has.
        if let last = entries.last, last.timestamp < threshold {
            // Remove expired entries without blocking animation
            entries.removeAll { $0.timestamp < threshold }
        }
    }
}
