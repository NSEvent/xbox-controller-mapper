import Foundation

public extension AutomationProgram {
	/// Decodes through the explicit schema migration pipeline. Regular
	/// `Decodable` remains strict: unknown future step kinds and unsupported
	/// future schema versions still fail closed.
	static func decodeMigrating(
		from data: Data,
		decoder: JSONDecoder = JSONDecoder()
	) throws -> AutomationProgram {
		let envelope = try decoder.decode(AutomationProgramSchemaEnvelope.self, from: data)
		let sourceVersion = envelope.schemaVersion ?? Self.currentSchemaVersion
		guard sourceVersion >= 1 else {
			throw DecodingError.dataCorrupted(DecodingError.Context(
				codingPath: [],
				debugDescription: "Unsupported automation schema version \(sourceVersion)"
			))
		}
		guard sourceVersion <= Self.currentSchemaVersion else {
			throw DecodingError.dataCorrupted(DecodingError.Context(
				codingPath: [],
				debugDescription: "Unsupported automation schema version \(sourceVersion)"
			))
		}
		guard sourceVersion < Self.currentSchemaVersion else {
			return try decoder.decode(Self.self, from: data)
		}

		var object = try mutableJSONObject(from: data)
		var version = sourceVersion
		while version < Self.currentSchemaVersion {
			object = try migrateJSONObject(object, from: version)
			version += 1
		}

		let migrated = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
		return try decoder.decode(Self.self, from: migrated)
	}

	private static func mutableJSONObject(from data: Data) throws -> [String: Any] {
		guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			throw DecodingError.dataCorrupted(DecodingError.Context(
				codingPath: [],
				debugDescription: "Automation program JSON must be an object"
			))
		}
		return object
	}

	private static func migrateJSONObject(_ object: [String: Any], from version: Int) throws -> [String: Any] {
		var migrated = object
		switch version {
		case 1:
			// v1 and v2 share the same payload shape. Keep this as a real
			// migration hop so future v2/v3 transforms have a single entry point.
			migrated["schemaVersion"] = 2
			return migrated
		default:
			throw DecodingError.dataCorrupted(DecodingError.Context(
				codingPath: [],
				debugDescription: "No migration registered from automation schema version \(version)"
			))
		}
	}
}

private struct AutomationProgramSchemaEnvelope: Decodable {
	var schemaVersion: Int?
}
