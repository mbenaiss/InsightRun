//
//  WeeklyCoachingService.swift
//  InsightRun
//
//  Generates a weekly recap coaching insight via the backend LLM
//  (`BackendAPIClient.classify`) and caches the result per ISO week.
//

import Foundation

struct WeeklyCoachingInsight: Codable, Equatable {
    /// One-sentence headline shown in the dashboard-style coach card.
    let tldr: String
    /// Single word in `tldr` that should be highlighted (lime accent).
    /// Optional — pass `nil` when nothing is worth emphasising.
    let highlight: String?
    /// Long-form coaching paragraph shown when the user expands the card.
    let detail: String
}

@MainActor
final class WeeklyCoachingService {
    static let shared = WeeklyCoachingService()

    private let backendClient = BackendAPIClient.shared
    private let cacheDefaults = UserDefaults.standard
    private let cachePrefix = "weeklyCoaching."

    /// Snapshot of the metrics needed to generate a coaching insight for a given week.
    struct Snapshot {
        let weekStart: Date
        let weekEnd: Date
        let language: String

        let runCount: Int
        let totalDistanceKm: Double
        let totalDurationMin: Int
        let averagePaceMinPerKm: Double?
        let prevTotalDistanceKm: Double
        let prevTotalDurationMin: Int

        let averageRecoveryScore: Int
        let recoveryScoreChange: Int?
        let averageHRV: Double?
        let hrvDelta: Double?
        let averageRestingHR: Double?
        let restingHRDelta: Double?

        let averageSleepHours: Double?
        let sleepDurationChangeMinutes: Int?
        let averageSleepEfficiency: Double?
    }

    // MARK: - Public

    /// Returns a cached insight for the snapshot's week if available, otherwise calls the LLM.
    /// - Returns: nil when the user hasn't consented to AI data sharing.
    func insight(for snapshot: Snapshot) async throws -> WeeklyCoachingInsight? {
        guard ConsentService.shared.hasConsentedToAIDataSharing else { return nil }

        let key = cacheKey(weekStart: snapshot.weekStart, language: snapshot.language)
        let isCompletedWeek = isWeekCompleted(weekStart: snapshot.weekStart)
        if let cached = loadCachedInsight(forKey: key, requireFreshForToday: !isCompletedWeek) {
            return cached
        }

        let prompt = buildPrompt(snapshot: snapshot)
        let systemPrompt = buildSystemPrompt(language: snapshot.language)
        // `.moderate` (not `.classification`) — the coach needs a multi-field JSON reply;
        // CLASSIFICATION caps the backend response at 10 tokens and truncates it.
        let raw = try await backendClient.classify(prompt: prompt, systemPrompt: systemPrompt, requestType: .moderate)

        guard let parsed = parse(raw: raw) else {
            throw WeeklyCoachingError.invalidResponse
        }

        cacheInsight(parsed, forKey: key)
        return parsed
    }

    /// A week is complete once its end (Sunday night for Monday-first locales) has passed.
    private func isWeekCompleted(weekStart: Date) -> Bool {
        let calendar = Calendar.current
        guard let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { return false }
        return Date() >= weekEnd
    }

    // MARK: - Cache

