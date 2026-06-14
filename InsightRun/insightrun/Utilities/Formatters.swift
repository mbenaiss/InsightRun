//
//  Formatters.swift
//  InsightRun
//
//  Single source of truth for number / distance / pace formatting.
//  Locale-aware (decimal separator, metric vs imperial). Use this instead of
//  raw `String(format:)` with hard-coded separators or units in the UI.
//

import Foundation

// MARK: - Unit preference

enum UnitPreference {
    case metric
    case imperial

    /// Derived from the device locale; metric is the fallback.
    static var current: UnitPreference {
        Locale.current.measurementSystem == .us ? .imperial : .metric
    }

    var usesImperial: Bool { self == .imperial }
}

// MARK: - Formatters

enum Formatters {
    static let kmToMiles = 0.621371
    static let metersToFeet = 3.28084

    private static let unitsLabel: [UnitPreference: String] = [
        .metric: "km",
        .imperial: "mi",
    ]

    // MARK: Decimal (locale-aware separator)

    /// `value` formatted with the locale decimal separator (e.g. `5,2` in fr).
    static func decimal(
        _ value: Double,
        fractionDigits: Int = 1,
        locale: Locale = .current
    ) -> String {
        decimal(value, minFractionDigits: fractionDigits, maxFractionDigits: fractionDigits, locale: locale)
    }

    static func decimal(
        _ value: Double,
        minFractionDigits: Int,
        maxFractionDigits: Int,
        locale: Locale = .current
    ) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.minimumFractionDigits = minFractionDigits
        f.maximumFractionDigits = maxFractionDigits
        return f.string(from: value as NSNumber) ?? "\(value)"
    }

    /// Integer formatted with the locale grouping separator (e.g. `1 234`).
    static func integer(_ value: Int, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = locale
        f.maximumFractionDigits = 0
        return f.string(from: value as NSNumber) ?? "\(value)"
    }

    // MARK: Distance

    /// Distance value (km) converted to the preferred system, with unit suffix.
    /// e.g. `5,2 km` (metric, fr) or `3.2 mi` (imperial).
    static func distance(
        km: Double,
        fractionDigits: Int = 2,
        unit: UnitPreference = .current,
        locale: Locale = .current
    ) -> String {
        let value = distanceValue(km: km, unit: unit)
        return "\(decimal(value, fractionDigits: fractionDigits, locale: locale)) \(distanceUnitLabel(unit))"
    }

    /// Numeric-only distance in the preferred system (no unit suffix).
    static func distanceValue(km: Double, unit: UnitPreference = .current) -> Double {
        unit.usesImperial ? km * kmToMiles : km
    }

    /// Localized distance unit label (`km` / `mi`).
    static func distanceUnitLabel(_ unit: UnitPreference = .current) -> String {
        unitsLabel[unit] ?? "km"
    }

    /// Elevation / short distance in m (metric) or ft (imperial), no decimals.
    static func elevation(
        meters: Double,
        unit: UnitPreference = .current,
        locale: Locale = .current
    ) -> String {
        if unit.usesImperial {
            return "\(integer(Int((meters * metersToFeet).rounded()), locale: locale)) ft"
        }
        return "\(integer(Int(meters.rounded()), locale: locale)) m"
    }

    // MARK: Pace

    /// Pace from seconds-per-km, formatted `M:SS` + localized unit suffix.
    /// In imperial mode the value is converted to minutes-per-mile.
    static func paceFromSecondsPerKm(
        _ secondsPerKm: Double,
        unit: UnitPreference = .current
    ) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else {
            return "\(paceClock(0)) \(paceUnitSuffix(unit))"
        }
        let secondsPerUnit = unit.usesImperial ? secondsPerKm / kmToMiles : secondsPerKm
        return "\(paceClock(secondsPerUnit)) \(paceUnitSuffix(unit))"
    }

    /// Pace from minutes-per-km (decimal minutes, e.g. `5.5` = 5:30/km).
    static func paceFromMinutesPerKm(
        _ minutesPerKm: Double,
        unit: UnitPreference = .current
    ) -> String {
        paceFromSecondsPerKm(minutesPerKm * 60, unit: unit)
    }

    /// Canonical average pace = total duration / total distance.
    /// Never average the individual paces — always weight by distance via this.
    static func averagePace(
        totalDurationSeconds: Double,
        totalDistanceKm: Double,
        unit: UnitPreference = .current
    ) -> String? {
        guard totalDistanceKm > 0, totalDurationSeconds > 0 else { return nil }
        return paceFromSecondsPerKm(totalDurationSeconds / totalDistanceKm, unit: unit)
    }

    /// `M:SS` clock for a per-unit pace expressed in seconds (no unit suffix).
    static func paceClock(_ secondsPerUnit: Double) -> String {
        let total = Int(secondsPerUnit.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Localized pace unit suffix (`/km` or `/mi`).
    static func paceUnitSuffix(_ unit: UnitPreference = .current) -> String {
        "/\(distanceUnitLabel(unit))"
    }

    // MARK: Speed

    /// Speed in km/h (metric) or mph (imperial) from a m/s value.
    static func speed(
        metersPerSecond: Double,
        unit: UnitPreference = .current,
        locale: Locale = .current
    ) -> String {
        let kmh = metersPerSecond * 3.6
        if unit.usesImperial {
            return "\(decimal(kmh * kmToMiles, fractionDigits: 1, locale: locale)) mph"
        }
        return "\(decimal(kmh, fractionDigits: 1, locale: locale)) km/h"
    }

    // MARK: Heart rate / percentage / cadence

    /// Heart rate with localized `bpm` suffix.
    static func heartRate(_ bpm: Double, locale: Locale = .current) -> String {
        "\(integer(Int(bpm.rounded()), locale: locale)) bpm"
    }

    /// Percentage with localized separator and `%` suffix (e.g. `82 %`).
    static func percent(
        _ value: Double,
        fractionDigits: Int = 0,
        signed: Bool = false,
        locale: Locale = .current
    ) -> String {
        let sign = signed && value > 0 ? "+" : ""
        return "\(sign)\(decimal(value, fractionDigits: fractionDigits, locale: locale)) %"
    }

    /// Cadence with localized `spm` (steps per minute) suffix.
    static func cadence(_ spm: Double, locale: Locale = .current) -> String {
        "\(integer(Int(spm.rounded()), locale: locale)) spm"
    }

    /// Calories with localized `kcal` suffix.
    static func calories(_ kcal: Double, locale: Locale = .current) -> String {
        "\(integer(Int(kcal.rounded()), locale: locale)) kcal"
    }
}
