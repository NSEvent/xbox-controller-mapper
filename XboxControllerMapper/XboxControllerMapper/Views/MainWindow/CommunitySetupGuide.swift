import SwiftUI

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
		Text(inlineMarkdown: text)
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
			.accessibilityLabel(didCopy ? "Copied" : "Copy code")
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
