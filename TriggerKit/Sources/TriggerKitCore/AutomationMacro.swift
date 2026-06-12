import Foundation

public struct AutomationMacro: Codable, Identifiable, Equatable, Sendable {
	public var id: UUID
	public var name: String
	public var program: AutomationProgram
	public var createdAt: Date
	public var updatedAt: Date

	public init(
		id: UUID = UUID(),
		name: String,
		program: AutomationProgram,
		createdAt: Date = Date(),
		updatedAt: Date = Date()
	) {
		let normalizedName = Self.normalizedName(name)
		self.id = id
		self.name = normalizedName
		self.program = program.normalized(fallbackName: normalizedName)
		self.createdAt = createdAt
		self.updatedAt = updatedAt
	}

	public var displaySummary: String {
		program.displaySummary
	}

	public static func normalizedName(_ raw: String) -> String {
		let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? "Untitled Macro" : trimmed
	}
}

public struct AutomationMacroReference: Codable, Equatable, Sendable {
	public var macroID: UUID?
	public var snapshot: AutomationProgram?

	public init(macroID: UUID? = nil, snapshot: AutomationProgram? = nil) {
		self.macroID = macroID
		self.snapshot = snapshot
	}

	public func resolvedProgram(macro: AutomationMacro?, fallbackName: String) -> AutomationProgram? {
		if let macro {
			return macro.program.normalized(fallbackName: macro.name)
		}
		if let snapshot, !snapshot.steps.isEmpty {
			return snapshot.normalized(fallbackName: fallbackName)
		}
		return nil
	}
}
