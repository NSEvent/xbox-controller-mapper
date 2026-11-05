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
				Button(packet == nil ? "Cancel" : "Close") { dismiss() }.keyboardShortcut(.cancelAction)
				if submission != nil && packet == nil {
					Button("Back") { submission = nil; reviewed = false; errorMessage = nil }
				}
				Spacer()
				if packet == nil {
					if submission == nil {
						Button("Review Shared Copy") { prepare() }.disabled(!details.isValid).buttonStyle(.borderedProminent)
					} else {
						Button(submission?.pasteBody == nil ? "Save File & Open GitHub" : "Copy Submission & Open GitHub") { saveAndOpen() }.disabled(!reviewed).buttonStyle(.borderedProminent)
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
			Text("You'll review a copy, then finish on GitHub. Paste the complete submission there and click Create. Larger profiles need a file attachment instead. A maintainer reviews each submission before adding it to the library.")
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
				Text(submission.pasteBody ?? submission.issueBody).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
			}
			Toggle("I tested this setup, reviewed it for private data, and agree to share it publicly under the library's PolyForm Noncommercial license.", isOn: $reviewed)
				.fixedSize(horizontal: false, vertical: true)
		}
	}

	private func ready(_ packet: CommunityProfileSubmissionFiles.Packet, submission: CommunityProfileSubmission) -> some View {
		CommunityProfileSubmissionReadyView(packet: packet, submission: submission,
			browserOpened: browserOpened, copied: copied,
			copySubmission: { copySubmission(submission) }, openDraft: { openDraft(submission) })
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
			openDraft(submission)
		} catch { errorMessage = error.localizedDescription }
	}

	@discardableResult
	private func copySubmission(_ submission: CommunityProfileSubmission) -> Bool {
		guard let body = submission.pasteBody else { return false }
		NSPasteboard.general.clearContents()
		copied = NSPasteboard.general.setString(body, forType: .string)
		errorMessage = copied ? nil : "Could not copy the submission. Click Copy Complete Submission to try again."
		return copied
	}

	private func openDraft(_ submission: CommunityProfileSubmission) {
		if submission.pasteBody != nil && !copySubmission(submission) { return }
		browserOpened = NSWorkspace.shared.open(submission.issueURL)
		errorMessage = browserOpened ? nil : "The draft could not open. Your files are saved; click Open GitHub Draft to try again."
	}
}

/// The same handoff view is rendered in paste and attachment regression snapshots.
struct CommunityProfileSubmissionReadyView: View {
	let packet: CommunityProfileSubmissionFiles.Packet
	let submission: CommunityProfileSubmission
	let browserOpened: Bool
	let copied: Bool
	let copySubmission: () -> Void
	let openDraft: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Label("Finish on GitHub—not submitted yet", systemImage: "arrow.up.forward.square").font(.headline)
			if submission.pasteBody != nil {
				Text("1. Sign in to GitHub if asked.\n2. Click the description box, press ⌘A, then ⌘V.\n3. Check that Profile data appears, then click Create (or Submit new issue).")
				Text("One paste includes your description and profile. No file attachment needed.").font(.callout)
				Button(copied ? "Copy Complete Submission Again" : "Copy Complete Submission") { copySubmission() }
			} else {
				Text("This profile is too large to paste. The GitHub draft contains only the description.").font(.callout)
				Text("1. Sign in to GitHub if asked.\n2. Drag the file below into the description box.\n3. Wait for a clickable file link, then click Create (or Submit new issue).")
				Label(submission.filename, systemImage: "doc.badge.arrow.up")
					.padding(12).frame(maxWidth: .infinity, alignment: .leading)
					.background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
					.onDrag { NSItemProvider(contentsOf: packet.profileURL) ?? NSItemProvider() }
					.help("Drag this profile file into the GitHub description")
				Button("Show Profile File") { NSWorkspace.shared.activateFileViewerSelecting([packet.profileURL]) }
			}
			Button(browserOpened ? "Reopen GitHub Draft" : "Open GitHub Draft") { openDraft() }
			Text("A backup is saved in Downloads → ControllerKeys Community. Opening GitHub does not submit anything; a maintainer reviews your profile after you create the issue.")
				.font(.caption).foregroundStyle(.secondary)
		}
	}
}
