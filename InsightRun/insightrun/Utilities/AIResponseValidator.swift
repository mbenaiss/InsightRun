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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else { return false }
        let lastChar = trimmed.last
        return lastChar == "." || lastChar == "!" || lastChar == "?" || lastChar == "\u{2026}"
    }
}
