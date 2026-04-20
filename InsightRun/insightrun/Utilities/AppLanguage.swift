//
//  AppLanguage.swift
//  InsightRun
//
//  Resolves the effective UI language (bounded by the app's supported
//  localizations) rather than the raw system locale, so backend content
//  is generated in the language the user actually reads.
//

import Foundation

enum AppLanguage {
    /// 2-letter language code of the effective app localization.
    /// Uses `Bundle.main.preferredLocalizations` so the result is always one
    /// of the languages the app is actually localized in (system locale can
    /// be e.g. "ja" while the app only ships "en"/"fr").
    /// Cached: app localization is fixed for the lifetime of the process.
    static let current: String = {
        let raw = Bundle.main.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        return Locale(identifier: raw).language.languageCode?.identifier ?? "en"
    }()
}
