import SwiftUI

// MARK: - Community Profiles Sheet

struct CommunityProfilesSheet: View {
    @EnvironmentObject var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss

    @State private var availableProfiles: [CommunityProfileInfo] = []
    @State private var selectedProfiles: Set<String> = []
    @State private var alreadyImportedProfiles: Set<String> = []
    @State private var isLoading = true
    @State private var isDownloading = false
    @State private var errorMessage: String?
    @State private var downloadedCount = 0

    // Preview state
    @State private var previewingProfileId: String?
    @State private var previewedProfile: Profile?
    @State private var isLoadingPreview = false
    @State private var previewCache: [String: Profile] = [:]

    // Setup guide state (sidecar markdown)
    @State private var previewedSetupGuide: String?
    @State private var setupGuideCache: [String: String?] = [:]

    // Safety approval (shell commands / scripts in imported profile)
    @State private var pendingSafetyApproval: SafetyApprovalRequest?

    /// Bridges the synchronous SwiftUI sheet flow with the async download
    /// loop: the loop awaits a continuation that fires when the user clicks
    /// Import or Cancel on the safety sheet.
    ///
    /// `resume(_:)` is idempotent — only the first call wins. This lets the
    /// sheet's `.onDisappear` safely fire as a fallback without double-resuming
    /// (which would crash with a checked-continuation violation) when the user
    /// already clicked a button.
    private final class SafetyApprovalRequest: Identifiable {
        let id = UUID()
        let profileName: String
        let report: ProfileImportSafetyReport
        private var continuation: CheckedContinuation<Bool, Never>?

        init(profileName: String, report: ProfileImportSafetyReport, continuation: CheckedContinuation<Bool, Never>) {
            self.profileName = profileName
            self.report = report
            self.continuation = continuation
        }

        func resume(approved: Bool) {
            continuation?.resume(returning: approved)
            continuation = nil
        }
    }

    // Count of new profiles to import (excludes already imported)
    private var newProfilesToImportCount: Int {
        selectedProfiles.subtracting(alreadyImportedProfiles).count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Community Profiles")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding()

            Divider()

            // Content
            if isLoading {
                Spacer()
                ProgressView("Loading profiles...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        loadProfiles()
                    }
                }
                .padding()
                Spacer()
            } else if availableProfiles.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No community profiles available")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                HStack(spacing: 0) {
                    // Left: Profile list
                    VStack(spacing: 0) {
                        List(availableProfiles) { profileInfo in
                            CommunityProfileRow(
                                profileInfo: profileInfo,
                                isSelected: selectedProfiles.contains(profileInfo.id),
                                isAlreadyImported: alreadyImportedProfiles.contains(profileInfo.id),
                                isPreviewing: previewingProfileId == profileInfo.id,
                                onToggleSelect: {
                                    // Don't allow unchecking already-imported profiles
                                    if alreadyImportedProfiles.contains(profileInfo.id) {
                                        return
                                    }
                                    if selectedProfiles.contains(profileInfo.id) {
                                        selectedProfiles.remove(profileInfo.id)
                                    } else {
                                        selectedProfiles.insert(profileInfo.id)
                                    }
                                },
                                onPreview: {
                                    loadPreview(for: profileInfo)
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        }
                        .listStyle(.plain)
                    }
                    .frame(width: 220)

                    Divider()

                    // Right: Preview panel
                    CommunityProfilePreview(
                        profile: previewedProfile,
                        profileName: availableProfiles.first { $0.id == previewingProfileId }?.displayName,
                        setupGuide: previewedSetupGuide,
                        isLoading: isLoadingPreview
                    )
                    .frame(maxWidth: .infinity)
                }
            }

            Divider()

            // Footer
            HStack {
                if !availableProfiles.isEmpty {
                    let allNewSelected = selectedProfiles.subtracting(alreadyImportedProfiles).count == availableProfiles.count - alreadyImportedProfiles.count
                    Button(allNewSelected ? "Deselect All" : "Select All") {
                        if allNewSelected {
                            // Deselect all except already-imported
                            selectedProfiles = alreadyImportedProfiles
                        } else {
                            // Select all
                            selectedProfiles = Set(availableProfiles.map { $0.id })
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                Spacer()

                if isDownloading {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Downloading \(downloadedCount)/\(newProfilesToImportCount)...")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    Button("Import \(newProfilesToImportCount) Profile\(newProfilesToImportCount == 1 ? "" : "s")") {
                        downloadSelectedProfiles()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newProfilesToImportCount == 0)
                }
            }
            .padding()
        }
        .frame(width: 700, height: 500)
        .onAppear {
            loadProfiles()
        }
        .sheet(item: $pendingSafetyApproval) { request in
            ProfileImportSafetySheet(
                profileName: request.profileName,
                report: request.report,
                onApprove: { request.resume(approved: true) },
                onCancel: { request.resume(approved: false) }
            )
            // Safety net for any non-button dismissal (parent close, system
            // event, view teardown). resume() is idempotent so this is a
            // no-op when the user clicked Approve or Cancel.
            .onDisappear { request.resume(approved: false) }
        }
    }

