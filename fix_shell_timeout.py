import sys

file_path = "TriggerKit/Sources/TriggerKitRuntime/AutomationExecutor.swift"
with open(file_path, "r") as f:
    content = f.read()

# Replace the part causing the test to hang
old_code = """		let timeout = DispatchTime.now() + step.timeoutSeconds
		if semaphore.wait(timeout: timeout) == .timedOut {
			terminateProcessTree(process, signal: SIGTERM)
			_ = semaphore.wait(timeout: .now() + 1)
			if process.isRunning {
				terminateProcessTree(process, signal: SIGKILL)
			}
			clearStoredProcess()
			pipe.fileHandleForReading.readabilityHandler = nil
			return ShellRunOutcome(result: .failure("Shell command timed out"))
		}"""

new_code = """		let timeout = DispatchTime.now() + step.timeoutSeconds
		if semaphore.wait(timeout: timeout) == .timedOut {
			terminateProcessTree(process, signal: SIGTERM)
			_ = semaphore.wait(timeout: .now() + 1)
			if process.isRunning {
				terminateProcessTree(process, signal: SIGKILL)
			}
			clearStoredProcess()
			pipe.fileHandleForReading.readabilityHandler = nil
			return ShellRunOutcome(result: .failure("Shell command timed out"))
		}"""

# Actually, the timeout in the test might be failing because we are blocking somewhere?
