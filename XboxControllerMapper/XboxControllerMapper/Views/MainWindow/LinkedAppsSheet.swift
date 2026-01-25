import SwiftUI

struct LinkedAppsSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var appMonitor: AppMonitor
    @Environment(\.dismiss) private var dismiss

    let profile: Profile
    @State private var showingAppPicker = false

    private var liveProfile: Profile {
        profileManager.profiles.first(where: { $0.id == profile.id }) ?? profile
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Linked Apps")
                .font(.headline)

            Text("This profile will automatically activate when any of these apps are in the front.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            List {
                if liveProfile.linkedApps.isEmpty {
                    Text("No apps linked")
                        .foregroundColor(.secondary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(liveProfile.linkedApps, id: \.self) { bundleId in
                        HStack {
                            if let appInfo = appMonitor.appInfo(for: bundleId) {
                                if let icon = appInfo.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                }
                                Text(appInfo.name)
                                    .fontWeight(.medium)
                                Text("(\(bundleId))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(bundleId)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                profileManager.removeLinkedApp(bundleId, from: liveProfile)
                            }) {
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
            .frame(height: 200)
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)

            HStack {
                Button(action: { showingAppPicker = true }) {
                    Label("Add App...", systemImage: "plus")
                }
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 450)
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet(profile: liveProfile)
        }
    }
}

struct AppPickerSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var appMonitor: AppMonitor
    @Environment(\.dismiss) private var dismiss
    
    let profile: Profile
    @State private var searchText = ""
    @State private var selectedTab = 0 // 0 = Running, 1 = Installed
    
    private var liveProfile: Profile {
        profileManager.profiles.first(where: { $0.id == profile.id }) ?? profile
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Select App")
                .font(.headline)
                
            Picker("", selection: $selectedTab) {
                Text("Running").tag(0)
                Text("Installed").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
            
            List {
                let apps = getFilteredApps()
                
                ForEach(apps) { app in
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 32, height: 32)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(app.name)
                                .fontWeight(.medium)
                            Text(app.bundleIdentifier)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if liveProfile.linkedApps.contains(app.bundleIdentifier) {
                            Text("Linked")
                                .font(.caption)
                                .foregroundColor(.green)
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button("Add") {
                                profileManager.addLinkedApp(app.bundleIdentifier, to: liveProfile)
                                dismiss()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
            .frame(height: 400)
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)
            
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 500)
    }
    
    private func getFilteredApps() -> [AppInfo] {
        let apps = selectedTab == 0 ? appMonitor.runningApplications : appMonitor.installedApplications
        if searchText.isEmpty {
            return apps
        }
        return apps.filter { 
            $0.name.localizedCaseInsensitiveContains(searchText) || 
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }
}