    /// Audit the profile and, if it carries shell commands or scripts, present
    /// the safety sheet and await the user's choice. Returns true on approve
    /// or no-warning-needed; false on cancel.
    private func requestSafetyApproval(for profile: Profile, displayName: String) async -> Bool {
        let report = ProfileImportSafetyAuditor.audit(profile)
        guard report.requiresUserConfirmation else { return true }
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                self.pendingSafetyApproval = SafetyApprovalRequest(
                    profileName: displayName,
                    report: report,
                    continuation: continuation
                )
            }
        }
    }

    private func loadProfiles() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let profiles = try await profileManager.fetchCommunityProfiles()
                await MainActor.run {
                    availableProfiles = profiles

                    // Mark and pre-select profiles that have already been imported
                    let existingProfileNames = Set(profileManager.profiles.map { $0.name })
                    for profile in profiles {
                        if existingProfileNames.contains(profile.displayName) {
                            selectedProfiles.insert(profile.id)
                            alreadyImportedProfiles.insert(profile.id)
                        }
                    }

                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func loadPreview(for profileInfo: CommunityProfileInfo) {
        previewingProfileId = profileInfo.id

        // Setup guide: outer optional == "have we tried fetching", inner == "did one exist".
        // `if let` unwraps the outer only, so a cached "no guide" is honored without a refetch.
        if let cachedGuide = setupGuideCache[profileInfo.id] {
            previewedSetupGuide = cachedGuide
        } else {
            previewedSetupGuide = nil
            loadSetupGuide(for: profileInfo)
        }

        // Check profile cache
        if let cached = previewCache[profileInfo.id] {
            previewedProfile = cached
            // Clear the spinner left over from any in-flight load triggered by
            // a previous selection — without this, switching from a loading
            // profile to a cached one leaves the spinner visible forever.
            isLoadingPreview = false
            return
        }

        isLoadingPreview = true
        previewedProfile = nil

        Task {
            do {
                let profile = try await profileManager.fetchProfileForPreview(from: profileInfo.downloadURL)
                await MainActor.run {
                    previewCache[profileInfo.id] = profile
                    // Only update if still previewing the same profile
                    if previewingProfileId == profileInfo.id {
                        previewedProfile = profile
                    }
                    isLoadingPreview = false
                }
            } catch {
                await MainActor.run {
                    isLoadingPreview = false
                }
            }
        }
    }

    private func loadSetupGuide(for profileInfo: CommunityProfileInfo) {
        Task {
            let guide = try? await profileManager.fetchSetupGuideForPreview(profileURL: profileInfo.downloadURL)
            await MainActor.run {
                setupGuideCache[profileInfo.id] = guide
                if previewingProfileId == profileInfo.id {
                    previewedSetupGuide = guide
                }
            }
        }
    }

    private func downloadSelectedProfiles() {
        isDownloading = true
        downloadedCount = 0

        // Only download profiles that aren't already imported
        let profilesToDownload = availableProfiles.filter {
            selectedProfiles.contains($0.id) && !alreadyImportedProfiles.contains($0.id)
        }

        Task {
            var lastImportedProfile: Profile?

            for profileInfo in profilesToDownload {
                do {
                    // Resolve the to-be-imported Profile data first (cache hit
                    // or network) so we can audit its bindings before deciding
                    // whether to install it.
                    let candidate: Profile
                    if let cached = previewCache[profileInfo.id] {
                        candidate = cached
                    } else {
                        candidate = try await profileManager.fetchProfileForPreview(from: profileInfo.downloadURL)
                    }

                    let approved = await requestSafetyApproval(for: candidate, displayName: profileInfo.displayName)
                    guard approved else { continue }

                    let imported = await MainActor.run {
                        profileManager.importFetchedProfile(candidate)
                    }
                    lastImportedProfile = imported
                    await MainActor.run {
                        downloadedCount += 1
                    }
                } catch {
                    #if DEBUG
                    print("Failed to download profile \(profileInfo.name): \(error)")
                    #endif
                }
            }

            await MainActor.run {
                isDownloading = false
                if let profile = lastImportedProfile {
                    profileManager.setActiveProfile(profile)
                }
                dismiss()
            }
        }
    }
}

