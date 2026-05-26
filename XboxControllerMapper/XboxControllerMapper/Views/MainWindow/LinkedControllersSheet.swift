import SwiftUI

struct LinkedControllersSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var controllerService: ControllerService
    @Environment(\.dismiss) private var dismiss

    let profile: Profile

    private var liveProfile: Profile {
        profileManager.profiles.first(where: { $0.id == profile.id }) ?? profile
    }

    private var currentIdentity: ControllerIdentity? {
        controllerService.currentControllerIdentity
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Linked Controller")
                .font(.headline)

            Text("This profile will automatically activate when a linked controller connects, unless the frontmost app matches another profile's Linked Apps option.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            List {
                if liveProfile.linkedControllers.isEmpty {
                    Text("No controllers linked")
                        .foregroundColor(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(liveProfile.linkedControllers) { binding in
                        HStack(spacing: 10) {
                            Image(systemName: binding.identity.hasStableId ? "gamecontroller.fill" : "gamecontroller")
                                .foregroundColor(.accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(binding.displayName)
                                    .fontWeight(.medium)
                                Text(binding.identity.hasStableId ? "Stable ID" : "Model fallback")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button {
                                profileManager.removeLinkedController(binding.id, from: liveProfile)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.inset)
            .frame(height: 180)
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)

            currentControllerSummary

            HStack {
                Button {
                    if let currentIdentity {
                        profileManager.bindController(currentIdentity, to: liveProfile)
                    }
                } label: {
                    Label("Bind Current Controller", systemImage: "link")
                }
                .disabled(currentIdentity == nil)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 470)
    }

    @ViewBuilder
    private var currentControllerSummary: some View {
        if let identity = currentIdentity {
            HStack(spacing: 10) {
                Image(systemName: identity.hasStableId ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(identity.hasStableId ? .green : .yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Current: \(identity.displayName)")
                        .font(.caption)
                    Text(identity.hasStableId
                         ? "This controller exposes a stable hardware ID."
                         : "No stable hardware ID found; binding will match any same-model controller.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(10)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(8)
        } else {
            Text("Connect a controller to bind it to this profile.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
