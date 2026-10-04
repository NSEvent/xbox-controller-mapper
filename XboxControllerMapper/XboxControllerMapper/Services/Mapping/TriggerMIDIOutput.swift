import Foundation

/// Serializes production sends and resets, including polling/disable races.
/// Values are quantized, duplicate-suppressed, and bounded to 60 updates/second.
nonisolated final class TriggerMIDIOutput: @unchecked Sendable {
	private struct Stream {
		var configuration: TriggerMIDIConfiguration
		var armed = false
		var lastValue: Int?
		var lastTime = -Double.infinity
	}
	private let lock = NSLock()
	private let sender: any MIDIControlChangeSending
	private var streams: [Int: Stream] = [:]
	init(sender: any MIDIControlChangeSending) { self.sender = sender }

	func update(left: Double, right: Double, leftConfiguration: TriggerMIDIConfiguration?, rightConfiguration: TriggerMIDIConfiguration?, now: Double) {
		lock.withLock {
			updateStream(0, raw: left, configuration: leftConfiguration, now: now)
			updateStream(1, raw: right, configuration: rightConfiguration, now: now)
		}
	}

	func snapshot(for side: Int) -> (armed: Bool, value: Int?)? {
		lock.withLock { streams[side].map { ($0.armed, $0.lastValue) } }
	}

	func reset() {
		lock.withLock {
			for stream in streams.values { reset(stream) }
			streams.removeAll()
		}
	}

	private func reset(_ stream: Stream) {
		let neutral = stream.configuration.value(for: 0)
		if stream.lastValue != neutral { sender.sendPress(stream.configuration.output(value: neutral)) }
	}

	private func updateStream(_ id: Int, raw: Double, configuration: TriggerMIDIConfiguration?, now: Double) {
		guard raw.isFinite, now.isFinite else { return }
		if streams[id]?.configuration != configuration {
			if let old = streams.removeValue(forKey: id) { reset(old) }
		}
		guard let configuration else { return }
		var stream = streams[id] ?? Stream(configuration: configuration)
		let neutral = configuration.value(for: 0)
		if stream.lastValue == nil {
			sender.sendPress(configuration.output(value: neutral))
			stream.lastValue = neutral
		}
		// A trigger held across profile/connection/enable boundaries must first release.
		if raw <= configuration.deadzone { stream.armed = true }
		let value = stream.armed ? configuration.value(for: raw) : neutral
		if value != stream.lastValue, value == neutral || now - stream.lastTime >= 1 / 60 {
			sender.sendPress(configuration.output(value: value))
			stream.lastValue = value
			stream.lastTime = now
		}
		streams[id] = stream
	}
}
