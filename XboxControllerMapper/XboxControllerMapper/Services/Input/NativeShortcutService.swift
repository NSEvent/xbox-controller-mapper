import Combine
import Foundation

nonisolated protocol ShortcutProcessRunning: Sendable {
	func run(arguments: [String], timeout: TimeInterval) async throws -> String
}

enum ShortcutExecutionError: LocalizedError {
	case timedOut, failed(String), busy
	var errorDescription: String? {
		switch self {
		case .timedOut: return "Stopped waiting after 60 seconds. The shortcut may have partially run; check Shortcuts before retrying."
		case .failed(let reason): return reason
		case .busy: return "Another shortcut is running. Wait for it to finish."
		}
	}
}

nonisolated struct NativeShortcutProcessRunner: ShortcutProcessRunning {
	var executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
	func run(arguments: [String], timeout: TimeInterval) async throws -> String {
		try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.global(qos: .userInitiated).async {
				do { continuation.resume(returning: try Self.execute(arguments, timeout: timeout, executableURL: executableURL)) }
				catch { continuation.resume(throwing: error) }
			}
		}
	}

	private static func execute(_ arguments: [String], timeout: TimeInterval, executableURL: URL) throws -> String {
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent("controllerkeys-shortcut-\(UUID())")
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: folder) }
		let output = folder.appendingPathComponent("output")
		_ = FileManager.default.createFile(atPath: output.path, contents: nil)
		let handle = try FileHandle(forWritingTo: output)
		defer { try? handle.close() }
		let process = Process()
		process.executableURL = executableURL
		process.arguments = arguments
		process.standardInput = FileHandle.nullDevice
		process.standardOutput = handle
		process.standardError = handle
		let finished = DispatchSemaphore(value: 0)
		process.terminationHandler = { _ in finished.signal() }
		try process.run()
		if finished.wait(timeout: .now() + timeout) == .timedOut {
			process.terminate()
			if finished.wait(timeout: .now() + 1) == .timedOut {
				kill(process.processIdentifier, SIGKILL)
				_ = finished.wait(timeout: .now() + 1)
			}
			throw ShortcutExecutionError.timedOut
		}
		let reader = try FileHandle(forReadingFrom: output)
		defer { try? reader.close() }
		let data = try reader.read(upToCount: 1_048_576) ?? Data()
		let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
		guard process.terminationStatus == 0 else {
			throw ShortcutExecutionError.failed(text.isEmpty ? "Shortcut failed. Check that it still exists and has permission to run." : String(text.prefix(500)))
		}
		return text
	}
}

@MainActor
final class NativeShortcutService: ObservableObject {
	static let shared = NativeShortcutService()
	@Published private(set) var names: [String] = []
	@Published private(set) var isLoading = false
	@Published private(set) var isRunning = false
	@Published private(set) var status = ""
	@Published private(set) var lastRunSucceeded: Bool?
	private let runner: any ShortcutProcessRunning

	init(runner: any ShortcutProcessRunning = NativeShortcutProcessRunner()) { self.runner = runner }

	func refresh() async {
		guard !isLoading, !isRunning else { return }
		isLoading = true
		lastRunSucceeded = nil
		defer { isLoading = false }
		do {
			let output = try await runner.run(arguments: ["list"], timeout: 15)
			names = Array(Set(output.split(separator: "\n").map(String.init))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
			status = names.isEmpty ? "No shortcuts found. Create one in the Shortcuts app, then refresh." : ""
		} catch {
			if case ShortcutExecutionError.timedOut = error {
				status = "Could not load shortcuts within 15 seconds. Open Shortcuts, then refresh."
			} else { status = error.localizedDescription }
		}
	}

	@discardableResult
	func run(name: String) async -> Bool {
		guard !isRunning else { status = ShortcutExecutionError.busy.localizedDescription; return false }
		guard !isLoading else { status = "Wait for the shortcut list to finish loading."; return false }
		guard !name.isEmpty else { status = "Choose a shortcut first."; return false }
		isRunning = true
		lastRunSucceeded = nil
		status = "Running \(name)…"
		defer { isRunning = false }
		do {
			_ = try await runner.run(arguments: ["run", "--", name], timeout: 60)
			status = "Finished \(name)."
			lastRunSucceeded = true
			return true
		} catch {
			status = error.localizedDescription
			lastRunSucceeded = false
			return false // Never retry: a failed shortcut may have partially executed.
		}
	}
}
