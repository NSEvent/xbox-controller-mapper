import Foundation
import SwiftUI

@MainActor
extension ProfileManager {
    // MARK: - Button Mapping

    func setMapping(_ mapping: KeyMapping, for button: ControllerButton, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.buttonMappings[button] = mapping
        updateProfile(targetProfile)
    }

    func removeMapping(for button: ControllerButton, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.buttonMappings.removeValue(forKey: button)
        updateProfile(targetProfile)
    }

    func getMapping(for button: ControllerButton, in profile: Profile? = nil) -> KeyMapping? {
        let targetProfile = profile ?? activeProfile
        return targetProfile?.buttonMappings[button]
    }

    /// Swaps all mappings between two buttons (base layer only, does not affect chords)
    func swapMappings(button1: ControllerButton, button2: ControllerButton, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }
        guard button1 != button2 else { return }

        // Get current mappings (may be nil)
        let mapping1 = targetProfile.buttonMappings[button1]
        let mapping2 = targetProfile.buttonMappings[button2]

        // Swap the mappings
        if let m2 = mapping2 {
            targetProfile.buttonMappings[button1] = m2
        } else {
            targetProfile.buttonMappings.removeValue(forKey: button1)
        }

        if let m1 = mapping1 {
            targetProfile.buttonMappings[button2] = m1
        } else {
            targetProfile.buttonMappings.removeValue(forKey: button2)
        }

