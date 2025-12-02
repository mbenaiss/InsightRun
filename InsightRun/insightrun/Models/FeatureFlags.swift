import Foundation

/// Feature flags returned by the backend /api/config endpoint
/// Uses dynamic dictionary to support adding features without code changes
struct RemoteConfig: Codable {
    let features: [String: Bool]
}

/// Known feature keys (for type-safe access)
/// New features can be added to KV without iOS code changes
enum FeatureKey: String {
    case strava = "strava_enabled"
    // Add new feature keys here as needed
}

/// Default feature values (used when offline or feature not in config)
let DEFAULT_FEATURES: [String: Bool] = [
    FeatureKey.strava.rawValue: false, // Disabled until Strava API validation
]
