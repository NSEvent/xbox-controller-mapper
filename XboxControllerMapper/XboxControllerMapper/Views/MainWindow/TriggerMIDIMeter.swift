import AppKit
import SwiftUI

struct TriggerMIDIMeterSample: Equatable {
	var pressure: Double
	var detail: String
	init(raw: Double, detail: String) {
		pressure = raw.isFinite ? (min(1, max(0, raw)) * 1000).rounded() / 1000 : 0
		self.detail = detail
	}
}

/// Keep high-frequency input out of SwiftUI layout. Sample the raw storage at
/// 60 Hz in common run-loop modes; draw only changed values, without interpolation.
struct TriggerMIDIMeter: NSViewRepresentable {
	@Environment(\.colorScheme) private var colorScheme
	let title: String
	let sample: @MainActor () -> TriggerMIDIMeterSample
	func makeNSView(context: Context) -> TriggerMIDIMeterView {
		let view = TriggerMIDIMeterView()
		view.title = title; view.sample = sample
		view.refresh()
		return view
	}
	func updateNSView(_ view: TriggerMIDIMeterView, context: Context) {
		view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
		view.title = title; view.sample = sample; view.refresh()
	}
	static func dismantleNSView(_ view: TriggerMIDIMeterView, coordinator: ()) { view.stop() }
}

final class TriggerMIDIMeterView: NSView {
	var title = ""
	var sample: (@MainActor () -> TriggerMIDIMeterSample)?
	private(set) var displayed: TriggerMIDIMeterSample?
	private(set) var updateCount = 0
	private var timer: Timer?
	override var isFlipped: Bool { true }
	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		stop()
		guard window != nil else { return }
		let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.refresh() }
		}
		RunLoop.main.add(timer, forMode: .common)
		self.timer = timer
	}
	func refresh() {
		guard let next = sample?(), next != displayed else { return }
		displayed = next; updateCount += 1; needsDisplay = true
		setAccessibilityElement(true)
		setAccessibilityRole(.progressIndicator)
		setAccessibilityLabel(title)
		setAccessibilityValue("\(Int((next.pressure * 100).rounded()))% pressure, \(next.detail)")
	}
	func stop() { timer?.invalidate(); timer = nil }
	override func draw(_ dirtyRect: NSRect) {
		guard let displayed else { return }
		let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
		let main: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
		let secondary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
		("\(title) · \(Int((displayed.pressure * 100).rounded()))% pressure" as NSString)
			.draw(at: NSPoint(x: 0, y: 0), withAttributes: main)
		(displayed.detail as NSString).draw(at: NSPoint(x: 0, y: 20), withAttributes: secondary)
		let track = NSRect(x: 0, y: 42, width: bounds.width, height: 8)
		NSColor.quaternaryLabelColor.setFill()
		NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()
		if displayed.pressure > 0 {
			NSColor.controlAccentColor.setFill()
			NSBezierPath(roundedRect: NSRect(x: 0, y: 42, width: track.width * displayed.pressure, height: 8), xRadius: 4, yRadius: 4).fill()
		}
	}
}
