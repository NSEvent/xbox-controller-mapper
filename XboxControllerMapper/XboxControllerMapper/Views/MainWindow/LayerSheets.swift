import SwiftUI

// MARK: - Add Layer Sheet

struct AddLayerSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss

    @State private var layerName: String = ""
    @State private var selectedActivator: ControllerButton? = .leftBumper

    /// Buttons that are already used as layer activators
    private var usedActivators: Set<ControllerButton> {
        Set(profileManager.activeProfile?.layers.compactMap { $0.activatorButton } ?? [])
    }

    /// Available activator buttons (exclude already-used ones)
    private var availableButtons: [ControllerButton] {
        // Good candidates for layer activators: bumpers, triggers, share, view, menu
        var candidates: [ControllerButton] = [
            .leftBumper, .rightBumper, .leftTrigger, .rightTrigger,
            .share, .view, .menu, .xbox,
            .leftThumbstick, .rightThumbstick
        ]
        // Add Edge-specific buttons when Edge controller is connected
        if controllerService.threadSafeIsDualSenseEdge {
            candidates.append(contentsOf: [.leftFunction, .rightFunction, .leftPaddle, .rightPaddle])
        }
        return candidates.filter { !usedActivators.contains($0) }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Layer")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Layer Name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("e.g., Combat Mode", text: $layerName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Activator Button (Optional)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Hold this button to activate the layer's mappings")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Activator", selection: $selectedActivator) {
                        Text("None (assign later)").tag(nil as ControllerButton?)
                        ForEach(availableButtons, id: \.self) { button in
                            Text(button.displayName(forDualSense: controllerService.threadSafeIsPlayStation))
                                .tag(button as ControllerButton?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.horizontal)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add Layer") {
                    guard !layerName.isEmpty else { return }
                    _ = profileManager.createLayer(name: layerName, activatorButton: selectedActivator)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(layerName.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            // Select first available activator
            if let first = availableButtons.first {
                selectedActivator = first
            }
        }
    }
}

// MARK: - Edit Layer Sheet

struct EditLayerSheet: View {
    let layer: Layer

    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss

    @State private var layerName: String = ""
    @State private var selectedActivator: ControllerButton? = .leftBumper

    /// Buttons that are already used as layer activators (excluding current layer)
    private var usedActivators: Set<ControllerButton> {
        Set(profileManager.activeProfile?.layers
            .filter { $0.id != layer.id }
            .compactMap { $0.activatorButton } ?? [])
    }

    /// Available activator buttons (exclude already-used ones, but include current)
    private var availableButtons: [ControllerButton] {
        var candidates: [ControllerButton] = [
            .leftBumper, .rightBumper, .leftTrigger, .rightTrigger,
            .share, .view, .menu, .xbox,
            .leftThumbstick, .rightThumbstick
        ]
        // Add Edge-specific buttons when Edge controller is connected
        if controllerService.threadSafeIsDualSenseEdge {
            candidates.append(contentsOf: [.leftFunction, .rightFunction, .leftPaddle, .rightPaddle])
        }
        return candidates.filter { !usedActivators.contains($0) }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Edit Layer")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Layer Name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("Layer name", text: $layerName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Activator Button")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Picker("Activator", selection: $selectedActivator) {
                        Text("None (assign later)").tag(nil as ControllerButton?)
                        ForEach(availableButtons, id: \.self) { button in
                            Text(button.displayName(forDualSense: controllerService.threadSafeIsPlayStation))
                                .tag(button as ControllerButton?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.horizontal)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    guard !layerName.isEmpty else { return }
                    var updatedLayer = layer
                    updatedLayer.name = layerName
                    updatedLayer.activatorButton = selectedActivator
                    profileManager.updateLayer(updatedLayer)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(layerName.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 350)
        .onAppear {
            layerName = layer.name
            selectedActivator = layer.activatorButton
        }
    }
}