// MARK: - Community Profile Row

struct CommunityProfileRow: View {
    let profileInfo: CommunityProfileInfo
    let isSelected: Bool
    let isAlreadyImported: Bool
    let isPreviewing: Bool
    let onToggleSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Checkbox - disabled for already-imported profiles
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isAlreadyImported ? .secondary : (isSelected ? .accentColor : .secondary))
            }
            .buttonStyle(.plain)
            .disabled(isAlreadyImported)

            // Profile name (clickable for preview)
            Text(profileInfo.displayName)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(isAlreadyImported ? .secondary : .primary)

            // Already imported indicator
            if isAlreadyImported {
                Text("Imported")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }

            // Preview indicator
            if isPreviewing {
                Image(systemName: "eye.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isPreviewing ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onToggleSelect()
            onPreview()
        }
        .onTapGesture(count: 1) {
            onPreview()
        }
    }
}

// MARK: - Community Profile Preview

struct CommunityProfilePreview: View {
    let profile: Profile?
    let profileName: String?
    let setupGuide: String?
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                Spacer()
                ProgressView("Loading preview...")
                Spacer()
            } else if let profile = profile {
                // Header
                HStack {
                    Text(profileName ?? profile.name)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(profile.buttonMappings.count) mappings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !profile.chordMappings.isEmpty {
                        Text("• \(profile.chordMappings.count) chords")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // Mappings list
                ScrollView {
                    VStack(spacing: 6) {
                        // Setup guide (if a sidecar markdown exists for this profile)
                        if let guide = setupGuide {
                            SetupGuideSection(markdown: guide)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                            Divider()
                                .padding(.bottom, 8)
                        }

                        // Button mappings
                        ForEach(ControllerButton.allCases.filter { profile.buttonMappings[$0] != nil }, id: \.self) { button in
                            if let mapping = profile.buttonMappings[button], !mapping.isEmpty {
                                PreviewMappingRow(button: button, mapping: mapping, profile: profile)
                            }
                        }

                        // Chord mappings
                        if !profile.chordMappings.isEmpty {
                            Divider()
                                .padding(.vertical, 12)

                            HStack {
                                Text("CHORDS")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                            VStack(spacing: 8) {
                                ForEach(profile.chordMappings) { chord in
                                    PreviewChordRow(chord: chord, profile: profile)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            } else {
                // Empty state - no profile selected
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "gamecontroller")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.secondary.opacity(0.3))

                    VStack(spacing: 4) {
                        Text("Preview")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("Click a profile to see its mappings")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.4))
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.opacity(0.15))
    }
}

// MARK: - Setup Guide Section

struct SetupGuideSection: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "book.fill")
                    .font(.system(size: 11))
                Text("SETUP GUIDE")
                    .font(.system(size: 10, weight: .bold))
                Spacer()
            }
            .foregroundColor(.accentColor)
            .padding(.bottom, 4)

            ForEach(SetupGuideMarkdown.parse(markdown)) { block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: SetupGuideMarkdown.Block) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(block.text)
                .font(.system(size: headingSize(level), weight: .semibold))
                .padding(.top, level <= 2 ? 8 : 4)
                .padding(.bottom, 2)
        case .codeBlock:
            CodeBlockView(text: block.text)
        case .table(let rows):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            inlineMarkdown(cell)
                                .font(.system(size: 11, weight: idx == 0 ? .semibold : .regular))
                                .foregroundColor(idx == 0 ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if idx == 0 {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 4)
        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ordered ? "\(idx + 1)." : "•")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        inlineMarkdown(item)
                            .font(.system(size: 12))
                    }
                }
            }
        case .blockquote:
            HStack(spacing: 8) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(width: 3)
                inlineMarkdown(block.text)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        case .rule:
            Divider().padding(.vertical, 4)
        case .paragraph:
            inlineMarkdown(block.text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inlineMarkdown(_ text: String) -> Text {
        if let attr = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(text)
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 16
        case 2: return 14
        default: return 12.5
        }
    }
}

/// Code-block renderer with a copy-to-clipboard button overlaid in the
/// top-right corner. Setup guides often contain shell snippets that users want
/// to paste verbatim — the button removes the friction of a manual select-all.
private struct CodeBlockView: View {
    let text: String
    @State private var didCopy = false
    @State private var revertTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    // Reserve space on the right so the button never overlaps
                    // the last column of long lines.
                    .padding(.trailing, 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.18))
            .cornerRadius(4)

            Button(action: copy) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(didCopy ? .green : .secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.gray.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help(didCopy ? "Copied" : "Copy code")
            .padding(4)
        }
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Brief visual confirmation, then revert. Cancel any prior pending
        // revert so rapid double-clicks don't snap back early.
        revertTask?.cancel()
        didCopy = true
        revertTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            if !Task.isCancelled {
                didCopy = false
            }
        }
    }
}

