import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @State private var showingWebsiteBookmarkPicker = false

    // App bar editing state
    @State private var editingAppBarItem: AppBarItem?

    // Website link editing state
    @State private var editingWebsiteLink: WebsiteLink?

    // Drag-to-reorder state
    @State private var draggedAppBarItem: AppBarItem?
    @State private var draggedWebsiteLink: WebsiteLink?

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
        (profileManager.activeProfile?.onScreenKeyboardSettings.quickTexts ?? []).filter { !$0.isTerminalCommand }
    }

    private var terminalCommands: [QuickText] {
        (profileManager.activeProfile?.onScreenKeyboardSettings.quickTexts ?? []).filter { $0.isTerminalCommand }
    }

    private var appBarItems: [AppBarItem] {
        profileManager.activeProfile?.onScreenKeyboardSettings.appBarItems ?? []
    }

    private var websiteLinks: [WebsiteLink] {
        profileManager.activeProfile?.onScreenKeyboardSettings.websiteLinks ?? []
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

            // Swipe Typing Section
            swipeTypingSection
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
            .sheet(item: $editingAppBarItem) { item in
                EditAppBarItemSheet(item: item) { updatedItem in
                    profileManager.updateAppBarItem(updatedItem)
                }
            }

            // List of app bar items
            if appBarItems.isEmpty {
                Text("No apps added yet")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                VStack(spacing: 4) {
                    ForEach(appBarItems) { item in
                        appBarListRow(item)
                            .onDrag {
                                draggedAppBarItem = item
                                return NSItemProvider(object: item.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: AppBarItemDropDelegate(
                                item: item,
                                items: appBarItems,
                                draggedItem: $draggedAppBarItem,
                                moveItems: { from, to in
                                    profileManager.moveAppBarItems(from: from, to: to)
                                }
                            ))
                    }
                }
            }
        } header: {
            Text("App Bar")
        } footer: {
            Text("Add apps for quick switching from the on-screen keyboard.")
        }
    }

    @ViewBuilder
    private func appBarListRow(_ item: AppBarItem) -> some View {
        AppBarItemRowView(
            item: item,
            onEdit: {
                editingAppBarItem = item
            },
            onDelete: {
                profileManager.removeAppBarItem(item)
            }
        )
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
                .keyboardShortcut(.return, modifiers: .command)
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

            Button {
                showingWebsiteBookmarkPicker = true
            } label: {
                Label("Browse Bookmarks", systemImage: "book")
            }
            .sheet(isPresented: $showingWebsiteBookmarkPicker) {
                BookmarkPickerSheet { url in
                    newWebsiteURL = url
                    addWebsiteLink()
                }
            }
            .sheet(item: $editingWebsiteLink) { link in
                EditWebsiteLinkSheet(link: link) { updatedLink in
                    profileManager.updateWebsiteLink(updatedLink)
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
                VStack(spacing: 4) {
                    ForEach(websiteLinks) { link in
                        websiteLinkRow(link)
                            .onDrag {
                                draggedWebsiteLink = link
                                return NSItemProvider(object: link.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: WebsiteLinkDropDelegate(
                                item: link,
                                items: websiteLinks,
                                draggedItem: $draggedWebsiteLink,
                                moveItems: { from, to in
                                    profileManager.moveWebsiteLinks(from: from, to: to)
                                }
                            ))
                    }
                }
            }
        } header: {
            Text("Website Links")
        } footer: {
            Text("Add websites for quick access from the on-screen keyboard.")
        }
    }

    @ViewBuilder
    private func websiteLinkRow(_ link: WebsiteLink) -> some View {
        WebsiteLinkRowView(
            link: link,
            onEdit: {
                editingWebsiteLink = link
            },
            onDelete: {
                profileManager.removeWebsiteLink(link)
            }
        )
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

        // Fetch favicon using cache (handles fetching and caching)
        let faviconData = await FaviconCache.shared.fetchFavicon(for: urlString)

        // Fetch page HTML for title extraction
        var title = host.replacingOccurrences(of: "www.", with: "")
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let html = String(data: data, encoding: .utf8) {
                title = extractTitle(from: html) ?? title
            }
        } catch {
            // Use host as fallback title
        }

        return (faviconData, title)
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

    // MARK: - Swipe Typing Section

    private var swipeTypingSection: some View {
        Section("Swipe Typing") {
            Toggle(isOn: Binding(
                get: { profileManager.onScreenKeyboardSettings.swipeTypingEnabled },
                set: { newValue in
                    var settings = profileManager.onScreenKeyboardSettings
                    settings.swipeTypingEnabled = newValue
                    profileManager.updateOnScreenKeyboardSettings(settings)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Swipe Typing")
                    Text("Hold left trigger and move the left stick to swipe across letter keys.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if profileManager.onScreenKeyboardSettings.swipeTypingEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Sensitivity")
                        Spacer()
                        Text(String(format: "%.1f", profileManager.onScreenKeyboardSettings.swipeTypingSensitivity))
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { profileManager.onScreenKeyboardSettings.swipeTypingSensitivity },
                            set: { newValue in
                                var settings = profileManager.onScreenKeyboardSettings
                                settings.swipeTypingSensitivity = newValue
                                profileManager.updateOnScreenKeyboardSettings(settings)
                            }
                        ),
                        in: 0.1...1.0,
                        step: 0.1
                    )
                }

                Stepper(value: Binding(
                    get: { profileManager.onScreenKeyboardSettings.swipeTypingPredictionCount },
                    set: { newValue in
                        var settings = profileManager.onScreenKeyboardSettings
                        settings.swipeTypingPredictionCount = newValue
                        profileManager.updateOnScreenKeyboardSettings(settings)
                    }
                ), in: 1...10) {
                    HStack {
                        Text("Predictions")
                        Spacer()
                        Text("\(profileManager.onScreenKeyboardSettings.swipeTypingPredictionCount)")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
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
                List {
                    ForEach(textSnippets) { snippet in
                        quickTextRow(snippet, isTerminalCommand: false)
                    }
                    .onMove { source, destination in
                        moveQuickTexts(from: source, to: destination, isTerminalCommand: false)
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(textSnippets.count) * 36)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
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
                List {
                    ForEach(terminalCommands) { command in
                        quickTextRow(command, isTerminalCommand: true)
                    }
                    .onMove { source, destination in
                        moveQuickTexts(from: source, to: destination, isTerminalCommand: true)
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(terminalCommands.count) * 36)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
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
        QuickTextRowView(
            quickText: quickText,
            isTerminalCommand: isTerminalCommand,
            isEditing: isTerminalCommand ? editingCommandId == quickText.id : editingTextId == quickText.id,
            editText: $editText,
            showEditSuggestions: showEditSuggestions,
            editSuggestionCount: editSuggestionCount,
            editSuggestionIndex: $editSuggestionIndex,
            onSelectSuggestion: selectEditSuggestion,
            onSave: { saveEdit(quickText) },
            onCancel: { cancelEdit(isTerminalCommand: isTerminalCommand) },
            onStartEdit: { startEdit(quickText, isTerminalCommand: isTerminalCommand) },
            onDelete: { profileManager.removeQuickText(quickText) },
            onEditTextChange: { newValue in
                let shouldShow = shouldShowSuggestions(for: newValue)
                if shouldShow && !showEditSuggestions {
                    editSuggestionIndex = 0
                }
                showEditSuggestions = shouldShow
            },
            variableSuggestionsView: {
                variableSuggestionsView(for: $editText, showSuggestions: $showEditSuggestions, selectedIndex: $editSuggestionIndex)
            }
        )
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

// MARK: - Quick Text Row View

struct QuickTextRowView<SuggestionsView: View>: View {
    let quickText: QuickText
    let isTerminalCommand: Bool
    let isEditing: Bool
    @Binding var editText: String
    let showEditSuggestions: Bool
    let editSuggestionCount: Int
    @Binding var editSuggestionIndex: Int
    let onSelectSuggestion: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onStartEdit: () -> Void
    let onDelete: () -> Void
    let onEditTextChange: (String) -> Void
    @ViewBuilder let variableSuggestionsView: () -> SuggestionsView

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Drag handle - not tappable, allows List drag to work
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
                        onSelectSuggestion: onSelectSuggestion,
                        onSubmit: {
                            if !showEditSuggestions {
                                onSave()
                            }
                        }
                    )
                    .onChange(of: editText) { _, newValue in
                        onEditTextChange(newValue)
                    }

                    Button("Save", action: onSave)
                    Button("Cancel", action: onCancel)
                } else {
                    // Tappable content area
                    HStack {
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
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onStartEdit() }

                    Button(action: onStartEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if isEditing && showEditSuggestions {
                variableSuggestionsView()
                    .padding(.leading, 28)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - App Bar Item Row View

struct AppBarItemRowView: View {
    let item: AppBarItem
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            // Drag handle - not tappable, allows drag to work
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .frame(width: 20)

            // Tappable content area
            HStack {
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
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit() }

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Website Link Row View

struct WebsiteLinkRowView: View {
    let link: WebsiteLink
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            // Drag handle - not tappable, allows drag to work
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)
                .frame(width: 20)

            // Tappable content area
            HStack {
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
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit() }

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Edit App Bar Item Sheet

struct EditAppBarItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: AppBarItem
    let onSave: (AppBarItem) -> Void

    @State private var displayName: String
    @State private var selectedBundleId: String
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var installedApps: [AppInfo] = []

    init(item: AppBarItem, onSave: @escaping (AppBarItem) -> Void) {
        self.item = item
        self.onSave = onSave
        self._displayName = State(initialValue: item.displayName)
        self._selectedBundleId = State(initialValue: item.bundleIdentifier)
    }

    private var filteredApps: [AppInfo] {
        if searchText.isEmpty {
            return installedApps
        }
        return installedApps.filter { app in
            app.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit App")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            Divider()

            // Display name field
            HStack {
                Text("Display Name:")
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)
            .padding(.top)

            Divider()
                .padding(.top)

            // Search field
            NavigableSearchField(
                text: $searchText,
                placeholder: "Search apps...",
                itemCount: filteredApps.count,
                selectedIndex: $selectedIndex,
                onSelect: {
                    selectApp(at: selectedIndex)
                }
            )
            .padding()

            Divider()

            // App list
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(filteredApps.enumerated()), id: \.element.id) { index, app in
                        let isSelected = index == selectedIndex
                        let isCurrentApp = app.bundleIdentifier == selectedBundleId

                        Button {
                            selectApp(at: index)
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

                                if isCurrentApp {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(isSelected ? .white : .accentColor)
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
                .listStyle(.plain)
                .onChange(of: searchText) { _, _ in
                    selectedIndex = 0
                    proxy.scrollTo(0, anchor: .top)
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 450, height: 500)
        .onAppear {
            loadInstalledApps()
        }
    }

    private func loadInstalledApps() {
        DispatchQueue.global(qos: .userInitiated).async {
            let apps = AppMonitor().installedApplications
            DispatchQueue.main.async {
                installedApps = apps
            }
        }
    }

    private func selectApp(at index: Int) {
        guard index >= 0 && index < filteredApps.count else { return }
        let app = filteredApps[index]
        selectedBundleId = app.bundleIdentifier
        // Update display name if it was the original app name
        if displayName == item.displayName {
            displayName = app.name
        }
    }

    private func save() {
        var updatedItem = item
        updatedItem.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        updatedItem.bundleIdentifier = selectedBundleId
        onSave(updatedItem)
        dismiss()
    }
}

// MARK: - Edit Website Link Sheet

struct EditWebsiteLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    let link: WebsiteLink
    let onSave: (WebsiteLink) -> Void

    @State private var displayName: String
    @State private var url: String

    init(link: WebsiteLink, onSave: @escaping (WebsiteLink) -> Void) {
        self.link = link
        self.onSave = onSave
        self._displayName = State(initialValue: link.displayName)
        self._url = State(initialValue: link.url)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Website Link")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save") { save() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            Divider()

            // Content
            Form {
                // Favicon preview
                HStack {
                    if let data = link.faviconData,
                       let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .frame(width: 32, height: 32)
                            .cornerRadius(4)
                    } else {
                        Image(systemName: "globe")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .foregroundColor(.secondary)
                    }

                    Text("Favicon will be updated if URL changes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)

                // Editable fields
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)

                TextField("URL", text: $url)
                    .textFieldStyle(.roundedBorder)
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 450, height: 280)
    }

    private func save() {
        var updatedLink = link
        updatedLink.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if newURL != link.url {
            updatedLink.url = newURL
            // Clear favicon if URL changed - it will be re-fetched
            updatedLink.faviconData = nil
        }
        onSave(updatedLink)
        dismiss()
    }
}

// MARK: - Drop Delegates for Reordering

struct AppBarItemDropDelegate: DropDelegate {
    let item: AppBarItem
    let items: [AppBarItem]
    @Binding var draggedItem: AppBarItem?
    let moveItems: (IndexSet, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem,
              draggedItem.id != item.id,
              let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            moveItems(IndexSet(integer: fromIndex), toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

struct WebsiteLinkDropDelegate: DropDelegate {
    let item: WebsiteLink
    let items: [WebsiteLink]
    @Binding var draggedItem: WebsiteLink?
    let moveItems: (IndexSet, Int) -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedItem = draggedItem,
              draggedItem.id != item.id,
              let fromIndex = items.firstIndex(where: { $0.id == draggedItem.id }),
              let toIndex = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            moveItems(IndexSet(integer: fromIndex), toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

#Preview {
    OnScreenKeyboardSettingsView()
        .environmentObject(ProfileManager())
        .frame(width: 600, height: 500)
}
