//  FeedbackKit.swift
//  ───────────────────────────────────────────────────────────────────────────
//  Drop-in, cross-platform (iOS 15+ / macOS 12+ / tvOS 15+) in-app feedback form.
//  A real text box the user fills in and sends — no mail app required — that POSTs
//  to the shared feedback backend (Cloudflare Worker + D1 at feedback.kevintang.app,
//  repo ~/projects/feedback-worker). If the network POST fails, it falls back to a
//  pre-filled `mailto:` so a motivated user's feedback is never lost.
//
//  WHY THIS EXISTS
//  The best product feedback comes from committed users, but it dies in friction:
//  finding an address, leaving the app, composing from a blank page. This gives every
//  app a "type + Send" box wired to one queryable store you can batch into an LLM.
//
//  USAGE — one line inside any Settings Form/List Section:
//
//      Section {
//          FeedbackLink()                       // auto-detects app name, id, version, device
//      }
//
//  Override anything you like:
//
//      FeedbackLink(config: FeedbackConfig(
//          appName: "Wallet Buddy",
//          appID: "xyz.kevintang.walletbuddy",
//          submitKey: "…",                      // only if the Worker's SUBMIT_KEY is set
//          prompt: "Tell me what card feature to build next."))
//
//  Or present the sheet yourself: `.sheet(isPresented:) { FeedbackFormView(config:) }`.
//
//  WHAT IT SENDS: the user's message, an optional reply email they choose to type, and
//  non-identifying diagnostics (app version/build, platform, OS version, device model,
//  locale). No user identifier, no tracking.
//
//  Provenance: extracted 2026-07-16 for the portfolio-wide feedback push.
//  Backend: ~/projects/feedback-worker (POST /submit). Dependency-free.
//  ───────────────────────────────────────────────────────────────────────────

import SwiftUI
import Combine
#if canImport(Darwin)
import Darwin
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Config

struct FeedbackConfig {
	/// The Worker endpoint that receives submissions.
	var endpoint: URL
	/// App identifier used to namespace rows server-side (defaults to the bundle id).
	var appID: String
	/// Human display name shown in the sheet + email subject (defaults to the bundle name).
	var appName: String
	/// Only needed if the Worker has a SUBMIT_KEY set. Sent as `X-Feedback-Key`.
	var submitKey: String?
	/// Address used for the `mailto:` fallback if the network POST fails.
	var fallbackEmail: String
	/// The framing line at the top of the sheet — the biggest lever on response rate.
	var prompt: String

	init(
		appName: String? = nil,
		appID: String? = nil,
		endpoint: URL = URL(string: "https://feedback.kevintang.app/submit")!,
		submitKey: String? = nil,
		fallbackEmail: String = "feedback@kevintang.xyz",
		prompt: String = "I'm an indie developer and I read every message. "
			+ "Tell me what's not working, what's missing, or what I should build next."
	) {
		self.appName = appName ?? FeedbackEnv.appName
		self.appID = appID ?? FeedbackEnv.bundleID
		self.endpoint = endpoint
		self.submitKey = submitKey
		self.fallbackEmail = fallbackEmail
		self.prompt = prompt
	}
}

// MARK: - Category

enum FeedbackCategory: String, CaseIterable, Identifiable {
	case useCase = "use_case"
	case idea
	case bug
	case confusing
	case other
	var id: String { rawValue }
	var title: String {
		switch self {
		case .useCase: return "How I use it"
		case .idea: return "An idea"
		case .bug: return "A bug"
		case .confusing: return "Confusing"
		case .other: return "Other"
		}
	}
}

// MARK: - Drop-in Settings row

/// A single Settings row that opens the feedback sheet. Drop into any Form/List Section.
struct FeedbackLink: View {
	var config: FeedbackConfig = FeedbackConfig()
	var title: String = "Send Feedback"
	var systemImage: String = "text.bubble"
	@State private var showSheet = false

