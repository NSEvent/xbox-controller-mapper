import SwiftUI

extension Text {
    /// Renders inline Markdown emphasis (`**bold**`, `*italic*`) from a runtime
    /// string, preserving whitespace, and falls back to the literal string if
    /// parsing fails. Shared by the short-Markdown surfaces in the app
    /// (controller pairing guides, community-profile setup notes) so they render
    /// identically and there's a single place to extend.
    init(inlineMarkdown string: String) {
        if let attributed = try? AttributedString(
            markdown: string,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            self = Text(attributed)
        } else {
            self = Text(string)
        }
    }
}
