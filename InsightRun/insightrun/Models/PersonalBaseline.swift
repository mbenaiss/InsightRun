//
//  PersonalBaseline.swift
//  InsightRun
//
//  Personal baseline metrics computed from rolling averages
//  Used for Whoop/Oura-style deviation-based recovery scoring
//

import Foundation

struct PersonalBaseline: Codable, Identifiable {
    let id: UUID
    let computedAt: Date
    let dataPointCount: Int

    // Heart Rate Metrics
    let restingHeartRateAverage: Double?
    let restingHeartRateStdDev: Double?
    let hrvAverage: Double?
    let hrvStdDev: Double?
    let walkingHeartRateAverage: Double?
    let walkingHeartRateStdDev: Double?

    // Respiratory
    let respiratoryRateAverage: Double?
    let respiratoryRateStdDev: Double?

    // SpO2 (Oxygen Saturation)
    let oxygenSaturationAverage: Double?
    let oxygenSaturationStdDev: Double?

    // Sleep Metrics
    let sleepDurationAverage: TimeInterval?
    let sleepEfficiencyAverage: Double?
    let deepSleepPercentageAverage: Double?
    let remSleepPercentageAverage: Double?

    // MARK: - Computed Properties

    /// Baseline is reliable when we have at least 7 days of data
    var isReliable: Bool {
        dataPointCount >= 7
    }

    /// Baseline needs refresh if older than 24 hours
    var needsRefresh: Bool {
        let hoursSinceComputed = Date().timeIntervalSince(computedAt) / 3600
        return hoursSinceComputed > 24
    }

    // MARK: - Z-Score Calculation

    /// Calculate z-score for a given metric
    /// Returns how many standard deviations the value is from the mean
    func zScore(value: Double, average: Double?, stdDev: Double?) -> Double? {
        guard let avg = average, let std = stdDev, std > 0 else { return nil }
        return (value - avg) / std
    }

    // MARK: - Factory

    static func empty() -> PersonalBaseline {
        PersonalBaseline(
            id: UUID(),
            computedAt: Date(),
            dataPointCount: 0,
            restingHeartRateAverage: nil,
            restingHeartRateStdDev: nil,
            hrvAverage: nil,
            hrvStdDev: nil,
            walkingHeartRateAverage: nil,
            walkingHeartRateStdDev: nil,
            respiratoryRateAverage: nil,
            respiratoryRateStdDev: nil,
            oxygenSaturationAverage: nil,
            oxygenSaturationStdDev: nil,
            sleepDurationAverage: nil,
            sleepEfficiencyAverage: nil,
            deepSleepPercentageAverage: nil,
            remSleepPercentageAverage: nil
        )
    }
}
