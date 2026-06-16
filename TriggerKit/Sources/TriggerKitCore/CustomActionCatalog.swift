import Foundation

/// One choice in a `.picker` option. `value` is what gets stored in the payload;
/// `label` is what the editor shows.
public struct PickerChoice: Equatable, Sendable, Identifiable {
	public let value: String
	public let label: String

	public var id: String { value }

	public init(value: String, label: String) {
		self.value = value
		self.label = label
	}
}

/// A single user-editable option on a registered custom action. Values live in
/// the `CustomStep.payload` JSON, keyed by `key`. Toggles store a Bool; text and
/// picker fields store a String; number fields store a Double. Extend `Kind` with
/// more cases as hosts need them.
public struct CustomActionOption: Equatable, Sendable, Identifiable {
	public enum Kind: Equatable, Sendable {
		case toggle(default: Bool)
		case text(default: String, placeholder: String)
		case number(default: Double, range: ClosedRange<Double>, step: Double)
		case picker(default: String, choices: [PickerChoice])
	}

	public let key: String
	public let label: String
	public let help: String?
	public let kind: Kind

	public var id: String { key }

	public init(key: String, label: String, help: String? = nil, kind: Kind) {
		self.key = key
		self.label = label
		self.help = help
		self.kind = kind
	}

	public static func toggle(
		key: String,
		label: String,
		help: String? = nil,
		default defaultValue: Bool
	) -> CustomActionOption {
		CustomActionOption(key: key, label: label, help: help, kind: .toggle(default: defaultValue))
	}

	public static func text(
		key: String,
		label: String,
		help: String? = nil,
		default defaultValue: String = "",
		placeholder: String = ""
	) -> CustomActionOption {
		CustomActionOption(key: key, label: label, help: help, kind: .text(default: defaultValue, placeholder: placeholder))
	}

	public static func number(
		key: String,
		label: String,
		help: String? = nil,
		default defaultValue: Double,
		range: ClosedRange<Double>,
		step: Double = 1
	) -> CustomActionOption {
		CustomActionOption(key: key, label: label, help: help, kind: .number(default: defaultValue, range: range, step: step))
	}

	public static func picker(
		key: String,
		label: String,
		help: String? = nil,
		default defaultValue: String,
		choices: [PickerChoice]
	) -> CustomActionOption {
		CustomActionOption(key: key, label: label, help: help, kind: .picker(default: defaultValue, choices: choices))
	}
}

/// Describes a host-provided `.custom` action so the shared editor can offer it
/// in the "Add" menu and render a friendly options form instead of a raw
/// namespace/payload box. The host still owns execution via
/// `TriggerExecutionContext.stepOverride`.
public struct CustomActionDescriptor: Equatable, Sendable, Identifiable {
	public let namespace: String
	public let title: String
	public let systemImage: String
	/// Optional menu grouping. Descriptors sharing a category are listed together
	/// under a section header in the editor's "Add" menu; `nil` lists ungrouped.
	public let category: String?
	public let options: [CustomActionOption]

	public var id: String { namespace }

	public init(
		namespace: String,
		title: String,
		systemImage: String = "puzzlepiece.extension",
		category: String? = nil,
		options: [CustomActionOption] = []
	) {
		self.namespace = namespace
		self.title = title
		self.systemImage = systemImage
		self.category = category
		self.options = options
	}

	/// JSON payload pre-filled with each option's default value.
	public var defaultPayload: String {
		var dict: [String: Any] = [:]
		for option in options {
			switch option.kind {
			case .toggle(let defaultValue): dict[option.key] = defaultValue
			case .text(let defaultValue, _): dict[option.key] = defaultValue
			case .number(let defaultValue, _, _): dict[option.key] = defaultValue
			case .picker(let defaultValue, _): dict[option.key] = defaultValue
			}
		}
		return CustomActionPayload.encode(dict)
	}

	/// A ready-to-insert step carrying this action's namespace, defaults, and
	/// title (so rows display the friendly name).
	public func makeStep() -> CustomStep {
		CustomStep(namespace: namespace, payload: defaultPayload, displayName: title)
	}
}

/// Read/write helpers for the JSON object stored in `CustomStep.payload`.
/// Values are booleans (toggles) or strings (text fields). Tolerant of
/// malformed payloads — falls back to defaults rather than throwing.
public enum CustomActionPayload {
	public static func encode(_ dict: [String: Any]) -> String {
		guard
			JSONSerialization.isValidJSONObject(dict),
			let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
			let string = String(data: data, encoding: .utf8)
		else {
			return "{}"
		}
		return string
	}

	public static func bool(_ key: String, in payload: String, default fallback: Bool) -> Bool {
		object(from: payload)[key] as? Bool ?? fallback
	}

	public static func string(_ key: String, in payload: String, default fallback: String) -> String {
		object(from: payload)[key] as? String ?? fallback
	}

	public static func double(_ key: String, in payload: String, default fallback: Double) -> Double {
		let value = object(from: payload)[key]
		if let number = value as? NSNumber { return number.doubleValue }
		if let string = value as? String, let parsed = Double(string) { return parsed }
		return fallback
	}

	public static func setting(_ value: Bool, for key: String, in payload: String) -> String {
		var object = object(from: payload)
		object[key] = value
		return encode(object)
	}

	public static func setting(_ value: Double, for key: String, in payload: String) -> String {
		var object = object(from: payload)
		object[key] = value
		return encode(object)
	}

	public static func setting(_ value: String, for key: String, in payload: String) -> String {
		var object = object(from: payload)
		object[key] = value
		return encode(object)
	}

	private static func object(from payload: String) -> [String: Any] {
		guard
			let data = payload.data(using: .utf8),
			let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		else {
			return [:]
		}
		return decoded
	}
}

/// Process-wide registry of host-provided custom actions. The host registers
/// descriptors at launch; the shared editor reads them to populate its menu and
/// option forms. Empty by default, so hosts that register nothing see no change.
@MainActor
public final class CustomActionRegistry {
	public static let shared = CustomActionRegistry()

	public private(set) var descriptors: [CustomActionDescriptor] = []

	private init() {}

	/// Registers (or replaces, by namespace) a descriptor. Idempotent.
	public func register(_ descriptor: CustomActionDescriptor) {
		if let index = descriptors.firstIndex(where: { $0.namespace == descriptor.namespace }) {
			descriptors[index] = descriptor
		} else {
			descriptors.append(descriptor)
		}
	}

	public func descriptor(for namespace: String) -> CustomActionDescriptor? {
		descriptors.first { $0.namespace == namespace }
	}
}
