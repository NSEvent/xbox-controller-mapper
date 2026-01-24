import SwiftUI
import AppKit

/// Settings view for the on-screen keyboard feature
struct OnScreenKeyboardSettingsView: View {
    @EnvironmentObject var profileManager: ProfileManager

    @State private var newTextSnippet = ""
    @State private var newTerminalCommand = ""
    @State private var editingTextId: UUID?
    @State private var editingCommandId: UUID?
    @State private var editText = ""
    @State private var hasRequestedAutomation = false
    @State private var automationPermissionGranted = false
    @State private var customTerminalApp = ""
    @State private var isUsingCustomTerminal = false
    @State private var showingAppPicker = false
    @State private var appPickerSearchText = ""
    @State private var appPickerSelectedIndex = 0
    @State private var showingTextSnippetVariableHelp = false
    @State private var showingTerminalVariableHelp = false

    // Website links state
    @State private var newWebsiteURL = ""
    @State private var isFetchingWebsiteMetadata = false
    @State private var websiteURLError: String?

    // Cached installed apps (loaded once on appear)
    @State private var cachedInstalledApps: [AppInfo] = []

    // Variable autocomplete state
    @State private var showSnippetSuggestions = false
    @State private var showCommandSuggestions = false
    @State private var showEditSuggestions = false
    @State private var snippetSuggestionIndex = 0
    @State private var commandSuggestionIndex = 0
    @State private var editSuggestionIndex = 0

    private var textSnippets: [QuickText] {
        profileManager.onScreenKeyboardSettings.quickTexts.filter { !$0.isTerminalCommand }
    }

    private var terminalCommands: [QuickText] {
        profileManager.onScreenKeyboardSettings.quickTexts.filter { $0.isTerminalCommand }
    }

    private var appBarItems: [AppBarItem] {
        profileManager.onScreenKeyboardSettings.appBarItems
    }

    private var websiteLinks: [WebsiteLink] {
        profileManager.onScreenKeyboardSettings.websiteLinks
    }

