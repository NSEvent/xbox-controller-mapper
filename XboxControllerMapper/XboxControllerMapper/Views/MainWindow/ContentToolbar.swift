import SwiftUI

/// Toolbar displayed at the top of the main content area showing connection status,
/// mapping toggle, and settings button.
struct ContentToolbar: View {
    @EnvironmentObject var controllerService: ControllerService
    @EnvironmentObject var mappingEngine: MappingEngine
    @Binding var showingSettingsSheet: Bool

    var body: some View {
        HStack {
            // Connection status
            HStack(spacing: 8) {
                Circle()
                    .fill(controllerService.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: (controllerService.isConnected ? Color.green : Color.red).opacity(0.6), radius: 4)

                Text(controllerService.isConnected ? controllerService.controllerName : "No Controller")
                    .font(.caption.bold())
                    .foregroundColor(controllerService.isConnected ? .white : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.3))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)

            Spacer()

            // Enable/disable toggle
            MappingActiveToggle(isEnabled: $mappingEngine.isEnabled)

            Button {
                showingSettingsSheet = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .hoverableIconButton()
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Transparent toolbar to let glass show through
    }
}
