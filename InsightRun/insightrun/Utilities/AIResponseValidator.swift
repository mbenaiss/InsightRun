//
//  AIResponseValidator.swift
//  InsightRun
//
//  Shared completeness check for streamed AI text, so a stream cut short by a
//  transient failure is never cached or displayed as a final, truncated answer.
//

import Foundation

enum AIResponseValidator {
    /// A streamed response is complete when it has substantive content and ends on
    /// terminal punctuation. A bare prefix or a sentence cut mid-word fails this check.
    static func isComplete(_ text: String) -> Bool {
        guard
            let markdown = try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        else { return false }

        let trimmed = String(markdown.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else { return false }
        let closingQuotes = CharacterSet(charactersIn: "\"'\u{201D}\u{2019}\u{00BB}").union(.whitespacesAndNewlines)
        let lastChar = trimmed.trimmingCharacters(in: closingQuotes).last
        return lastChar == "." || lastChar == "!" || lastChar == "?" || lastChar == "\u{2026}"
    }
}
