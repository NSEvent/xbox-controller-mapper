import Foundation
import SwiftUI

/// A stable view of the stored order. Compatibility requires every control;
/// a mixed-device trigger belongs in Other mappings, not both sections.
struct ControllerMappingGroup<Item: Identifiable>: Identifiable {
	enum Kind: String { case compatible, other, all }
	let id: Kind
	let title: String
	let items: [Item]
}

enum ControllerMappingGroups {
	static func sections<Item: Identifiable>(of items: [Item], descriptor: ControllerVisualDescriptor?,
		buttons: (Item) -> Set<ControllerButton>) -> [ControllerMappingGroup<Item>] {
		guard let descriptor else { return items.isEmpty ? [] : [.init(id: .all, title: "All mappings", items: items)] }
		let compatible = items.filter { !buttons($0).isEmpty && buttons($0).isSubset(of: descriptor.supportedButtons) }
		let ids = Set(compatible.map(\.id))
		let other = items.filter { !ids.contains($0.id) }
		// Keep an empty active section visible: it explains where a newly
		// created mapping for this device will appear.
		var groups: [ControllerMappingGroup<Item>] = [.init(id: .compatible, title: "For \(descriptor.displayName)", items: compatible)]
		if !other.isEmpty { groups.append(.init(id: .other, title: "Other mappings", items: other)) }
		return groups
	}

	/// Reorder only this section's original slots. Other devices' relative
	/// order and slots stay intact. Reject stale drags after edits or switches.
	static func moving<Item: Identifiable>(_ items: [Item], visibleIDs: [Item.ID], from source: IndexSet, to destination: Int) -> [Item]? {
		let ids = Set(visibleIDs)
		let slots = items.indices.filter { ids.contains(items[$0].id) }
		guard ids.count == visibleIDs.count,
			slots.map({ items[$0].id }) == visibleIDs,
			!source.isEmpty, source.allSatisfy({ visibleIDs.indices.contains($0) }),
			(0...visibleIDs.count).contains(destination) else { return nil }
		var visible = slots.map { items[$0] }
		visible.move(fromOffsets: source, toOffset: destination)
		var result = items
		for (slot, item) in zip(slots, visible) { result[slot] = item }
		return result
	}
}