        updateProfile(targetProfile)
    }

    /// Swaps all mappings between two buttons within a specific layer
    func swapLayerMappings(button1: ControllerButton, button2: ControllerButton, in layerId: UUID, profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }
        guard button1 != button2 else { return }
        guard let layerIndex = targetProfile.layers.firstIndex(where: { $0.id == layerId }) else { return }

        var layer = targetProfile.layers[layerIndex]

        // Get current layer mappings (may be nil)
        let mapping1 = layer.buttonMappings[button1]
        let mapping2 = layer.buttonMappings[button2]

        // Swap the mappings
        if let m2 = mapping2 {
            layer.buttonMappings[button1] = m2
        } else {
            layer.buttonMappings.removeValue(forKey: button1)
        }

        if let m1 = mapping1 {
            layer.buttonMappings[button2] = m1
        } else {
            layer.buttonMappings.removeValue(forKey: button2)
        }

        targetProfile.layers[layerIndex] = layer
        updateProfile(targetProfile)
    }

    // MARK: - Chord Mapping

    func addChord(_ chord: ChordMapping, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.chordMappings.append(chord)
        updateProfile(targetProfile)
    }

    func removeChord(_ chord: ChordMapping, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.chordMappings.removeAll { $0.id == chord.id }
        updateProfile(targetProfile)
    }

    func updateChord(_ chord: ChordMapping, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        if let index = targetProfile.chordMappings.firstIndex(where: { $0.id == chord.id }) {
            targetProfile.chordMappings[index] = chord
        }
        updateProfile(targetProfile)
    }

    func moveChords(from source: IndexSet, to destination: Int, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.chordMappings.move(fromOffsets: source, toOffset: destination)
        updateProfile(targetProfile)
    }

    // MARK: - Sequence Mapping

    func addSequence(_ sequence: SequenceMapping, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.sequenceMappings.append(sequence)
        updateProfile(targetProfile)
    }

    func removeSequence(_ sequence: SequenceMapping, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.sequenceMappings.removeAll { $0.id == sequence.id }
        updateProfile(targetProfile)
    }

    func updateSequence(_ sequence: SequenceMapping, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        if let index = targetProfile.sequenceMappings.firstIndex(where: { $0.id == sequence.id }) {
            targetProfile.sequenceMappings[index] = sequence
        }
        updateProfile(targetProfile)
    }

    func moveSequences(from source: IndexSet, to destination: Int, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.sequenceMappings.move(fromOffsets: source, toOffset: destination)
        updateProfile(targetProfile)
    }

    // MARK: - Gesture Mapping

    func addGesture(_ gesture: GestureMapping, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.gestureMappings.append(gesture)
        updateProfile(targetProfile)
    }

    func removeGesture(_ gesture: GestureMapping, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.gestureMappings.removeAll { $0.id == gesture.id }
        updateProfile(targetProfile)
    }

    func updateGesture(_ gesture: GestureMapping, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        if let index = targetProfile.gestureMappings.firstIndex(where: { $0.id == gesture.id }) {
            targetProfile.gestureMappings[index] = gesture
        }
        updateProfile(targetProfile)
    }

    /// Returns the gesture mapping for a given gesture type, if one exists
    func gestureMapping(for gestureType: MotionGestureType, in profile: Profile? = nil) -> GestureMapping? {
        let targetProfile = profile ?? activeProfile
        return targetProfile?.gestureMappings.first(where: { $0.gestureType == gestureType })
    }

    // MARK: - Layer Management

    /// Maximum number of layers allowed per profile
    static let maxLayers = 12

    /// Creates a new layer with the given name and optional activator button.
    /// Returns nil if max layers reached or activator already used.
    func createLayer(name: String, activatorButton: ControllerButton? = nil, in profile: Profile? = nil) -> Layer? {
        guard var targetProfile = profile ?? activeProfile else { return nil }

        // Check max layers limit
        guard targetProfile.layers.count < Self.maxLayers else { return nil }

        // Check if activator button is already used by another layer
        if let button = activatorButton,
           targetProfile.layers.contains(where: { $0.activatorButton == button }) {
            return nil
        }

        let layer = Layer(name: name, activatorButton: activatorButton)
        targetProfile.layers.append(layer)
        updateProfile(targetProfile)
        return layer
    }

    /// Updates an existing layer in the profile
    func updateLayer(_ layer: Layer, in profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        if let index = targetProfile.layers.firstIndex(where: { $0.id == layer.id }) {
            targetProfile.layers[index] = layer
        }
        updateProfile(targetProfile)
    }

    /// Deletes a layer from the profile
    func deleteLayer(_ layer: Layer, from profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }

        targetProfile.layers.removeAll { $0.id == layer.id }
        updateProfile(targetProfile)
    }

    /// Sets a button mapping within a specific layer
    func setLayerMapping(_ mapping: KeyMapping, for button: ControllerButton, in layer: Layer, profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }
        guard let layerIndex = targetProfile.layers.firstIndex(where: { $0.id == layer.id }) else { return }

        targetProfile.layers[layerIndex].buttonMappings[button] = mapping
        updateProfile(targetProfile)
    }

    /// Removes a button mapping from a specific layer
    func removeLayerMapping(for button: ControllerButton, from layer: Layer, profile: Profile? = nil) {
        guard var targetProfile = profile ?? activeProfile else { return }
        guard let layerIndex = targetProfile.layers.firstIndex(where: { $0.id == layer.id }) else { return }

        targetProfile.layers[layerIndex].buttonMappings.removeValue(forKey: button)
        updateProfile(targetProfile)
    }

    /// Returns the layer that uses the given activator button, if any
    func layerForActivator(_ button: ControllerButton, in profile: Profile? = nil) -> Layer? {
        let targetProfile = profile ?? activeProfile
        return targetProfile?.layers.first(where: { $0.activatorButton == button })
    }

    /// Renames a layer
    func renameLayer(_ layer: Layer, to newName: String, in profile: Profile? = nil) {
        var updatedLayer = layer
        updatedLayer.name = newName
        updateLayer(updatedLayer, in: profile)
    }

    /// Changes a layer's activator button, or removes it if nil.
    /// Returns false if the new button is already used by another layer.
    func setLayerActivator(_ layer: Layer, button: ControllerButton?, in profile: Profile? = nil) -> Bool {
        guard var targetProfile = profile ?? activeProfile else { return false }

        // Check if button is already used by another layer (only if setting a button)
        if let button = button,
           targetProfile.layers.contains(where: { $0.id != layer.id && $0.activatorButton == button }) {
            return false
        }

        if let index = targetProfile.layers.firstIndex(where: { $0.id == layer.id }) {
            targetProfile.layers[index].activatorButton = button
            updateProfile(targetProfile)
            return true
        }
        return false
    }

    /// Returns layers that don't have an activator button assigned
    func unassignedLayers(in profile: Profile? = nil) -> [Layer] {
        let targetProfile = profile ?? activeProfile
        return targetProfile?.layers.filter { $0.activatorButton == nil } ?? []
    }
}
