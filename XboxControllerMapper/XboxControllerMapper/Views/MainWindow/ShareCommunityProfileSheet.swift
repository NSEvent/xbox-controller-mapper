import AppKit
import SwiftUI

struct ShareCommunityProfileSheet: View {
	let source: Profile
	@Environment(\.dismiss) private var dismiss
	@State private var details: CommunityProfileSubmissionDetails
	@State private var includeCustomActions = false
	@State private var submission: CommunityProfileSubmission?
	@State private var reviewed = false
	@State private var packet: CommunityProfileSubmissionFiles.Packet?
	@State private var errorMessage: String?
	@State private var browserOpened = false
	@State private var copied = false

	init(profile: Profile) {
		source = profile
		_details = State(initialValue: .init(name: profile.name))
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Label("Share to Community", systemImage: "person.2.wave.2").font(.title2.bold())
			Text("Help someone else get their controller working.").foregroundStyle(.secondary)
			Divider()
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					if let packet, let submission { ready(packet, submission: submission) }
					else if let submission { review(submission) }
					else { form }
					if let errorMessage { Text(errorMessage).foregroundStyle(.red).textSelection(.enabled) }
				}.frame(maxWidth: .infinity, alignment: .leading).padding(4)
			}
			Divider()
			HStack {
				Button(packet == nil ? "Cancel" : "Done") { dismiss() }.keyboardShortcut(.cancelAction)
				if submission != nil && packet == nil {
					Button("Back") { submission = nil; reviewed = false; errorMessage = nil }
				}
				Spacer()
				if packet == nil {
					if submission == nil {
						Button("Review Shared Copy") { prepare() }.disabled(!details.isValid).buttonStyle(.borderedProminent)
					} else {
						Button("Save & Open GitHub Draft") { saveAndOpen() }.disabled(!reviewed).buttonStyle(.borderedProminent)
					}
				}
			}
		}.padding(24).frame(width: 640, height: 690)
	}

	private var form: some View {
		VStack(alignment: .leading, spacing: 14) {
			field("Public profile name", text: $details.name, prompt: "Anki on DualSense")
			field("What does this setup help you do?", text: $details.summary, prompt: "Review Anki cards with one hand")
			field("Which controller did you test?", text: $details.controller, prompt: "PS5 DualSense, Bluetooth")
			Text("Setup tips and a first action to try").font(.headline)
			TextEditor(text: $details.instructions).font(.body).frame(height: 100)
				.overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
			Text("Include the target app and any required tools. No private keys, addresses or account details.").font(.caption).foregroundStyle(.secondary)
			Toggle("Include custom automations, text and links", isOn: $includeCustomActions)
			Text("Off by default: macros, scripts, shell commands, Shortcuts, webhooks, custom text and website links are omitted. App launches, keyboard and mouse mappings stay included.")
				.font(.caption).foregroundStyle(.secondary)
			Label("Your working profile stays unchanged.", systemImage: "doc.on.doc").font(.callout)
			Text("Sharing opens a draft on GitHub. Sign in, attach the prepared file, then submit it for review. A maintainer adds accepted profiles to the library.")
				.font(.callout).foregroundStyle(.secondary)
		}
	}

	private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
		VStack(alignment: .leading, spacing: 5) {
			Text(title).font(.headline)
			TextField(prompt, text: text).textFieldStyle(.roundedBorder)
		}
	}

	private func review(_ submission: CommunityProfileSubmission) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Review what you're sharing").font(.headline)
			Text("\(submission.profile.name) · \(submission.profile.buttonMappings.count) button entries · \(submission.profile.layers.count) layers")
			ForEach(submission.removedItems, id: \.self) { Text("Omitted: \($0)").font(.caption).foregroundStyle(.secondary) }
			if !submission.reviewFields.isEmpty {
				Label("Check these fields for private values", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
				ForEach(submission.reviewFields, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
			}
			Text("Detection is a reminder, not a privacy guarantee. Review labels, code, text and links yourself.").font(.caption).foregroundStyle(.secondary)
			DisclosureGroup("Profile file—exact contents") {
				Text(String(decoding: submission.json, as: UTF8.self)).font(.caption.monospaced())
					.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
			}
			DisclosureGroup("GitHub description—exact contents") {
				Text(submission.issueBody).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
			}
			Toggle("I tested this setup, reviewed it for private data, and agree to share it publicly under the library's PolyForm Noncommercial license.", isOn: $reviewed)
				.fixedSize(horizontal: false, vertical: true)
		}
	}

	private func ready(_ packet: CommunityProfileSubmissionFiles.Packet, submission: CommunityProfileSubmission) -> some View {
		VStack(alignment: .leading, spacing: 16) {
			Label("Your submission is prepared", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
			Text("1. Sign in to GitHub if asked.\n2. Drag \(submission.filename) from Finder into the draft description.\n3. Click Submit new issue on GitHub.")
			Text("The file and setup guide are saved in Downloads → ControllerKeys Community. They become public when you attach them on GitHub; review before attaching.")
				.font(.callout).foregroundStyle(.secondary)
			HStack {
				Button("Show Profile File") { NSWorkspace.shared.activateFileViewerSelecting([packet.profileURL]) }
				Button(browserOpened ? "Reopen GitHub Draft" : "Open GitHub Draft") { browserOpened = NSWorkspace.shared.open(submission.issueURL) }
			}
			Button(copied ? "Description Copied" : "Copy Submission Description") {
				NSPasteboard.general.clearContents()
				copied = NSPasteboard.general.setString(submission.issueBody, forType: .string)
			}
			Text("Opening this draft does not submit the profile or add it to the library. Keep this folder until your submission is accepted.")
				.font(.caption).foregroundStyle(.secondary)
		}
	}

	private func prepare() {
		do {
			submission = try CommunityProfileSubmission.prepare(profile: source, details: details, includeCustomActions: includeCustomActions)
			reviewed = false
			errorMessage = nil
		} catch { errorMessage = error.localizedDescription }
	}

	private func saveAndOpen() {
		guard reviewed, packet == nil, let submission else { return }
		do {
			let downloads = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
			let saved = try CommunityProfileSubmissionFiles.write(submission, to: downloads)
			packet = saved
			NSWorkspace.shared.activateFileViewerSelecting([saved.profileURL])
			browserOpened = NSWorkspace.shared.open(submission.issueURL)
			errorMessage = browserOpened ? nil : "The draft could not open. Your files are saved; use Open GitHub Draft or copy the description."
		} catch { errorMessage = error.localizedDescription }
	}
}