    private func loadInstalledApps() {
        guard cachedInstalledApps.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = AppMonitor().installedApplications
            DispatchQueue.main.async {
                cachedInstalledApps = apps
            }
        }
    }

    var body: some View {
        Form {
            // How to show keyboard info
            howToShowKeyboardSection

            // Text Snippets Section
            textSnippetsSection

            // Terminal Section
            terminalSection

            // App Bar Section
            appBarSection

            // Website Links Section
            websiteLinksSection

            // App Switching Section
            appSwitchingSection

            // Command Wheel Section
            commandWheelSection

            // Keyboard Layout Section
            keyboardLayoutSection
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            checkAutomationPermission()
            setupCustomTerminal()
        }
    }

    // MARK: - How to Show Keyboard Section

    private var howToShowKeyboardSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("To show the on-screen keyboard widget, assign a button to toggle it.")
                        .fontWeight(.medium)
                    Text("Go to the Buttons tab, add a command, select \"Show Keyboard\", then choose \"Keyboard\".")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)

            HStack {
                Text("Toggle Shortcut")
                Spacer()
                KeyCaptureField(
                    keyCode: Binding<CGKeyCode?>(
                        get: { profileManager.onScreenKeyboardSettings.toggleShortcutKeyCode.map { CGKeyCode($0) } },
                        set: { newValue in
                            var settings = profileManager.onScreenKeyboardSettings
                            settings.toggleShortcutKeyCode = newValue.map { UInt16($0) }
                            profileManager.updateOnScreenKeyboardSettings(settings)
                        }
                    ),
                    modifiers: Binding<ModifierFlags>(
                        get: { profileManager.onScreenKeyboardSettings.toggleShortcutModifiers },
                        set: { newValue in
                            var settings = profileManager.onScreenKeyboardSettings
                            settings.toggleShortcutModifiers = newValue
                            profileManager.updateOnScreenKeyboardSettings(settings)
                        }
                    )
                )
                .frame(width: 200)
            }
        }
    }

    // MARK: - Automation Permission

    private func checkAutomationPermission() {
        // Run a simple AppleScript to check if we have permission
        let script = """
        tell application "System Events"
            return name of first process whose frontmost is true
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: script) {
                scriptObject.executeAndReturnError(&error)
                DispatchQueue.main.async {
                    // If no error, permission was granted
                    automationPermissionGranted = (error == nil)
                }
            }
        }
    }

    private func setupCustomTerminal() {
        let currentTerminal = profileManager.onScreenKeyboardSettings.defaultTerminalApp
        if !OnScreenKeyboardSettings.terminalOptions.contains(currentTerminal) {
            isUsingCustomTerminal = true
            customTerminalApp = currentTerminal
        }
    }

    // MARK: - Variable Hint Section

    private func variableHintSection(isPresented: Binding<Bool>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
                .font(.caption)

            Text("Type")
                .foregroundColor(.secondary)

            Text("{")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(3)

            Text("to insert variables like date, time, clipboard, etc.")
                .foregroundColor(.secondary)

            Button {
                isPresented.wrappedValue.toggle()
            } label: {
                Text("View all")
                    .font(.caption)
            }
            .buttonStyle(.link)
            .popover(isPresented: isPresented, arrowEdge: .bottom) {
                variableHelpPopover
            }
        }
        .font(.caption)
    }

    private var variableHelpPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Variables")
                .font(.headline)

            Text("Type { followed by a variable name. Suggestions will appear as you type.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(VariableExpander.availableVariables, id: \.name) { variable in
                        HStack(spacing: 12) {
                            Text("{\(variable.name)}")
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)
                                .frame(width: 130, alignment: .leading)

                            Text(variable.description)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(variable.example)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.trailing, 12)
            }
            .frame(maxHeight: 400)
        }
        .padding()
        .frame(width: 450)
    }

    // MARK: - Variable Autocomplete Helpers

    /// Finds the variable prefix being typed (text after the last unclosed `{`)
    private func variablePrefix(in text: String) -> String? {
        // Find the last `{` that isn't closed by `}`
        guard let lastBrace = text.lastIndex(of: "{") else { return nil }

        let afterBrace = text[text.index(after: lastBrace)...]

        // If there's a `}` after the `{`, the variable is already closed
        if afterBrace.contains("}") { return nil }

        return String(afterBrace)
    }

    /// Returns filtered variables matching the given prefix
    private func filteredVariables(for prefix: String) -> [(name: String, description: String, example: String)] {
        if prefix.isEmpty {
            return VariableExpander.availableVariables
        }
        return VariableExpander.availableVariables.filter {
            $0.name.lowercased().hasPrefix(prefix.lowercased())
        }
    }

    /// Inserts a variable into text, replacing any partial variable being typed
    private func insertVariable(_ variableName: String, into text: inout String) {
        guard let lastBrace = text.lastIndex(of: "{") else { return }
        let beforeBrace = String(text[..<lastBrace])
        text = beforeBrace + "{\(variableName)}"
    }

    /// Checks if suggestions should be shown for the given text
    private func shouldShowSuggestions(for text: String) -> Bool {
        guard let prefix = variablePrefix(in: text) else { return false }
        return !filteredVariables(for: prefix).isEmpty
    }

    /// Returns the count of filtered variables for the given text
    private func suggestionCount(for text: String) -> Int {
        guard let prefix = variablePrefix(in: text) else { return 0 }
        return filteredVariables(for: prefix).count
    }

    /// Computed suggestion counts for each field
    private var snippetSuggestionCount: Int {
        suggestionCount(for: newTextSnippet)
    }

    private var commandSuggestionCount: Int {
        suggestionCount(for: newTerminalCommand)
    }

    private var editSuggestionCount: Int {
        suggestionCount(for: editText)
    }

    /// Select the currently highlighted suggestion for snippet field
    private func selectSnippetSuggestion() {
        guard let prefix = variablePrefix(in: newTextSnippet) else { return }
        let matches = filteredVariables(for: prefix)
        guard snippetSuggestionIndex < matches.count else { return }
        insertVariable(matches[snippetSuggestionIndex].name, into: &newTextSnippet)
        showSnippetSuggestions = false
        snippetSuggestionIndex = 0
    }

    /// Select the currently highlighted suggestion for command field
    private func selectCommandSuggestion() {
        guard let prefix = variablePrefix(in: newTerminalCommand) else { return }
        let matches = filteredVariables(for: prefix)
        guard commandSuggestionIndex < matches.count else { return }
        insertVariable(matches[commandSuggestionIndex].name, into: &newTerminalCommand)
        showCommandSuggestions = false
        commandSuggestionIndex = 0
    }

    /// Select the currently highlighted suggestion for edit field
    private func selectEditSuggestion() {
        guard let prefix = variablePrefix(in: editText) else { return }
        let matches = filteredVariables(for: prefix)
        guard editSuggestionIndex < matches.count else { return }
        insertVariable(matches[editSuggestionIndex].name, into: &editText)
        showEditSuggestions = false
        editSuggestionIndex = 0
    }

    /// Variable suggestion dropdown view
    @ViewBuilder
    private func variableSuggestionsView(
        for text: Binding<String>,
        showSuggestions: Binding<Bool>,
        selectedIndex: Binding<Int>
    ) -> some View {
        if let prefix = variablePrefix(in: text.wrappedValue) {
            let matches = filteredVariables(for: prefix)
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.name) { index, variable in
                        let isSelected = index == selectedIndex.wrappedValue
                        Button {
                            insertVariable(variable.name, into: &text.wrappedValue)
                            showSuggestions.wrappedValue = false
                            selectedIndex.wrappedValue = 0
                        } label: {
                            HStack {
                                Text("{\(variable.name)}")
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)

                                Spacer()

                                Text(variable.description)
                                    .font(.caption2)
                                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .foregroundColor(isSelected ? .white : .primary)
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(6)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                .frame(maxWidth: 300)
            }
        }
    }

    // MARK: - App Bar Section

    private var appBarSection: some View {
        Section {
            // Add app button
            Button {
                showingAppPicker = true
            } label: {
                Label("Add App", systemImage: "plus.app")
            }
            .sheet(isPresented: $showingAppPicker) {
                appPickerSheet
            }

            // List of app bar items
            if appBarItems.isEmpty {
                Text("No apps added yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                List {
                    ForEach(appBarItems) { item in
                        appBarListRow(item)
                    }
                    .onMove { source, destination in
                        profileManager.moveAppBarItems(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(appBarItems.count) * 32)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
            }
        } header: {
            Text("App Bar")
        } footer: {
            Text("Add apps for quick switching from the on-screen keyboard.")
        }
    }

    @ViewBuilder
    private func appBarListRow(_ item: AppBarItem) -> some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .frame(width: 20)

            // App icon
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleIdentifier),
               let icon = NSWorkspace.shared.icon(forFile: url.path) as NSImage? {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.secondary)
            }

            Text(item.displayName)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Button {
                profileManager.removeAppBarItem(item)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    private var filteredInstalledApps: [AppInfo] {
        cachedInstalledApps.filter { app in
            appPickerSearchText.isEmpty ||
            app.name.localizedCaseInsensitiveContains(appPickerSearchText)
        }
    }

    private func toggleAppSelection(at index: Int) {
        let apps = filteredInstalledApps
        guard index >= 0 && index < apps.count else { return }
        let app = apps[index]
        let alreadyAdded = appBarItems.contains { $0.bundleIdentifier == app.bundleIdentifier }

        if alreadyAdded {
            // Remove the app
            if let item = appBarItems.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
                profileManager.removeAppBarItem(item)
            }
        } else {
            // Add the app
            let item = AppBarItem(
                bundleIdentifier: app.bundleIdentifier,
                displayName: app.name
            )
            profileManager.addAppBarItem(item)
        }
    }

    private var appPickerSheet: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add App")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showingAppPicker = false
                }
            }
            .padding()

            Divider()

            // Search field with keyboard navigation
            NavigableSearchField(
                text: $appPickerSearchText,
                placeholder: "Search apps...",
                itemCount: filteredInstalledApps.count,
                selectedIndex: $appPickerSelectedIndex,
                onSelect: {
                    toggleAppSelection(at: appPickerSelectedIndex)
                }
            )
            .padding()

            Divider()

            // App list with scroll-to-top
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(filteredInstalledApps.enumerated()), id: \.element.id) { index, app in
                        let alreadyAdded = appBarItems.contains { $0.bundleIdentifier == app.bundleIdentifier }
                        let isSelected = index == appPickerSelectedIndex

                        Button {
                            toggleAppSelection(at: index)
                        } label: {
                            HStack(spacing: 12) {
                                if let icon = app.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                } else {
                                    Image(systemName: "app.fill")
                                        .resizable()
                                        .frame(width: 32, height: 32)
                                }

                                Text(app.name)

                                Spacer()

                                if alreadyAdded {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(isSelected ? .white : .green)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(isSelected ? Color.accentColor : Color.clear)
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .onChange(of: appPickerSearchText) { _, _ in
                    // Scroll to top when search changes
                    appPickerSelectedIndex = 0
                    proxy.scrollTo(0, anchor: .top)
                }
                .onChange(of: appPickerSelectedIndex) { _, newIndex in
                    // Scroll to keep selected item visible
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            loadInstalledApps()
        }
        .onDisappear {
            appPickerSearchText = ""
            appPickerSelectedIndex = 0
        }
    }

    // MARK: - Website Links Section

    private var websiteLinksSection: some View {
        Section {
            // Add URL field
            HStack {
                TextField("Enter website URL...", text: $newWebsiteURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addWebsiteLink() }

                if isFetchingWebsiteMetadata {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20)
                } else {
                    Button("Add") { addWebsiteLink() }
                        .disabled(newWebsiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let error = websiteURLError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // List of website links
            if websiteLinks.isEmpty {
                Text("No website links yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                List {
                    ForEach(websiteLinks) { link in
                        websiteLinkRow(link)
                    }
                    .onMove { source, destination in
                        profileManager.moveWebsiteLinks(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(websiteLinks.count) * 40)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
            }
        } header: {
            Text("Website Links")
        } footer: {
            Text("Add websites for quick access from the on-screen keyboard.")
        }
    }

    @ViewBuilder
    private func websiteLinkRow(_ link: WebsiteLink) -> some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .frame(width: 20)

            // Favicon
            if let data = link.faviconData,
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .cornerRadius(4)
            } else {
                Image(systemName: "globe")
                    .frame(width: 24, height: 24)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(link.displayName)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(link.domain ?? link.url)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                profileManager.removeWebsiteLink(link)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
    }

    private func addWebsiteLink() {
        var urlString = newWebsiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return }

        // Add https:// if no scheme provided
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        guard URL(string: urlString) != nil else {
            websiteURLError = "Invalid URL"
            return
        }

        websiteURLError = nil
        isFetchingWebsiteMetadata = true

        Task {
            let (faviconData, title) = await fetchWebsiteMetadata(for: urlString)

            let link = WebsiteLink(
                url: urlString,
                displayName: title,
                faviconData: faviconData
            )

            await MainActor.run {
                profileManager.addWebsiteLink(link)
                newWebsiteURL = ""
                isFetchingWebsiteMetadata = false
            }
        }
    }

    private func fetchWebsiteMetadata(for urlString: String) async -> (Data?, String) {
        guard let url = URL(string: urlString),
              let host = url.host else {
            return (nil, urlString)
        }

        // Fetch page HTML first (we need it for both title and favicon)
        var html: String?
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            html = String(data: data, encoding: .utf8)
        } catch {
            // Continue without HTML
        }

        // Try to get favicon from HTML link tags first (more accurate for subpages)
        var faviconData = await fetchFaviconFromHTML(html: html, baseURL: url)

        // Fall back to Google's service if HTML parsing didn't work
        if faviconData == nil {
            faviconData = await fetchFaviconFromGoogle(host: host)
        }

        // Extract title from HTML
        let title = extractTitle(from: html) ?? host.replacingOccurrences(of: "www.", with: "")

        return (faviconData, title)
    }

    private func fetchFaviconFromHTML(html: String?, baseURL: URL) async -> Data? {
        guard let html = html else { return nil }

        // Look for favicon in link tags (apple-touch-icon or icon)
        // Patterns to match: <link rel="icon" href="..."> or <link rel="apple-touch-icon" href="...">
        let patterns = [
            "<link[^>]*rel=[\"']apple-touch-icon[\"'][^>]*href=[\"']([^\"']+)[\"']",
            "<link[^>]*href=[\"']([^\"']+)[\"'][^>]*rel=[\"']apple-touch-icon[\"']",
            "<link[^>]*rel=[\"']icon[\"'][^>]*href=[\"']([^\"']+)[\"']",
            "<link[^>]*href=[\"']([^\"']+)[\"'][^>]*rel=[\"']icon[\"']",
            "<link[^>]*rel=[\"']shortcut icon[\"'][^>]*href=[\"']([^\"']+)[\"']"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let urlRange = Range(match.range(at: 1), in: html) {
                let faviconURLString = String(html[urlRange])

                // Resolve relative URLs
                var faviconURL: URL?
                if faviconURLString.hasPrefix("http") {
                    faviconURL = URL(string: faviconURLString)
                } else if faviconURLString.hasPrefix("//") {
                    faviconURL = URL(string: "https:" + faviconURLString)
                } else if faviconURLString.hasPrefix("/") {
                    faviconURL = URL(string: faviconURLString, relativeTo: URL(string: "https://\(baseURL.host ?? "")"))
                } else {
                    faviconURL = URL(string: faviconURLString, relativeTo: baseURL)
                }

                if let url = faviconURL {
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        if let httpResponse = response as? HTTPURLResponse,
                           httpResponse.statusCode == 200,
                           data.count > 100 {
                            return data
                        }
                    } catch {
                        continue // Try next pattern
                    }
                }
            }
        }

        return nil
    }

    private func fetchFaviconFromGoogle(host: String) async -> Data? {
        guard let googleURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: googleURL)
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               data.count > 100 {  // Ensure it's not a placeholder
                return data
            }
        } catch {
            // Fall through to return nil
        }

        return nil
    }

    private func extractTitle(from html: String?) -> String? {
        guard let html = html else { return nil }

        let pattern = "<title[^>]*>([^<]+)</title>"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let titleRange = Range(match.range(at: 1), in: html) {
            let title = String(html[titleRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Take first part before common separators
            return title
                .components(separatedBy: " - ").first?
                .components(separatedBy: " | ").first?
                .components(separatedBy: " — ").first
        }

        return nil
    }

    // MARK: - App Switching Section

    private var appSwitchingSection: some View {
        Section("App Switching") {
            Toggle(isOn: Binding(
                get: { profileManager.onScreenKeyboardSettings.activateAllWindows },
                set: { newValue in
                    var settings = profileManager.onScreenKeyboardSettings
                    settings.activateAllWindows = newValue
                    profileManager.updateOnScreenKeyboardSettings(settings)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Activate All Windows")
                    Text("When switching to an app, bring all of its windows to the front.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Command Wheel Section

    private var commandWheelSection: some View {
        Section("Command Wheel") {
            Toggle(isOn: Binding(
                get: { profileManager.onScreenKeyboardSettings.wheelShowsWebsites },
                set: { newValue in
                    var settings = profileManager.onScreenKeyboardSettings
                    settings.wheelShowsWebsites = newValue
                    profileManager.updateOnScreenKeyboardSettings(settings)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show Websites in Wheel")
                    Text("Command wheel shows website links instead of apps.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Picker(selection: Binding(
                get: { wheelAlternateModifierSelection },
                set: { newValue in
                    var settings = profileManager.onScreenKeyboardSettings
                    settings.wheelAlternateModifiers = modifierFlagsForSelection(newValue)
                    profileManager.updateOnScreenKeyboardSettings(settings)
                }
            )) {
                Text("None").tag("none")
                Text("⌘ Command").tag("command")
                Text("⌥ Option").tag("option")
                Text("⇧ Shift").tag("shift")
                Text("⌃ Control").tag("control")
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Alternate Modifier")
                    Text("Hold this key to show \(profileManager.onScreenKeyboardSettings.wheelShowsWebsites ? "apps" : "websites") instead on the command wheel.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var wheelAlternateModifierSelection: String {
        let mods = profileManager.onScreenKeyboardSettings.wheelAlternateModifiers
        if mods.command { return "command" }
        if mods.option { return "option" }
        if mods.shift { return "shift" }
        if mods.control { return "control" }
        return "none"
    }

    private func modifierFlagsForSelection(_ selection: String) -> ModifierFlags {
        switch selection {
        case "command": return ModifierFlags(command: true)
        case "option": return ModifierFlags(option: true)
        case "shift": return ModifierFlags(shift: true)
        case "control": return ModifierFlags(control: true)
        default: return ModifierFlags()
        }
    }

    // MARK: - Keyboard Layout Section

    private var keyboardLayoutSection: some View {
        Section("Keyboard Layout") {
            Toggle(isOn: Binding(
                get: { profileManager.onScreenKeyboardSettings.showExtendedFunctionKeys },
                set: { newValue in
                    var settings = profileManager.onScreenKeyboardSettings
                    settings.showExtendedFunctionKeys = newValue
                    profileManager.updateOnScreenKeyboardSettings(settings)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Show F13-F20 Keys")
                    Text("Display extended function keys (F13-F20) in a row above F1-F12.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }


    // MARK: - Text Snippets Section

    private var textSnippetsSection: some View {
        Section {
            // Variable hint
            variableHintSection(isPresented: $showingTextSnippetVariableHelp)

            // Add new text snippet with autocomplete
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VariableTextField(
                        text: $newTextSnippet,
                        placeholder: "Enter text snippet...",
                        showingSuggestions: showSnippetSuggestions,
                        suggestionCount: snippetSuggestionCount,
                        selectedSuggestionIndex: $snippetSuggestionIndex,
                        onSelectSuggestion: {
                            selectSnippetSuggestion()
                        },
                        onSubmit: {
                            if !showSnippetSuggestions {
                                addTextSnippet()
                            }
                        }
                    )
                    .onChange(of: newTextSnippet) { _, newValue in
                        let shouldShow = shouldShowSuggestions(for: newValue)
                        if shouldShow && !showSnippetSuggestions {
                            snippetSuggestionIndex = 0
                        }
                        showSnippetSuggestions = shouldShow
                    }

                    Button("Add") {
                        addTextSnippet()
                    }
                    .disabled(newTextSnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if showSnippetSuggestions {
                    variableSuggestionsView(for: $newTextSnippet, showSuggestions: $showSnippetSuggestions, selectedIndex: $snippetSuggestionIndex)
                }
            }

            // List of text snippets
            if textSnippets.isEmpty {
                Text("No text snippets yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(textSnippets) { snippet in
                    quickTextRow(snippet, isTerminalCommand: false)
                }
                .onMove { source, destination in
                    moveQuickTexts(from: source, to: destination, isTerminalCommand: false)
                }
            }

            // Typing Speed
            VStack(alignment: .leading, spacing: 6) {
                Picker("Typing Speed", selection: Binding(
                    get: { profileManager.onScreenKeyboardSettings.typingDelay },
                    set: { profileManager.setTypingDelay($0) }
                )) {
                    ForEach(OnScreenKeyboardSettings.typingSpeedPresets, id: \.delay) { preset in
                        Text(preset.name).tag(preset.delay)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
        } header: {
            Text("Text Snippets")
        } footer: {
            Text("Click these to type the text into any app.")
        }
    }

    // MARK: - Terminal Section

    private var terminalSection: some View {
        Section {
            // Variable hint
            variableHintSection(isPresented: $showingTerminalVariableHelp)

            // Add new terminal command with autocomplete
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VariableTextField(
                        text: $newTerminalCommand,
                        placeholder: "Enter terminal command...",
                        showingSuggestions: showCommandSuggestions,
                        suggestionCount: commandSuggestionCount,
                        selectedSuggestionIndex: $commandSuggestionIndex,
                        onSelectSuggestion: {
                            selectCommandSuggestion()
                        },
                        onSubmit: {
                            if !showCommandSuggestions {
                                addTerminalCommand()
                            }
                        }
                    )
                    .onChange(of: newTerminalCommand) { _, newValue in
                        let shouldShow = shouldShowSuggestions(for: newValue)
                        if shouldShow && !showCommandSuggestions {
                            commandSuggestionIndex = 0
                        }
                        showCommandSuggestions = shouldShow
                    }

                    Button("Add") {
                        addTerminalCommand()
                    }
                    .disabled(newTerminalCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if showCommandSuggestions {
                    variableSuggestionsView(for: $newTerminalCommand, showSuggestions: $showCommandSuggestions, selectedIndex: $commandSuggestionIndex)
                }
            }

            // List of terminal commands
            if terminalCommands.isEmpty {
                Text("No terminal commands yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(terminalCommands) { command in
                    quickTextRow(command, isTerminalCommand: true)
                }
                .onMove { source, destination in
                    moveQuickTexts(from: source, to: destination, isTerminalCommand: true)
                }
            }

            // Default Terminal App
            Picker("Default App", selection: Binding(
                get: {
                    let current = profileManager.onScreenKeyboardSettings.defaultTerminalApp
                    if OnScreenKeyboardSettings.terminalOptions.contains(current) {
                        return current
                    }
                    return "Other"
                },
                set: { newValue in
                    if newValue == "Other" {
                        isUsingCustomTerminal = true
                    } else {
                        isUsingCustomTerminal = false
                        profileManager.setDefaultTerminalApp(newValue)
                    }
                }
            )) {
                ForEach(OnScreenKeyboardSettings.terminalOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
                Divider()
                Text("Other...").tag("Other")
            }
            .pickerStyle(.menu)

            if isUsingCustomTerminal {
                HStack {
                    TextField("App name", text: $customTerminalApp)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !customTerminalApp.isEmpty {
                                profileManager.setDefaultTerminalApp(customTerminalApp)
                            }
                        }

                    Button("Set") {
                        if !customTerminalApp.isEmpty {
                            profileManager.setDefaultTerminalApp(customTerminalApp)
                        }
                    }
                    .disabled(customTerminalApp.isEmpty)
                }
            }

            // Permissions status
            if automationPermissionGranted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Automation permission granted")
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Automation permission required")
                    }

                    Button("Open Automation Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                    .buttonStyle(.link)
                }
            }
        } header: {
            Text("Terminal")
        } footer: {
            Text("Click these to open a new terminal window and run the command.")
        }
    }

    // MARK: - Quick Text Row

    @ViewBuilder
    private func quickTextRow(_ quickText: QuickText, isTerminalCommand: Bool) -> some View {
        let isEditing = isTerminalCommand ? editingCommandId == quickText.id : editingTextId == quickText.id

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                if isEditing {
                    VariableTextField(
                        text: $editText,
                        placeholder: "",
                        showingSuggestions: showEditSuggestions,
                        suggestionCount: editSuggestionCount,
                        selectedSuggestionIndex: $editSuggestionIndex,
                        onSelectSuggestion: {
                            selectEditSuggestion()
                        },
                        onSubmit: {
                            if !showEditSuggestions {
                                saveEdit(quickText)
                            }
                        }
                    )
                    .onChange(of: editText) { _, newValue in
                        let shouldShow = shouldShowSuggestions(for: newValue)
                        if shouldShow && !showEditSuggestions {
                            editSuggestionIndex = 0
                        }
                        showEditSuggestions = shouldShow
                    }

                    Button("Save") {
                        saveEdit(quickText)
                    }

                    Button("Cancel") {
                        cancelEdit(isTerminalCommand: isTerminalCommand)
                    }
                } else {
                    Text(quickText.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if quickText.containsVariables {
                        Image(systemName: "function")
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .help("Contains variables that will be expanded")
                    }

                    Spacer()

                    Button {
                        startEdit(quickText, isTerminalCommand: isTerminalCommand)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)

                    Button {
                        profileManager.removeQuickText(quickText)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Show variable suggestions when editing
            if isEditing && showEditSuggestions {
                variableSuggestionsView(for: $editText, showSuggestions: $showEditSuggestions, selectedIndex: $editSuggestionIndex)
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - Actions

    private func addTextSnippet() {
        let trimmed = newTextSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let snippet = QuickText(text: trimmed, isTerminalCommand: false)
        profileManager.addQuickText(snippet)
        newTextSnippet = ""
    }

    private func addTerminalCommand() {
        let trimmed = newTerminalCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let command = QuickText(text: trimmed, isTerminalCommand: true)
        profileManager.addQuickText(command)
        newTerminalCommand = ""
    }

    private func startEdit(_ quickText: QuickText, isTerminalCommand: Bool) {
        editText = quickText.text
        editSuggestionIndex = 0
        showEditSuggestions = false
        if isTerminalCommand {
            editingCommandId = quickText.id
            editingTextId = nil
        } else {
            editingTextId = quickText.id
            editingCommandId = nil
        }
    }

    private func saveEdit(_ quickText: QuickText) {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var updated = quickText
        updated.text = trimmed
        profileManager.updateQuickText(updated)

        editingTextId = nil
        editingCommandId = nil
        editText = ""
    }

    private func cancelEdit(isTerminalCommand: Bool) {
        if isTerminalCommand {
            editingCommandId = nil
        } else {
            editingTextId = nil
        }
        editText = ""
    }

    private func moveQuickTexts(from source: IndexSet, to destination: Int, isTerminalCommand: Bool) {
        // Get the filtered list
        let filteredList = isTerminalCommand ? terminalCommands : textSnippets

        // Get the items being moved
        var items = filteredList
        items.move(fromOffsets: source, toOffset: destination)

        // Rebuild the full list maintaining the order
        var newQuickTexts: [QuickText] = []
        if isTerminalCommand {
            // Keep text snippets first, then reordered terminal commands
            newQuickTexts = textSnippets + items
        } else {
            // Keep reordered text snippets first, then terminal commands
            newQuickTexts = items + terminalCommands
        }

        var settings = profileManager.onScreenKeyboardSettings
        settings.quickTexts = newQuickTexts
        profileManager.updateOnScreenKeyboardSettings(settings)
    }
}

#Preview {
    OnScreenKeyboardSettingsView()
        .environmentObject(ProfileManager())
        .frame(width: 600, height: 500)
}