enum SetupGuideMarkdown {
    struct Block: Identifiable {
        let id = UUID()
        enum Kind {
            case heading(Int)
            case paragraph
            case codeBlock
            case table([[String]])
            case list([String], ordered: Bool)
            case blockquote
            case rule
        }
        let kind: Kind
        let text: String
    }

    static func parse(_ md: String) -> [Block] {
        var blocks: [Block] = []
        let lines = md.components(separatedBy: "\n")
        var i = 0

        func isOrderedListLine(_ s: String) -> Bool {
            guard let dot = s.firstIndex(of: ".") else { return false }
            let prefix = s[..<dot]
            return !prefix.isEmpty && prefix.allSatisfy(\.isNumber) && s.distance(from: s.startIndex, to: dot) <= 3 && s.index(after: dot) < s.endIndex && s[s.index(after: dot)] == " "
        }
        func orderedListContent(_ s: String) -> String {
            guard let dot = s.firstIndex(of: ".") else { return s }
            return String(s[s.index(dot, offsetBy: 2)...])
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { i += 1; continue }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" {
                blocks.append(Block(kind: .rule, text: ""))
                i += 1
                continue
            }

            // Headings
            if line.hasPrefix("# ") {
                blocks.append(Block(kind: .heading(1), text: String(line.dropFirst(2))))
                i += 1; continue
            }
            if line.hasPrefix("## ") {
                blocks.append(Block(kind: .heading(2), text: String(line.dropFirst(3))))
                i += 1; continue
            }
            if line.hasPrefix("### ") {
                blocks.append(Block(kind: .heading(3), text: String(line.dropFirst(4))))
                i += 1; continue
            }

            // Code fence
            if line.hasPrefix("```") {
                var code = ""
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    code += lines[i] + "\n"
                    i += 1
                }
                if i < lines.count { i += 1 }
                blocks.append(Block(kind: .codeBlock, text: code.trimmingCharacters(in: CharacterSet.newlines)))
                continue
            }

            // Table (GFM): row starts with |, includes a separator row of dashes
            if line.hasPrefix("|") {
                var rows: [[String]] = []
                while i < lines.count && lines[i].hasPrefix("|") {
                    let row = lines[i]
                        .split(separator: "|", omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    let trimmedRow = Array(row.dropFirst().dropLast())
                    let isSeparator = !trimmedRow.isEmpty && trimmedRow.allSatisfy { cell in
                        cell.allSatisfy { c in c == "-" || c == ":" }
                    }
                    if !isSeparator {
                        rows.append(trimmedRow)
                    }
                    i += 1
                }
                blocks.append(Block(kind: .table(rows), text: ""))
                continue
            }

            // Blockquote
            if line.hasPrefix("> ") {
                var quote = String(line.dropFirst(2))
                i += 1
                while i < lines.count && lines[i].hasPrefix("> ") {
                    quote += " " + String(lines[i].dropFirst(2)).trimmingCharacters(in: .whitespaces)
                    i += 1
                }
                blocks.append(Block(kind: .blockquote, text: quote))
                continue
            }

            // Bullet list
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                var items: [String] = []
                while i < lines.count && (lines[i].hasPrefix("- ") || lines[i].hasPrefix("* ")) {
                    items.append(String(lines[i].dropFirst(2)))
                    i += 1
                }
                blocks.append(Block(kind: .list(items, ordered: false), text: ""))
                continue
            }

            // Ordered list
            if isOrderedListLine(line) {
                var items: [String] = []
                while i < lines.count && isOrderedListLine(lines[i]) {
                    items.append(orderedListContent(lines[i]))
                    i += 1
                }
                blocks.append(Block(kind: .list(items, ordered: true), text: ""))
                continue
            }

            // Paragraph: gather until blank/special line
            var para = line
            i += 1
            while i < lines.count {
                let next = lines[i]
                let nextTrim = next.trimmingCharacters(in: .whitespaces)
                if nextTrim.isEmpty || next.hasPrefix("#") || next.hasPrefix("```") || next.hasPrefix("|")
                    || next.hasPrefix("- ") || next.hasPrefix("* ") || next.hasPrefix("> ")
                    || nextTrim == "---" || isOrderedListLine(next) {
                    break
                }
                para += " " + nextTrim
                i += 1
            }
            blocks.append(Block(kind: .paragraph, text: para))
        }
        return blocks
    }
}

