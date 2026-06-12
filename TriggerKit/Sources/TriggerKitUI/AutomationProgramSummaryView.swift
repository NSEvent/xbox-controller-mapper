import SwiftUI
import TriggerKitCore

public struct AutomationProgramSummaryView: View {
	private let program: AutomationProgram

	public init(program: AutomationProgram) {
		self.program = program
	}

	public var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(program.name)
				.font(.headline)
				.lineLimit(1)
			Text(program.displaySummary)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
	}
}
