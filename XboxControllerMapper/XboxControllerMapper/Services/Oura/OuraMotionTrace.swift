import CoreGraphics
import Foundation

// Full-rate motion trace for the gesture-labeling harness (Tools/oura-calibration).
// Unlike the throttled diagnostic log, this records every accelerometer sample plus
// every recognizer event, as ndjson, so prompted capture sessions can be joined with
// the browser-side gesture labels by wall-clock time.
//
// Enable:  defaults write KevinTang.XboxControllerMapper ouraMotionTraceLogging -bool true
// Output:  /tmp/controllerkeys-oura-motion-trace.ndjson
//
// Line shapes ("t" = unix seconds at write, "ct" = CFAbsoluteTime the recognizers saw;
// note both samples of one BLE frame carry near-identical "ct" — the analyzer
// reconstructs nominal spacing from frame pairing):
//   {"type":"sample","t":…,"ct":…,"x":…,"y":…,"z":…,"px":…,"py":…}
//   {"type":"event","t":…,"ct":…,"name":"tap-detected","detail":"…"}

nonisolated enum OuraMotionTraceFormat {
	static func sampleLine(
		wallTime: TimeInterval,
		sample: OuraMotionSample,
		projected: CGPoint
	) -> String {
		jsonLine([
			"type": "sample",
			"t": wallTime,
			"ct": sample.timestamp,
			"x": sample.x,
			"y": sample.y,
			"z": sample.z,
			"px": Double(projected.x),
			"py": Double(projected.y)
		])
	}

	static func eventLine(
		wallTime: TimeInterval,
		timestamp: CFAbsoluteTime,
		name: String,
		detail: String? = nil
	) -> String {
		var object: [String: Any] = [
			"type": "event",
			"t": wallTime,
			"ct": timestamp,
			"name": name
		]
		if let detail {
			object["detail"] = detail
		}
		return jsonLine(object)
	}

	private static func jsonLine(_ object: [String: Any]) -> String {
		guard JSONSerialization.isValidJSONObject(object),
		      let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
		      let line = String(data: data, encoding: .utf8) else {
			return "{}"
		}
		return line
	}
}

// nonisolated: internally NSLock-synchronized and must not inherit the
// project's default MainActor isolation. XCTest teardown can otherwise trip the
// isolated-deinit back-deploy path when OuraRingInputService is released.
nonisolated final class OuraMotionTraceWriter {
	static let defaultsKey = "ouraMotionTraceLogging"
	static let traceURL = URL(fileURLWithPath: "/tmp/controllerkeys-oura-motion-trace.ndjson")

	private let lock = NSLock()
	private var handle: FileHandle?
	private var openFailed = false

	private var isEnabled: Bool {
		UserDefaults.standard.bool(forKey: Self.defaultsKey)
	}

	func recordSample(_ sample: OuraMotionSample, projected: CGPoint) {
		guard isEnabled else { return }
		write(OuraMotionTraceFormat.sampleLine(
			wallTime: Date().timeIntervalSince1970,
			sample: sample,
			projected: projected
		))
	}

	func recordEvent(
		_ name: String,
		detail: String? = nil,
		timestamp: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
	) {
		guard isEnabled else { return }
		write(OuraMotionTraceFormat.eventLine(
			wallTime: Date().timeIntervalSince1970,
			timestamp: timestamp,
			name: name,
			detail: detail
		))
	}

	func close() {
		lock.lock()
		defer { lock.unlock() }
		try? handle?.close()
		handle = nil
		openFailed = false
	}

	private func write(_ line: String) {
		guard let data = (line + "\n").data(using: .utf8) else { return }
		lock.lock()
		defer { lock.unlock() }
		if handle == nil, !openFailed {
			let path = Self.traceURL.path
			if !FileManager.default.fileExists(atPath: path) {
				FileManager.default.createFile(atPath: path, contents: nil)
			}
			if let opened = try? FileHandle(forWritingTo: Self.traceURL) {
				_ = try? opened.seekToEnd()
				handle = opened
			} else {
				openFailed = true
				NSLog("[ControllerKeys][Oura] motion trace open failed at %@", path)
				return
			}
		}
		guard let handle else { return }
		do {
			try handle.write(contentsOf: data)
		} catch {
			NSLog("[ControllerKeys][Oura] motion trace write failed: %@", error.localizedDescription)
			try? handle.close()
			self.handle = nil
			openFailed = true
		}
	}
}
