import Foundation

public struct AutomationProgram: Codable, Equatable, Identifiable, Sendable {
	public static let currentSchemaVersion = 2

	public var id: UUID
	public var schemaVersion: Int
	public var name: String
	public var steps: [AutomationStep]

	public init(
		id: UUID = UUID(),
		schemaVersion: Int = AutomationProgram.currentSchemaVersion,
		name: String,
		steps: [AutomationStep] = []
	) {
		self.id = id
		self.schemaVersion = schemaVersion
		self.name = name
		self.steps = steps
	}

	public var isEmpty: Bool {
		steps.isEmpty
	}

	public var displaySummary: String {
		if steps.isEmpty { return "No actions" }
		if steps.count == 1 { return steps[0].displaySummary }
		return "\(steps.count) steps"
	}

	private enum CodingKeys: String, CodingKey {
		case id
		case schemaVersion
		case name
		case steps
	}

	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let decodedSchemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
		guard (1...Self.currentSchemaVersion).contains(decodedSchemaVersion) else {
			throw DecodingError.dataCorruptedError(
				forKey: .schemaVersion,
				in: container,
				debugDescription: "Unsupported automation schema version \(decodedSchemaVersion)"
			)
		}

		let decodedSteps = try container.decodeIfPresent([AutomationStep].self, forKey: .steps) ?? []
		self.init(
			id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
			schemaVersion: Self.currentSchemaVersion,
			name: try container.decodeIfPresent(String.self, forKey: .name) ?? "Automation",
			steps: decodedSteps
		)
	}

	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(id, forKey: .id)
		try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
		try container.encode(name, forKey: .name)
		try container.encode(steps, forKey: .steps)
	}
}