    private func cacheKey(weekStart: Date, language: String) -> String {
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)
        let year = comps.yearForWeekOfYear ?? 0
        let week = comps.weekOfYear ?? 0
        return "\(cachePrefix)\(year)-W\(week)-\(language)"
    }

    /// Cache envelope tracking when an insight was generated. The current week's
    /// recap is only valid for the day it was produced, so an early-week ("0 runs")
    /// insight isn't served frozen for the rest of the week as runs accumulate.
    private struct CachedEnvelope: Codable {
        let insight: WeeklyCoachingInsight
        let generatedAt: Date
    }

    private func loadCachedInsight(forKey key: String, requireFreshForToday: Bool) -> WeeklyCoachingInsight? {
        guard let data = cacheDefaults.data(forKey: key) else { return nil }
        if let envelope = try? JSONDecoder().decode(CachedEnvelope.self, from: data) {
            if requireFreshForToday, !Calendar.current.isDateInToday(envelope.generatedAt) {
                return nil
            }
            return envelope.insight
        }
        // Backward compatibility with entries written by older app versions.
        guard !requireFreshForToday else { return nil }
        return try? JSONDecoder().decode(WeeklyCoachingInsight.self, from: data)
    }

    private func cacheInsight(_ insight: WeeklyCoachingInsight, forKey key: String) {
        let envelope = CachedEnvelope(insight: insight, generatedAt: Date())
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        cacheDefaults.set(data, forKey: key)
    }

    /// Drops cached insight for the supplied week — used when the user pulls to refresh.
    func invalidateCache(weekStart: Date, language: String) {
        cacheDefaults.removeObject(forKey: cacheKey(weekStart: weekStart, language: language))
    }

    // MARK: - Prompts

    private func buildSystemPrompt(language: String) -> String {
        let langInstruction = language.lowercased().hasPrefix("fr")
            ? "Réponds en français, tutoie l'utilisateur."
            : "Reply in English, address the user as \"you\"."
        return """
        You are a senior running coach producing a one-week recap for an amateur runner.
        \(langInstruction)
        Output STRICTLY a single JSON object — no markdown fences, no prose around it — with this exact shape:
        {
          "tldr": "<one declarative sentence, 90–140 characters, no greeting>",
          "highlight": "<one short word from tldr to highlight, or empty>",
          "detail": "<two short sentences, 180–260 characters total, explaining the why and the next step>"
        }
        Rules:
        - Be specific. Reference the metrics provided when they support the message.
        - Avoid emojis, exclamation marks, hashtags, and rhetorical questions.
        - Never invent numbers that aren't in the input.
        - Write every number as digits ("17", "5:30/km"), never spelled out in words.
        """
    }

    private func buildPrompt(snapshot s: Snapshot) -> String {
        var lines: [String] = []
        lines.append("Week: \(formatDate(s.weekStart)) → \(formatDate(s.weekEnd))")
        lines.append("Runs this week: \(s.runCount)")
        lines.append(String(format: "Distance: %.1f km (prev %.1f km)", s.totalDistanceKm, s.prevTotalDistanceKm))
        lines.append("Duration: \(s.totalDurationMin) min (prev \(s.prevTotalDurationMin) min)")
        if let pace = s.averagePaceMinPerKm {
            lines.append(String(format: "Average pace: %.2f min/km", pace))
        }
        lines.append("Average recovery score: \(s.averageRecoveryScore)/100")
        if let delta = s.recoveryScoreChange {
            lines.append("Recovery delta vs previous week: \(formatSignedInt(delta)) pts")
        }
        if let hrv = s.averageHRV {
            var line = String(format: "Average HRV: %.0f ms", hrv)
            if let d = s.hrvDelta { line += String(format: " (delta %+.0f ms)", d) }
            lines.append(line)
        }
        if let rhr = s.averageRestingHR {
            var line = String(format: "Average resting HR: %.0f bpm", rhr)
            if let d = s.restingHRDelta { line += String(format: " (delta %+.0f bpm)", d) }
            lines.append(line)
        }
        if let sleep = s.averageSleepHours {
            var line = String(format: "Average sleep: %.1f h", sleep)
            if let dm = s.sleepDurationChangeMinutes { line += " (delta \(formatSignedInt(dm)) min)" }
            lines.append(line)
        }
        if let eff = s.averageSleepEfficiency {
            lines.append(String(format: "Sleep efficiency: %.0f %%", eff))
        }
        return lines.joined(separator: "\n")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func formatSignedInt(_ value: Int) -> String {
        value >= 0 ? "+\(value)" : "\(value)"
    }

    // MARK: - Parsing

    private func parse(raw: String) -> WeeklyCoachingInsight? {
        // The model occasionally wraps the JSON in fences — strip whitespace and the first/last `{}` block.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start <= end
        else {
            return nil
        }
        let jsonSlice = trimmed[start...end]
        guard let data = String(jsonSlice).data(using: .utf8) else { return nil }

        struct DecodedInsight: Decodable {
            let tldr: String
            let highlight: String?
            let detail: String
        }

        guard let decoded = try? JSONDecoder().decode(DecodedInsight.self, from: data) else {
            return nil
        }

        let highlight = decoded.highlight?.trimmingCharacters(in: .whitespacesAndNewlines)
        return WeeklyCoachingInsight(
            tldr: decoded.tldr.trimmingCharacters(in: .whitespacesAndNewlines),
            highlight: (highlight?.isEmpty == false) ? highlight : nil,
            detail: decoded.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

enum WeeklyCoachingError: Error {
    case invalidResponse
}