// MARK: - Preview Mapping Row

struct PreviewMappingRow: View {
    @EnvironmentObject var controllerService: ControllerService

    let button: ControllerButton
    let mapping: KeyMapping
    let profile: Profile

    var body: some View {
        HStack(spacing: 12) {
            ButtonIconView(button: button, isPressed: false, isDualSense: controllerService.threadSafeIsPlayStation, isNintendo: controllerService.threadSafeIsNintendo, isSteamController: controllerService.threadSafeIsSteamController)
                .frame(width: 28, height: 28)

            // Show mappings with hint + actual shortcut side by side
            HStack(spacing: 16) {
                // Primary mapping
                if let systemCommand = mapping.systemCommand {
                    PreviewMappingLabel(
                        text: mapping.hint ?? systemCommand.displayName,
                        shortcut: mapping.hint != nil ? systemCommand.displayName : nil,
                        icon: "SYS",
                        color: .green
                    )
                } else if let macroId = mapping.macroId,
                          let macro = profile.macros.first(where: { $0.id == macroId }) {
                    PreviewMappingLabel(
                        text: mapping.hint ?? macro.name,
                        shortcut: mapping.hint != nil ? "Macro: \(macro.name)" : nil,
                        icon: "▶",
                        color: .purple
                    )
                } else if !mapping.isEmpty {
                    PreviewMappingLabel(
                        text: mapping.hint ?? mapping.displayString,
                        shortcut: mapping.hint != nil ? mapping.displayString : nil,
                        icon: mapping.isHoldModifier ? "▼" : nil,
                        color: mapping.isHoldModifier ? .purple : .primary
                    )
                }

                // Long hold
                if let longHold = mapping.longHoldMapping, !longHold.isEmpty {
                    PreviewMappingLabel(
                        text: longHold.hint ?? longHold.displayString,
                        shortcut: longHold.hint != nil ? longHold.displayString : nil,
                        icon: "⏱",
                        color: .orange
                    )
                }

                // Double tap
                if let doubleTap = mapping.doubleTapMapping, !doubleTap.isEmpty {
                    PreviewMappingLabel(
                        text: doubleTap.hint ?? doubleTap.displayString,
                        shortcut: doubleTap.hint != nil ? doubleTap.displayString : nil,
                        icon: "2×",
                        color: .cyan
                    )
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }
}

struct PreviewMappingLabel: View {
    let text: String
    let shortcut: String?
    let icon: String?
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Text(icon)
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(color)
                    .cornerRadius(2)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color == .primary ? .primary : color)
                .lineLimit(1)

            // Show actual shortcut to the right if there's a hint
            if let shortcut = shortcut {
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Preview Chord Row

struct PreviewChordRow: View {
    @EnvironmentObject var controllerService: ControllerService

    let chord: ChordMapping
    let profile: Profile

    var body: some View {
        HStack(spacing: 12) {
            // Button icons - match main chord list spacing
            HStack(spacing: 4) {
                ForEach(Array(chord.buttons).sorted(by: { $0.category.chordDisplayOrder < $1.category.chordDisplayOrder }), id: \.self) { button in
                    ButtonIconView(button: button, isPressed: false, isDualSense: controllerService.threadSafeIsPlayStation, isNintendo: controllerService.threadSafeIsNintendo, isSteamController: controllerService.threadSafeIsSteamController)
                }
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            // Action with hint + actual shortcut shown inline
            if let systemCommand = chord.systemCommand {
                chordActionLabel(
                    text: chord.hint ?? systemCommand.displayName,
                    shortcut: chord.hint != nil ? systemCommand.displayName : nil,
                    color: .green.opacity(0.9)
                )
            } else if let macroId = chord.macroId,
                      let macro = profile.macros.first(where: { $0.id == macroId }) {
                chordActionLabel(
                    text: chord.hint ?? macro.name,
                    shortcut: chord.hint != nil ? "Macro: \(macro.name)" : nil,
                    color: .purple.opacity(0.9)
                )
			} else if let scriptId = chord.scriptId,
					  let script = profile.scripts.first(where: { $0.id == scriptId }) {
				chordActionLabel(
					text: chord.hint ?? script.name,
					shortcut: chord.hint != nil ? "Script: \(script.name)" : nil,
					color: .primary
				)
            } else {
                chordActionLabel(
                    text: chord.hint ?? chord.actionDisplayString,
                    shortcut: chord.hint != nil ? chord.actionDisplayString : nil,
                    color: .primary
                )
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func chordActionLabel(text: String, shortcut: String?, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)

            if let shortcut = shortcut {
                Text(shortcut)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}
