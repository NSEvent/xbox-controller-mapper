import SwiftUI
import Combine

class InputLogService: ObservableObject {
    @Published var entries: [InputLogEntry] = []
    
    private var timer: Timer?
    private let retentionDuration: TimeInterval = 3.0 // Items disappear after 3 seconds
    
    func log(buttons: [ControllerButton], type: InputEventType, action: String) {
        let entry = InputLogEntry(buttons: buttons, type: type, actionDescription: action)
        
        DispatchQueue.main.async {
            // Use a faster, simpler animation for list updates (sliding)
            withAnimation(.easeOut(duration: 0.2)) {
                self.entries.insert(entry, at: 0) // Newest first
                
                // Keep list manageable
                if self.entries.count > 8 {
                    self.entries.removeLast()
                }
            }
            self.scheduleCleanup()
        }
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
