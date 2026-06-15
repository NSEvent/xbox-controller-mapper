import SwiftUI
import GameController

/// The main controller visual tab showing the button mapping diagram, layer bar,
/// and active chords/sequences.
struct ButtonMappingsTab: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var profileManager: ProfileManager
    @Binding var selectedButton: ControllerButton?
    @Binding var configuringButton: ControllerButton?
    @Binding var selectedLayerId: UUID?
    @Binding var isSwapMode: Bool
    @Binding var swapFirstButton: ControllerButton?
	@Binding var controllerPreviewLayout: ControllerPreviewLayout
    @Binding var showingAddLayerSheet: Bool
    @Binding var editingLayerId: UUID?
    @Binding var editingChord: ChordMapping?
    @Binding var editingSequence: SequenceMapping?
    @Binding var isMagnifying: Bool
    var actionFeedbackEnabled: Binding<Bool>
    var streamOverlayEnabled: Binding<Bool>
    @AppStorage(ButtonMappingsTabSection.hiddenDefaultsKey) private var hiddenSectionTags = ""

    // Canvas pan/zoom. The pan offset is view state (resets on relaunch);
    // the zoom factor is profileManager.uiScale (persisted in the config).
    @State private var canvasPan: CGSize = .zero
    @State private var panDragBase: CGSize?
    @State private var pinchBase: (scale: CGFloat, pan: CGSize, anchor: CGPoint)?
    @State private var canvasEventView: NSView?
    @State private var scrollPanMonitor: Any?

    /// Posted by the View > Reset Zoom menu command so the pan offset
    /// clears along with the scale.
    static let resetCanvasNotification = Notification.Name("ControllerKeysResetCanvas")

    private var hiddenSections: Set<ButtonMappingsTabSection> {
        ButtonMappingsTabSection.hiddenSections(from: hiddenSectionTags)
    }

    private func isSectionVisible(_ section: ButtonMappingsTabSection) -> Bool {
        !hiddenSections.contains(section)
    }

    // MARK: - Canvas pan/zoom helpers

    /// Keep at least part of the canvas content in view.
    private func clampedPan(_ pan: CGSize, in size: CGSize) -> CGSize {
        let scale = max(profileManager.uiScale, 0.5)
        let boundX = size.width * scale
        let boundY = size.height * scale
        return CGSize(
            width: min(max(pan.width, -boundX), boundX),
            height: min(max(pan.height, -boundY), boundY)
        )
    }

    /// Two-finger scroll over the canvas pans it (direct manipulation:
    /// content follows the fingers). Events outside the canvas pass through
    /// untouched so other scrollable areas keep working.
    private func installScrollPanMonitor() {
        guard scrollPanMonitor == nil else { return }
        scrollPanMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let canvasEventView,
                  let canvasWindow = canvasEventView.window else { return event }

            let pointerInCanvas: Bool
            if event.window === canvasWindow {
                let point = canvasEventView.convert(event.locationInWindow, from: nil)
                pointerInCanvas = canvasEventView.bounds.contains(point)
            } else {
                pointerInCanvas = false
            }

            guard CanvasScrollPanPolicy.shouldHandleScroll(
                pointerInCanvas: pointerInCanvas,
                eventWindowNumber: event.window?.windowNumber,
                canvasWindowNumber: canvasWindow.windowNumber,
                eventWindowHasAttachedSheet: event.window?.attachedSheet != nil,
                eventWindowIsSheet: event.window?.sheetParent != nil
            ) else { return event }

            canvasPan = clampedPan(
                CGSize(width: canvasPan.width + event.scrollingDeltaX,
                       height: canvasPan.height + event.scrollingDeltaY),
                in: canvasEventView.bounds.size
            )
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                LayerTabBar(
                    selectedLayerId: $selectedLayerId,
                    isSwapMode: $isSwapMode,
                    swapFirstButton: $swapFirstButton,
                    showingAddLayerSheet: $showingAddLayerSheet,
                    editingLayerId: $editingLayerId,
                    actionFeedbackEnabled: actionFeedbackEnabled,
                    streamOverlayEnabled: streamOverlayEnabled
                )

				layoutPreviewMenu

				// Scope the connect/disconnect animation to just this card so it
				// doesn't also cross-fade the picker label / mismatch note / layer
				// bar, which change on the same `isConnected` flip.
				Group {
					if !controllerService.isConnected {
						ControllerPairingHintView(
							previewLayout: controllerPreviewLayout,
							onSelectLayout: { controllerPreviewLayout = $0 }
						)
						.transition(.opacity.combined(with: .move(edge: .top)))
					}
				}
				.animation(.easeInOut(duration: 0.25), value: controllerService.isConnected)

                InputLogView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(0.13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.07), lineWidth: 1)
                        }

                    // Base size of ControllerVisualView content
                    let baseWidth: CGFloat = 920
                    let baseHeight: CGFloat = 580

                    // Calculate scale to fit available space (allow both up and down scaling)
                    let scaleX = geometry.size.width / baseWidth
                    let scaleY = geometry.size.height / baseHeight
                    let autoScale = min(scaleX, scaleY)

                    // Combine with user's manual zoom setting (and the
                    // per-variant zoom override in screenshot mode)
                    let finalScale = autoScale * profileManager.uiScale * (AppRuntime.screenshotZoom ?? 1)

                    ControllerVisualView(
                        selectedButton: $selectedButton,
                        selectedLayerId: selectedLayerId,
                        swapFirstButton: swapFirstButton,
                        isSwapMode: isSwapMode,
						previewLayout: controllerPreviewLayout,
                        onButtonTap: { button in
                            // Ignore taps during magnification gestures to prevent accidental triggers
                            guard !isMagnifying else { return }
                            // Async dispatch to avoid layout recursion if triggered during layout pass
                            DispatchQueue.main.async {
								handleButtonTap(button)
                            }
                        }
                    )
                    .scaleEffect(finalScale)
                    .offset(canvasPan)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(!isMagnifying)
                }
                .contentShape(Rectangle())
                // Drag empty canvas (or card backgrounds) to pan. Child
                // controls' own gestures still win for taps and button drags.
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if panDragBase == nil { panDragBase = canvasPan }
                            let base = panDragBase ?? .zero
                            canvasPan = clampedPan(
                                CGSize(width: base.width + value.translation.width,
                                       height: base.height + value.translation.height),
                                in: geometry.size
                            )
                        }
                        .onEnded { _ in panDragBase = nil }
                )
                // Pinch zooms toward the gesture location: the content point
                // under the fingers stays fixed while the scale changes.
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            isMagnifying = true
                            if pinchBase == nil {
                                pinchBase = (profileManager.uiScale, canvasPan, value.startLocation)
                            }
                            guard let base = pinchBase else { return }
                            let newScale = min(max(base.scale * value.magnification, 0.5), 2.0)
                            let k = newScale / base.scale
                            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                            let anchor = CGPoint(x: base.anchor.x - center.x, y: base.anchor.y - center.y)
                            canvasPan = clampedPan(
                                CGSize(width: anchor.x * (1 - k) + base.pan.width * k,
                                       height: anchor.y * (1 - k) + base.pan.height * k),
                                in: geometry.size
                            )
                            profileManager.uiScale = newScale
                        }
                        .onEnded { _ in
                            pinchBase = nil
                            profileManager.setUiScale(profileManager.uiScale)
                            // Delay resetting isMagnifying to prevent tap events that fire at gesture end
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(100))
                                isMagnifying = false
                            }
                        }
                )
                // Double-click empty canvas to re-center and reset zoom
                .onTapGesture(count: 2) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        canvasPan = .zero
                    }
                    profileManager.setUiScale(1.0)
                }
                .background(
                    CanvasScrollEventViewReader(view: $canvasEventView)
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .clipped()

            // Mapped Chords Display
            if isSectionVisible(.activeChords) {
                removableSection(.activeChords) {
                    ActiveChordsView(editingChord: $editingChord)
                }
            }

            // Mapped Sequences Display
            if isSectionVisible(.activeSequences) {
                removableSection(.activeSequences) {
                    ActiveSequencesView(editingSequence: $editingSequence)
                }
            }
        }
        .onAppear { installScrollPanMonitor() }
        .onDisappear {
            if let monitor = scrollPanMonitor {
                NSEvent.removeMonitor(monitor)
                scrollPanMonitor = nil
            }
            canvasEventView = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.resetCanvasNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                canvasPan = .zero
            }
        }
        .sheet(isPresented: $showingAddLayerSheet) {
            AddLayerSheet()
        }
        .sheet(item: $editingLayerId) { layerId in
            if let profile = profileManager.activeProfile,
               let layer = profile.layers.first(where: { $0.id == layerId }) {
                EditLayerSheet(layer: layer)
            }
        }
        .onChange(of: controllerService.activeButtons) { _, activeButtons in
            guard let profile = profileManager.activeProfile else { return }

            // Check if any layer activator is being held
            for layer in profile.layers {
				if let activator = layer.activatorButton,
				   activeButtonsContain(activator, in: activeButtons) {
                    selectedLayerId = layer.id
                    return
                }
            }

            // No layer activator held - return to base layer
            selectedLayerId = nil
        }
    }

	private var layoutPreviewMenu: some View {
		HStack {
			Menu {
				ForEach(ControllerPreviewLayout.allCases) { layout in
					Button {
						controllerPreviewLayout = layout
					} label: {
						if controllerPreviewLayout == layout {
							Label(layoutMenuTitle(for: layout), systemImage: "checkmark")
						} else {
							Label(layoutMenuTitle(for: layout), systemImage: layout.systemImage)
						}
					}
				}
			} label: {
				Label(controllerPreviewLayout.displayName, systemImage: controllerPreviewLayout.systemImage)
					.font(.system(size: 11, weight: .semibold))
					.padding(.horizontal, 10)
					.frame(height: 26)
					.background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
					.overlay(
						RoundedRectangle(cornerRadius: 7, style: .continuous)
							.stroke(Color.white.opacity(0.08), lineWidth: 1)
					)
			}
			.menuStyle(.borderlessButton)
			.help("Preview controller layout")

			if let note = layoutPreviewMismatchNote {
				Label(note, systemImage: "exclamationmark.triangle.fill")
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(Color.yellow.opacity(0.9))
					.lineLimit(1)
					.truncationMode(.tail)
					.help(note)
			}

			Spacer(minLength: 0)
		}
	}

	private var layoutPreviewMismatchNote: String? {
		guard controllerPreviewLayout != .active else { return nil }

		// When no controller is connected, the pairing-hint card owns the
		// messaging — suppress every mismatch warning so the two can't
		// contradict each other (the card says "No controller connected" while
		// this would say "Connected: …"). `connectedControllerPreviewLayouts` is
		// built from GCController / HID snapshots that aren't gated by
		// `isConnected`, so without this guard the non-empty branch below could
		// still fire mid-(dis)connect.
		guard controllerService.isConnected else { return nil }

		let connectedLayouts = connectedControllerPreviewLayouts
		guard !connectedLayouts.contains(controllerPreviewLayout) else { return nil }

		if connectedLayouts.isEmpty {
			return "No connected controller matches \(controllerPreviewLayout.displayName)"
		}

		let connectedNames = connectedLayouts
			.map(\.displayName)
			.sorted()
			.joined(separator: ", ")
		return "Connected: \(connectedNames); previewing \(controllerPreviewLayout.displayName)"
	}

	private func layoutMenuTitle(for layout: ControllerPreviewLayout) -> String {
		guard isLayoutCurrentlyConnected(layout) else { return layout.displayName }
		return "\(layout.displayName) 🟢"
	}

	private func isLayoutCurrentlyConnected(_ layout: ControllerPreviewLayout) -> Bool {
		guard layout != .active else { return false }
		return connectedControllerPreviewLayouts.contains(layout)
	}

	private var connectedControllerPreviewLayouts: Set<ControllerPreviewLayout> {
		var layouts = Set<ControllerPreviewLayout>()

		for controller in GCController.controllers() {
			layouts.formUnion(previewLayouts(for: controller))
		}

		if controllerService.isConnected {
			if controllerService.threadSafeIsAppleTVRemote {
				layouts.insert(.appleTVRemote)
			}
			if controllerService.threadSafeIsSteamController {
				layouts.insert(.steam)
			}
			if controllerService.threadSafeIsNintendo {
				layouts.insert(.nintendo)
			}
			if controllerService.threadSafeIsXboxElite {
				layouts.insert(.xboxElite)
			} else if controllerService.connectedController?.extendedGamepad is GCXboxGamepad {
				layouts.insert(.xbox)
			}
			if controllerService.threadSafeIsDualSenseEdge {
				layouts.insert(.dualSenseEdge)
			} else if controllerService.threadSafeIsDualSense {
				layouts.insert(.dualSense)
			}
			if controllerService.threadSafeIsDualShock {
				layouts.insert(.dualShock)
			}
			// Small 8BitDo pads connected in D-input mode (the generic HID
			// path identifies them by SDL product name). In Switch mode they
			// are byte-perfect Pro Controller clones and land on .nintendo.
			switch controllerService.threadSafeEightBitDoMinimapModel {
			case .zero2: layouts.insert(.eightBitDoZero2)
			case .micro: layouts.insert(.eightBitDoMicro)
			case .lite2: layouts.insert(.eightBitDoLite2)
			case .liteSE: layouts.insert(.eightBitDoLiteSE)
			case nil: break
			}
		}

		if controllerService.appleTVRemoteHIDDevice != nil || controllerService.appleTVRemoteHIDTouchDevice != nil {
			layouts.insert(.appleTVRemote)
		}

		return layouts
	}

	private func previewLayouts(for controller: GCController) -> Set<ControllerPreviewLayout> {
		if ControllerService.isAppleTVRemoteMetadata(
			vendorName: controller.vendorName,
			productCategory: controller.productCategory
		) {
			return [.appleTVRemote]
		}
		if ControllerService.isSteamControllerMetadata(
			vendorName: controller.vendorName,
			productCategory: controller.productCategory
		) {
			return [.steam]
		}
		if isNintendoMetadata(controller) {
			return [.nintendo]
		}
		if controller.extendedGamepad is GCXboxGamepad {
			if ControllerService.isEliteControllerMetadata(
				vendorName: controller.vendorName,
				productCategory: controller.productCategory
			) {
				return [.xboxElite]
			}
			return [.xbox]
		}
		if controller.extendedGamepad is GCDualSenseGamepad {
			if isDualSenseEdgeMetadata(controller) {
				return [.dualSenseEdge]
			}
			return [.dualSense]
		}
		if controller.extendedGamepad is GCDualShockGamepad {
			return [.dualShock]
		}
		return []
	}

	private func isDualSenseEdgeMetadata(_ controller: GCController) -> Bool {
		let combined = metadataString(for: controller)
		return combined.contains("dualsense edge") || combined.contains("edge")
	}

	private func isNintendoMetadata(_ controller: GCController) -> Bool {
		let combined = metadataString(for: controller)
		return combined.contains("joy-con")
			|| combined.contains("joycon")
			|| combined.contains("pro controller")
			|| combined.contains("nintendo")
	}

	private func metadataString(for controller: GCController) -> String {
		"\(controller.vendorName ?? "") \(controller.productCategory)".lowercased()
	}

    // MARK: - Swap Mode

	private func handleButtonTap(_ button: ControllerButton) {
		if isSwapMode {
			handleSwapButtonTap(button)
			return
		}

		if let layer = layerToOpen(for: button) {
			selectedLayerId = layer.id
			selectedButton = nil
			configuringButton = nil
			return
		}

		selectedButton = button
		configuringButton = button
	}

	private func layerToOpen(for button: ControllerButton) -> Layer? {
		guard let profile = profileManager.activeProfile,
			  let layer = profile.layers.first(where: { $0.activatorButton == button }),
			  selectedLayerId == nil || selectedLayerId == layer.id else {
			return nil
		}
		return layer
	}

	private func activeButtonsContain(
		_ button: ControllerButton,
		in activeButtons: Set<ControllerButton>
	) -> Bool {
		activeButtons.contains(button) ||
			button.physicalEquivalentButtons.contains { activeButtons.contains($0) }
	}

    private func handleSwapButtonTap(_ button: ControllerButton) {
        if let firstButton = swapFirstButton {
            // Second button selected - perform the swap
            if let layerId = selectedLayerId {
                profileManager.swapLayerMappings(button1: firstButton, button2: button, in: layerId)
            } else {
                profileManager.swapMappings(button1: firstButton, button2: button)
            }
            // Exit swap mode
            swapFirstButton = nil
            isSwapMode = false
        } else {
            // First button selected
            swapFirstButton = button
        }
    }

    @ViewBuilder
    private func removableSection<Content: View>(
        _ section: ButtonMappingsTabSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .overlay(alignment: .topTrailing) {
                Button {
                    hideSection(section)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.secondary)
                        .background(.regularMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help("Hide \(section.label)")
                .accessibilityLabel("Hide \(section.label)")
                .padding(.top, 6)
                .padding(.trailing, 8)
            }
    }

    private func hideSection(_ section: ButtonMappingsTabSection) {
        var currentHiddenSections = hiddenSections
        currentHiddenSections.insert(section)
        hiddenSectionTags = ButtonMappingsTabSection.encodedHiddenSections(currentHiddenSections)
    }
}

enum ButtonMappingsTabSection: Int, CaseIterable, Identifiable {
    case activeChords = 3
    case activeSequences = 4

    static let hiddenDefaultsKey = "hiddenButtonMappingsTabSectionTags"

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .activeChords: return "Active Chords"
        case .activeSequences: return "Active Sequences"
        }
    }

    static func hiddenSections(from rawValue: String) -> Set<ButtonMappingsTabSection> {
        Set(rawValue
            .split(separator: ",")
            .compactMap { Int(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .compactMap(ButtonMappingsTabSection.init(rawValue:))
        )
    }

    static func encodedHiddenSections(_ sections: Set<ButtonMappingsTabSection>) -> String {
        sections
            .map(\.rawValue)
            .sorted()
            .map { String($0) }
            .joined(separator: ",")
    }
}