	var body: some View {
		Button { showSheet = true } label: {
			Label(title, systemImage: systemImage)
		}
		.sheet(isPresented: $showSheet) {
			FeedbackFormView(config: config)
		}
	}
}

// MARK: - The form sheet

struct FeedbackFormView: View {
	let config: FeedbackConfig
	/// Value event that prompted this (only set when opened from a contextual nudge).
	let trigger: String?

	@Environment(\.dismiss) private var dismiss
	@State private var message = ""
	@State private var contact = ""
	@State private var category: FeedbackCategory
	@State private var betaOptIn = false
	@State private var state: SendState = .idle
	@FocusState private var messageFocused: Bool

	init(config: FeedbackConfig, presetCategory: FeedbackCategory? = nil, trigger: String? = nil) {
		self.config = config
		self.trigger = trigger
		_category = State(initialValue: presetCategory ?? .useCase)
	}

	private enum SendState: Equatable { case idle, sending, success, failed }
	private var canSend: Bool {
		state != .sending && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			header

			if state == .success {
				successView
			} else {
				categoryPicker
				editor
				contactField
				betaToggle
				if state == .failed { failureNotice }
				sendButton
				privacyNote
			}
			Spacer(minLength: 0)
		}
		.padding(20)
		.frame(maxWidth: .infinity, alignment: .leading)
		#if os(macOS)
		.frame(minWidth: 400, minHeight: 480)
		#endif
		.onAppear { messageFocused = true }
	}

	// MARK: pieces

	private var header: some View {
		HStack(alignment: .top) {
			VStack(alignment: .leading, spacing: 4) {
				Text("Feedback").font(.title2.bold())
				Text(config.prompt)
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			Spacer()
			Button {
				dismiss()
			} label: {
				Image(systemName: "xmark.circle.fill")
					.font(.title2)
					.foregroundStyle(.secondary)
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Close")
		}
	}

	private var categoryPicker: some View {
		HStack(spacing: 8) {
			Text("This is…").font(.subheadline).foregroundStyle(.secondary)
			Picker("Category", selection: $category) {
				ForEach(FeedbackCategory.allCases) { Text($0.title).tag($0) }
			}
			.pickerStyle(.menu)
			.labelsHidden()
			Spacer()
		}
	}

	private var betaToggle: some View {
		Toggle(isOn: $betaOptIn) {
			Text("I'd be happy to help test new features")
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
		#if os(iOS)
		.toggleStyle(.switch)
		#endif
	}

	private var editor: some View {
		ZStack(alignment: .topLeading) {
			RoundedRectangle(cornerRadius: 10, style: .continuous)
				.stroke(Color.secondary.opacity(0.3), lineWidth: 1)
			if message.isEmpty {
				Text("What's on your mind?")
					.foregroundStyle(.tertiary)
					.padding(.horizontal, 12)
					.padding(.vertical, 12)
					.allowsHitTesting(false)
			}
			// Clamp to the server's 4000-char cap via the binding itself — avoids
			// onChange(of:perform:), which is deprecated on iOS 17 and keeps the
			// iOS 15 / macOS 12 floor warning-free.
			TextEditor(text: Binding(
				get: { message },
				set: { message = String($0.prefix(4000)) }
			))
				.focused($messageFocused)
				.frame(minHeight: 140)
				.padding(6)
				.scrollContentBackgroundHiddenIfAvailable()
		}
		.frame(minHeight: 152)
	}

	private var contactField: some View {
		VStack(alignment: .leading, spacing: 4) {
			TextField("Email (optional — only if you'd like a reply)", text: $contact)
				.textFieldStyle(.roundedBorder)
				#if os(iOS)
				.keyboardType(.emailAddress)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled(true)
				#endif
		}
	}

	private var sendButton: some View {
		Button {
			Task { await send() }
		} label: {
			HStack {
				if state == .sending { ProgressView().controlSize(.small) }
				Text(state == .sending ? "Sending…" : "Send Feedback")
					.fontWeight(.semibold)
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 6)
		}
		.buttonStyle(.borderedProminent)
		.disabled(!canSend)
	}

	private var failureNotice: some View {
		VStack(alignment: .leading, spacing: 8) {
			Label("Couldn't reach the server.", systemImage: "wifi.exclamationmark")
				.font(.footnote)
				.foregroundStyle(.secondary)
			Button {
				openMailFallback()
			} label: {
				Label("Send via email instead", systemImage: "envelope")
					.font(.footnote)
			}
			.buttonStyle(.plain)
			.foregroundStyle(.tint)
		}
		.padding(10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
	}

	private var privacyNote: some View {
		Text("Sends your message plus your app version and device model. "
			+ "Your email is only included if you type one.")
			.font(.caption2)
			.foregroundStyle(.tertiary)
			.fixedSize(horizontal: false, vertical: true)
	}

	private var successView: some View {
		VStack(spacing: 12) {
			Image(systemName: "checkmark.circle.fill")
				.font(.system(size: 44))
				.foregroundStyle(.green)
			Text("Thank you — I read every message.")
				.font(.headline)
				.multilineTextAlignment(.center)
			if !contact.trimmingCharacters(in: .whitespaces).isEmpty {
				Text("I'll reply to \(contact) if a response is needed.")
					.font(.footnote)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
			}
			Button("Done") { dismiss() }
				.buttonStyle(.borderedProminent)
				.padding(.top, 4)
		}
		.frame(maxWidth: .infinity)
		.padding(.top, 24)
	}

	// MARK: send

	@MainActor
	private func send() async {
		state = .sending
		let trimmedContact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
		do {
			try await FeedbackClient(config: config).submit(
				message: message,
				contact: trimmedContact.isEmpty ? nil : trimmedContact,
				category: category,
				trigger: trigger,
				betaOptIn: betaOptIn
			)
			state = .success
		} catch {
			state = .failed
		}
	}

	private func openMailFallback() {
		guard let url = FeedbackClient(config: config).mailtoURL(message: message, contact: contact) else { return }
		#if os(iOS) || os(tvOS)
		UIApplication.shared.open(url)
		#elseif os(macOS)
		NSWorkspace.shared.open(url)
		#endif
	}
}

// MARK: - Networking

struct FeedbackClient {
	let config: FeedbackConfig

	enum FeedbackError: Error { case badStatus(Int) }

	func submit(
		message: String,
		contact: String?,
		category: FeedbackCategory = .other,
		trigger: String? = nil,
		betaOptIn: Bool = false
	) async throws {
		var req = URLRequest(url: config.endpoint)
		req.httpMethod = "POST"
		req.setValue("application/json", forHTTPHeaderField: "Content-Type")
		req.timeoutInterval = 20
		if let key = config.submitKey { req.setValue(key, forHTTPHeaderField: "X-Feedback-Key") }

		var payload: [String: Any] = [
			"app": config.appID,
			"appName": config.appName,
			"appVersion": FeedbackEnv.appVersion,
			"build": FeedbackEnv.build,
			"platform": FeedbackEnv.platform,
			"osVersion": FeedbackEnv.osVersion,
			"device": FeedbackEnv.device,
			"locale": FeedbackEnv.locale,
			"message": message,
			"category": category.rawValue,
			"betaOptIn": betaOptIn,
		]
		if let contact, !contact.isEmpty { payload["contact"] = contact }
		if let trigger, !trigger.isEmpty { payload["trigger"] = trigger }
		req.httpBody = try JSONSerialization.data(withJSONObject: payload)

		let (_, resp) = try await URLSession.shared.data(for: req)
		guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
			throw FeedbackError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1)
		}
	}

	/// Pre-filled mailto used as the offline/failure fallback.
	func mailtoURL(message: String, contact: String?) -> URL? {
		let subject = "\(config.appName) Feedback"
		var body = message
		body += "\n\n———\nSent from \(config.appName) \(FeedbackEnv.appVersion) (\(FeedbackEnv.build)) · "
		body += "\(FeedbackEnv.device) · \(FeedbackEnv.platform) \(FeedbackEnv.osVersion)"
		if let contact, !contact.isEmpty { body += "\nReply-to: \(contact)" }

		var comps = URLComponents()
		comps.scheme = "mailto"
		comps.path = config.fallbackEmail
		comps.queryItems = [
			URLQueryItem(name: "subject", value: subject),
			URLQueryItem(name: "body", value: body),
		]
		return comps.url
	}
}

// MARK: - Environment metadata

enum FeedbackEnv {
	static var appName: String {
		(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
			?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
			?? "App"
	}
	static var bundleID: String { Bundle.main.bundleIdentifier ?? "unknown" }
	static var appVersion: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
	}
	static var build: String {
		Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
	}
	static var osVersion: String {
		let v = ProcessInfo.processInfo.operatingSystemVersion
		return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
	}
	static var locale: String { Locale.current.identifier }
	static var platform: String {
		#if os(macOS)
		return "macos"
		#elseif os(tvOS)
		return "tvos"
		#elseif os(watchOS)
		return "watchos"
		#else
		return ProcessInfo.processInfo.isiOSAppOnMac ? "ios_on_mac" : "ios"
		#endif
	}
	/// Hardware model identifier, e.g. "iPhone16,2" or "Mac15,3".
	static var device: String {
		#if os(macOS)
		return sysctlString("hw.model") ?? "Mac"
		#else
		var sys = utsname()
		uname(&sys)
		let mirror = Mirror(reflecting: sys.machine)
		let id = mirror.children.reduce(into: "") { acc, el in
			if let value = el.value as? Int8, value != 0 {
				acc.append(Character(UnicodeScalar(UInt8(value))))
			}
		}
		return id.isEmpty ? "unknown" : id
		#endif
	}

	#if os(macOS)
	private static func sysctlString(_ name: String) -> String? {
		var size = 0
		guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
		var buffer = [CChar](repeating: 0, count: size)
		guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
		return String(cString: buffer)
	}
	#endif
}

// MARK: - Contextual nudge (surfaces #2 & #3)

/// Prompts for feedback *after* the app proves it worked. Call `recordSuccess` on a
/// value event (export done, scan copied, routine finished) or `recordFailure` on a
/// repeated error. Arms a non-modal card (shown by `.feedbackNudge`) once the count
/// crosses a threshold, then stays quiet: at most once per app version, and never
/// within `cooldownDays` of a dismissal. State persists in UserDefaults (per app).
///
/// Usage:
///   RootView().feedbackNudge(config: FeedbackConfig(appName: "MyApp"))   // once, at root
///   FeedbackNudge.shared.recordSuccess("third_export")                    // on a value event
final class FeedbackNudge: ObservableObject {
	static let shared = FeedbackNudge()

	struct Prompt: Identifiable, Equatable {
		let id = UUID()
		let kind: Kind
		let trigger: String
	}
	enum Kind { case success, failure }

	@Published private(set) var active: Prompt?

	private let defaults = UserDefaults.standard
	private var version: String { FeedbackEnv.appVersion }
	private func key(_ suffix: String) -> String { "feedbackNudge.\(suffix)" }

	/// Record a value event. Default: arm after the 3rd success this app version.
	func recordSuccess(_ trigger: String, promptAfter: Int = 3, cooldownDays: Int = 30) {
		record(.success, trigger: trigger, threshold: promptAfter, cooldownDays: cooldownDays)
	}
	/// Record a failure / troubleshooting action. Default: arm after the 2nd.
	func recordFailure(_ trigger: String, promptAfter: Int = 2, cooldownDays: Int = 30) {
		record(.failure, trigger: trigger, threshold: promptAfter, cooldownDays: cooldownDays)
	}

	/// User tapped "Tell me" — clear the card; the form takes over.
	func consume() { setActive(nil) }
	/// User dismissed the card — clear it and start the cooldown.
	func dismiss() {
		defaults.set(Date().timeIntervalSince1970, forKey: key("dismissedAt"))
		setActive(nil)
	}

	private func record(_ kind: Kind, trigger: String, threshold: Int, cooldownDays: Int) {
		if active != nil { return }
		if defaults.string(forKey: key("promptedVersion")) == version { return } // once per version
		let dismissedAt = defaults.double(forKey: key("dismissedAt"))
		if dismissedAt > 0, Date().timeIntervalSince1970 - dismissedAt < Double(cooldownDays) * 86400 { return }

		let ck = key("count.\(kind == .success ? "success" : "failure").\(version)")
		let n = defaults.integer(forKey: ck) + 1
		defaults.set(n, forKey: ck)
		guard n >= threshold else { return }
		defaults.set(version, forKey: key("promptedVersion"))
		setActive(Prompt(kind: kind, trigger: trigger))
	}

	private func setActive(_ p: Prompt?) {
		if Thread.isMainThread { active = p }
		else { DispatchQueue.main.async { self.active = p } }
	}
}

/// Attach once near your root view; shows the non-modal nudge card when armed.
extension View {
	func feedbackNudge(config: FeedbackConfig) -> some View {
		modifier(FeedbackNudgeModifier(config: config))
	}
}

private struct FeedbackNudgeModifier: ViewModifier {
	let config: FeedbackConfig
	@ObservedObject private var nudge = FeedbackNudge.shared
	@State private var showForm = false
	@State private var preset: (category: FeedbackCategory, trigger: String)?

	func body(content: Content) -> some View {
		content
			.overlay(alignment: .bottom) {
				if let prompt = nudge.active {
					NudgeCard(
						kind: prompt.kind,
						appName: config.appName,
						onTell: {
							preset = (prompt.kind == .failure ? .bug : .useCase, prompt.trigger)
							nudge.consume()
							showForm = true
						},
						onDismiss: { nudge.dismiss() }
					)
					.padding(.horizontal, 12)
					.padding(.bottom, 12)
					.transition(.move(edge: .bottom).combined(with: .opacity))
				}
			}
			.animation(.spring(response: 0.4, dampingFraction: 0.85), value: nudge.active?.id)
			.sheet(isPresented: $showForm) {
				FeedbackFormView(config: config, presetCategory: preset?.category, trigger: preset?.trigger)
			}
	}
}

private struct NudgeCard: View {
	let kind: FeedbackNudge.Kind
	let appName: String
	let onTell: () -> Void
	let onDismiss: () -> Void

	private var title: String {
		kind == .failure ? "Something not working?" : "What are you using \(appName) to do?"
	}

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: kind == .failure ? "exclamationmark.bubble" : "text.bubble")
				.font(.title3)
				.foregroundStyle(.tint)
			VStack(alignment: .leading, spacing: 2) {
				Text(title).font(.subheadline.weight(.semibold))
				Text("A quick note helps me improve it — I read every one.")
					.font(.caption).foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			Spacer(minLength: 4)
			Button("Tell me", action: onTell)
				.buttonStyle(.borderedProminent)
				.controlSize(.small)
			Button(action: onDismiss) {
				Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Dismiss")
		}
		.padding(12)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.secondary.opacity(0.15)))
		.shadow(color: .black.opacity(0.12), radius: 10, y: 4)
		.frame(maxWidth: 520)
	}
}

// MARK: - Small compatibility shim

private extension View {
	/// Hide the TextEditor's default background where the API exists (iOS 16+/macOS 13+),
	/// no-op below that so the block still builds on the iOS 15 / macOS 12 floor.
	@ViewBuilder
	func scrollContentBackgroundHiddenIfAvailable() -> some View {
		if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
			self.scrollContentBackground(.hidden)
		} else {
			self
		}
	}
}
