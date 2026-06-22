import SwiftUI

// MARK: - Add Layer Sheet

struct AddLayerSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss

    @State private var layerName: String = ""
    @State private var selectedActivator: ControllerButton? = .leftBumper
    @State private var ledColor: Color = .blue

    private var controllerPresentationState: ControllerPresentationState {
		controllerService.threadSafeControllerPresentationState
    }

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
		let presentationState = controllerPresentationState
		if presentationState.isAppleTVRemote {
			candidates = [.view, .menu, .xbox, .siri]
		}
		// Add Edge-specific buttons when Edge controller is connected
		if presentationState.isDualSenseEdge {
			candidates.append(contentsOf: [.leftFunction, .rightFunction, .leftPaddle, .rightPaddle])
        }
        return candidates.filter { !usedActivators.contains($0) }
    }

    var body: some View {
		let presentationState = controllerPresentationState

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
							Text(button.displayName(
								forDualSense: presentationState.isPlayStation,
								forNintendo: presentationState.isNintendo,
								forAppleTVRemote: presentationState.isAppleTVRemote,
								forEightBitDo: presentationState.eightBitDoModel != nil
							))
							.tag(button as ControllerButton?)
						}
                    }
                    .pickerStyle(.menu)
                }

				if presentationState.isPlayStation {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Light Bar Color")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Lightbar shows this color while the layer is active")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ColorPicker("Color", selection: $ledColor, supportsOpacity: false)
                    }
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
                    if let layer = profileManager.createLayer(name: layerName, activatorButton: selectedActivator) {
                        // Override the auto-assigned color with the user's pick
                        var updated = layer
                        var led = updated.dualSenseLEDSettings ?? DualSenseLEDSettings()
                        led.lightBarColor = CodableColor(color: ledColor)
                        led.lightBarEnabled = true
                        updated.dualSenseLEDSettings = led
                        profileManager.updateLayer(updated)
                    }
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
            // Pre-fill color picker with the next distinct palette color
            // (matches what createLayer would auto-assign)
            let existingLayers = profileManager.activeProfile?.layers ?? []
            ledColor = LayerColorPalette.nextColor(usedBy: existingLayers).color
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
    @State private var enableCustomLED: Bool = false
    @State private var ledColor: Color = .blue

    private var controllerPresentationState: ControllerPresentationState {
		controllerService.threadSafeControllerPresentationState
    }

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
		let presentationState = controllerPresentationState
		if presentationState.isAppleTVRemote {
			candidates = [.view, .menu, .xbox, .siri]
		}
		// Add Edge-specific buttons when Edge controller is connected
		if presentationState.isDualSenseEdge {
			candidates.append(contentsOf: [.leftFunction, .rightFunction, .leftPaddle, .rightPaddle])
        }
        return candidates.filter { !usedActivators.contains($0) }
    }

    var body: some View {
		let presentationState = controllerPresentationState

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
							Text(button.displayName(
								forDualSense: presentationState.isPlayStation,
								forNintendo: presentationState.isNintendo,
								forAppleTVRemote: presentationState.isAppleTVRemote,
								forEightBitDo: presentationState.eightBitDoModel != nil
							))
							.tag(button as ControllerButton?)
						}
                    }
                    .pickerStyle(.menu)
                }

				if presentationState.isPlayStation {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Custom Light Bar Color", isOn: $enableCustomLED)
                            .font(.subheadline)

                        if enableCustomLED {
                            Text("Light bar changes to this color when the layer is active")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ColorPicker("Color", selection: $ledColor, supportsOpacity: false)
                        }
                    }
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
                    if enableCustomLED {
                        var ledSettings = DualSenseLEDSettings()
                        ledSettings.lightBarEnabled = true
                        ledSettings.lightBarColor = CodableColor(color: ledColor)
                        updatedLayer.dualSenseLEDSettings = ledSettings
                    } else {
                        updatedLayer.dualSenseLEDSettings = nil
                    }
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
            if let ledSettings = layer.dualSenseLEDSettings {
                enableCustomLED = true
                ledColor = ledSettings.lightBarColor.color
            }
        }
    }
}
