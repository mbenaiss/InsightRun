//
//  StringHelpers.swift
//  InsightRun
//

import Foundation

extension String {
    /// Returns the string when it has non-whitespace content, otherwise `nil`.
    /// Convenient for fallback chaining: `optional?.nilIfEmpty ?? fallback`.
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
