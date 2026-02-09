//
//  WidgetDataReader.swift
//  InsightRunWidgets
//
//  Utility to read shared data from App Group UserDefaults
//

import Foundation

enum WidgetDataReader {
    private static let defaults = UserDefaults(suiteName: WidgetDataKeys.suiteName)

    static func read<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
