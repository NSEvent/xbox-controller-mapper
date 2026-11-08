import SwiftUI

// MARK: - Add Layer Sheet

struct AddLayerSheet: View, MappingControllerTypeProviding {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss
	@State private var editorScope = MappingEditorScope()

    @State private var layerName: String = ""
    @State private var selectedActivator: ControllerButton? = nil
    @State private var activationStyle: LayerActivationStyle = .hold
    @State private var ledColor: Color = .blue

    /// Buttons that are already used as layer activators
    private var usedActivators: Set<ControllerButton> {
        Set(profileManager.activeProfile?.layers.compactMap { $0.activatorButton } ?? [])
    }

    private var availableButtons: [ControllerButton] {
		LayerActivatorOptions.buttons(for: controllerPresentationState, excluding: usedActivators)
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

					LayerActivatorPicker(selection: $selectedActivator, descriptor: presentationState,
						used: usedActivators)
                }

				VStack(alignment: .leading, spacing: 4) {
					Text("Activation Style")
						.font(.subheadline)
						.foregroundColor(.secondary)

					Picker("Activation Style", selection: $activationStyle) {
						ForEach(LayerActivationStyle.allCases) { style in
							Text(style.displayName).tag(style)
						}
					}
					.pickerStyle(.segmented)

					Text(activationStyle.helpText)
					.font(.caption)
					.foregroundColor(.secondary)
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
					guard editorScope.canSave(to: profileManager.activeProfileId), !layerName.isEmpty else { return }
					if let layer = profileManager.createLayer(
						name: layerName,
						activatorButton: selectedActivator,
						activationStyle: activationStyle
					) {
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
		.mappingEditorScope($editorScope, profileId: profileManager.activeProfileId)
        .onAppear {
            // Select first available activator
			selectedActivator = availableButtons.first
            // Pre-fill color picker with the next distinct palette color
            // (matches what createLayer would auto-assign)
            let existingLayers = profileManager.activeProfile?.layers ?? []
            ledColor = LayerColorPalette.nextColor(usedBy: existingLayers).color
        }
    }
}

// MARK: - Edit Layer Sheet

struct EditLayerSheet: View, MappingControllerTypeProviding {
    let layer: Layer

    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss
	@State private var editorScope = MappingEditorScope()

    @State private var layerName: String = ""
    @State private var selectedActivator: ControllerButton? = nil
    @State private var activationStyle: LayerActivationStyle = .hold
	@State private var enableLayerLEDOverride: Bool = false
	@State private var ledColor: Color = .blue

    /// Buttons that are already used as layer activators (excluding current layer)
    private var usedActivators: Set<ControllerButton> {
        Set(profileManager.activeProfile?.layers
            .filter { $0.id != layer.id }
            .compactMap { $0.activatorButton } ?? [])
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

					LayerActivatorPicker(selection: $selectedActivator, descriptor: presentationState,
						used: usedActivators, existing: layer.activatorButton)
                }

				VStack(alignment: .leading, spacing: 4) {
					Text("Activation Style")
						.font(.subheadline)
						.foregroundColor(.secondary)

					Picker("Activation Style", selection: $activationStyle) {
						ForEach(LayerActivationStyle.allCases) { style in
							Text(style.displayName).tag(style)
						}
					}
					.pickerStyle(.segmented)

					Text(activationStyle.helpText)
					.font(.caption)
					.foregroundColor(.secondary)
				}

				if presentationState.isPlayStation {
                    VStack(alignment: .leading, spacing: 4) {
						Toggle("Layer LED Override", isOn: $enableLayerLEDOverride)
							.font(.subheadline)

						if enableLayerLEDOverride {
							Text("Selecting a color enables the light bar and turns off battery color.")
								.font(.caption)
								.foregroundColor(.secondary)

							ColorPicker("Color", selection: $ledColor, supportsOpacity: false)
						} else if layer.dualSenseLEDSettings != nil {
							Text("Turning this off removes all LED settings for this layer.")
								.font(.caption)
								.foregroundColor(.secondary)
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
					guard editorScope.canSave(to: profileManager.activeProfileId), !layerName.isEmpty else { return }
                    var updatedLayer = layer
                    updatedLayer.name = layerName
                    updatedLayer.activatorButton = selectedActivator
					updatedLayer.activationStyle = activationStyle
					updatedLayer.dualSenseLEDSettings = LayerLEDSettingsPolicy.applyingColorEdit(
						to: updatedLayer.dualSenseLEDSettings,
						isEnabled: enableLayerLEDOverride,
						color: CodableColor(color: ledColor),
						didEditColor: didChangeLEDColor
					)
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
		.mappingEditorScope($editorScope, profileId: profileManager.activeProfileId)
        .onAppear {
            layerName = layer.name
            selectedActivator = layer.activatorButton
			activationStyle = layer.activationStyle
			if let ledSettings = layer.dualSenseLEDSettings {
				enableLayerLEDOverride = true
				ledColor = ledSettings.lightBarColor.color
			}
		}
    }

	private var didChangeLEDColor: Bool {
		guard let existing = layer.dualSenseLEDSettings?.lightBarColor else { return true }
		let selected = CodableColor(color: ledColor)
		return (existing.redByte, existing.greenByte, existing.blueByte)
			!= (selected.redByte, selected.greenByte, selected.blueByte)
	}
}
