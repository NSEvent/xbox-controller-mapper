import SwiftUI
import AppKit

/// Swipe typing settings section for the on-screen keyboard settings.
struct SwipeTypingSection: View {
    @EnvironmentObject var profileManager: ProfileManager

    // Custom words state
    @State private var newCustomWord = ""
    @State private var customWords: Set<String> = []

    var body: some View {
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

                Divider()

                // Custom Dictionary
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Dictionary")
                        .fontWeight(.medium)
                    Text("Add words that aren't in the built-in dictionary.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    TextField("Add a word...", text: $newCustomWord)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addCustomWord() }
                    Button("Add") { addCustomWord() }
                        .disabled(newCustomWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !customWords.isEmpty {
                    ForEach(Array(customWords).sorted(), id: \.self) { word in
                        HStack {
                            Text(word)
                                .font(.body.monospaced())
                            Spacer()
                            Button {
                                removeCustomWord(word)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Divider()

                Button {
                    let dirURL = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".controllerkeys/dictionaries")
                    try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(dirURL)
                } label: {
                    Label("Open Dictionaries Folder", systemImage: "folder")
                }
                .buttonStyle(.borderless)

                Text("Add .txt files with custom words (one per line) for domain-specific vocabulary.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear { loadCustomWords() }
    }

    // MARK: - Custom Words Helpers

    private var customWordsFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".controllerkeys/dictionaries/_custom.txt")
    }

    private func loadCustomWords() {
        let url = customWordsFileURL
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            customWords = []
            return
        }
        let words = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        customWords = Set(words)
    }

    private func addCustomWord() {
        let word = newCustomWord.trimmingCharacters(in: .whitespaces).lowercased()
        guard word.count >= 2, word.count <= 12, word.allSatisfy({ $0.isLetter }) else { return }
        guard !customWords.contains(word) else {
            newCustomWord = ""
            return
        }
        customWords.insert(word)
        saveCustomWords()
        newCustomWord = ""
        reloadSwipeModel()
    }

    private func removeCustomWord(_ word: String) {
        customWords.remove(word)
        saveCustomWords()
        reloadSwipeModel()
    }

    private func saveCustomWords() {
        let url = customWordsFileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? AtomicFileWriter.write(Array(customWords).sorted().joined(separator: "\n"), to: url)
    }

    private func reloadSwipeModel() {
        SwipeTypingEngine.shared.reloadModel()
    }
}
