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
    
    func log(buttons: [ControllerButton], type: InputEventType, action: String) {
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
    }
    
    private func flushPendingEntries() {
        lock.lock()
        let newItems = pendingEntries
        pendingEntries.removeAll()
        isUpdateScheduled = false
        lock.unlock()
        
        guard !newItems.isEmpty else { return }
        
        withAnimation(.easeOut(duration: 0.2)) {
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
            withAnimation(.easeOut(duration: 0.5)) {
                entries.removeAll { $0.timestamp < threshold }
            }
        }
    }
}
