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

enum OuraMotionTraceFormat {
	static func sampleLine(
		wallTime: TimeInterval,
		sample: OuraMotionSample,
		projected: CGPoint
	) -> String {
		String(
			format: "{\"type\":\"sample\",\"t\":%.6f,\"ct\":%.6f,\"x\":%.4f,\"y\":%.4f,\"z\":%.4f,\"px\":%.4f,\"py\":%.4f}",
			wallTime, sample.timestamp, sample.x, sample.y, sample.z, projected.x, projected.y
		)
	}

	static func eventLine(
		wallTime: TimeInterval,
		timestamp: CFAbsoluteTime,
		name: String,
		detail: String? = nil
	) -> String {
		var line = String(
			format: "{\"type\":\"event\",\"t\":%.6f,\"ct\":%.6f,\"name\":\"%@\"",
			wallTime, timestamp, name as NSString
		)
		if let detail {
			line += ",\"detail\":\"\(detail)\""
		}
		line += "}"
		return line
	}
}

final class OuraMotionTraceWriter {
	static let defaultsKey = "ouraMotionTraceLogging"
	static let traceURL = URL(fileURLWithPath: "/tmp/controllerkeys-oura-motion-trace.ndjson")

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
		try? handle?.close()
		handle = nil
		openFailed = false
	}

	private func write(_ line: String) {
		guard let data = (line + "\n").data(using: .utf8) else { return }
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
