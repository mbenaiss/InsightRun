//
//  AgentModels.swift
//  InsightRun
//
//  Models for agentic AI function call results
//

import Foundation

// MARK: - Workout Generation Result

struct AgentWorkoutResult: Codable {
    let type: String
    let duration: Int
    let distance: Double?
    let targetPace: String?
    let notes: String?
    let steps: [AgentWorkoutStep]

    private enum CodingKeys: String, CodingKey {
        case type, duration, distance, targetPace, notes, steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decode(String.self, forKey: .type)
        // LLM may emit a fractional duration (e.g. 45.5); tolerate Double then round.
        self.duration = try c.decodeFlexibleInt(forKey: .duration) ?? 0
        self.distance = try c.decodeIfPresent(Double.self, forKey: .distance)
        self.targetPace = try c.decodeIfPresent(String.self, forKey: .targetPace)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes)
        self.steps = (try c.decodeIfPresent([AgentWorkoutStep].self, forKey: .steps)) ?? []
    }
}

private extension KeyedDecodingContainer {
    /// Decode an integer that the source may have encoded as a Double or numeric String.
    func decodeFlexibleInt(forKey key: Key) throws -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d.rounded()) }
        if let s = try? decodeIfPresent(String.self, forKey: key), let d = Double(s) { return Int(d.rounded()) }
        return nil
    }
}

struct AgentWorkoutStep: Codable, Identifiable {
    let id: UUID
    let type: String
    let duration: Int
    let description: String
    let targetPace: String?

    private enum CodingKeys: String, CodingKey {
        case type, duration, description, targetPace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.type = try container.decode(String.self, forKey: .type)
        self.duration = try container.decodeFlexibleInt(forKey: .duration) ?? 0
        self.description = (try container.decodeIfPresent(String.self, forKey: .description)) ?? ""
        self.targetPace = try container.decodeIfPresent(String.self, forKey: .targetPace)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(duration, forKey: .duration)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(targetPace, forKey: .targetPace)
    }

    var stepColor: String {
        switch type {
        case "warmup": return "orange"
        case "cooldown": return "blue"
        case "intervals": return "red"
        case "tempo": return "purple"
        default: return "green"
        }
    }

    var stepIcon: String {
        switch type {
        case "warmup": return "flame.fill"
        case "cooldown": return "snowflake"
        case "intervals": return "bolt.fill"
        case "tempo": return "gauge.with.dots.needle.67percent"
        default: return "figure.run"
        }
    }
}

// MARK: - Trend Analysis Result

struct AgentTrendResult: Codable {
    let metric: String
    let period: String
    let trend: String
    let percentageChange: Double
    let insights: [String]

    var trendIcon: String {
        switch trend {
        case "improving": return "arrow.up.right"
        case "declining": return "arrow.down.right"
        default: return "arrow.right"
        }
    }

    var trendColor: String {
        switch trend {
        case "improving": return "green"
        case "declining": return "red"
        default: return "orange"
        }
    }

    var metricDisplayName: String {
        switch metric {
        case "pace": return String(localized: "Pace", comment: "Trend metric name")
        case "heart_rate": return String(localized: "Heart Rate", comment: "Trend metric name")
        case "distance": return String(localized: "Distance", comment: "Trend metric name")
        case "cadence": return String(localized: "Cadence", comment: "Trend metric name")
        case "vo2max": return String(localized: "VO2 Max", comment: "Trend metric name")
        case "training_load": return String(localized: "Training Load", comment: "Trend metric name")
        case "recovery": return String(localized: "Recovery", comment: "Trend metric name")
        default: return metric.capitalized
        }
    }

    var periodDisplayName: String {
        switch period {
        case "week": return String(localized: "This Week", comment: "Trend period")
        case "month": return String(localized: "This Month", comment: "Trend period")
        case "quarter": return String(localized: "Last 3 Months", comment: "Trend period")
        case "year": return String(localized: "This Year", comment: "Trend period")
        default: return period.capitalized
        }
    }
}
