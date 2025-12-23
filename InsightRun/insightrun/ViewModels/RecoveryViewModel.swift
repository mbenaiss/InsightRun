//
//  RecoveryViewModel.swift
//  InsightRun
//
//  ViewModel for recovery and readiness metrics
//

import SwiftUI
import Combine

enum BaselineStatus {
    case notAvailable
    case building(days: Int)
    case ready(days: Int)

    var description: String {
        switch self {
        case .notAvailable:
            return String(localized: "Not enough data for personal baseline", comment: "Baseline status - not available")
        case .building(let days):
            return String(localized: "Building baseline: \(days)/7 days", comment: "Baseline status - building")
        case .ready(let days):
            return String(localized: "Based on \(days)-day personal baseline", comment: "Baseline status - ready")
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

@MainActor
class RecoveryViewModel: ObservableObject {
    @Published var metricsCache: [Date: RecoveryMetrics] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedDate: Date
    @Published var recentWorkoutsCount: Int = 0
    @Published var baselineStatus: BaselineStatus = .notAvailable

    init() {
        // Initialize to start of today to match availableDates
        self.selectedDate = Calendar.current.startOfDay(for: Date())
    }

    private let healthKitManager = HealthKitManager.shared

    var recoveryMetrics: RecoveryMetrics? {
        let dateKey = Calendar.current.startOfDay(for: selectedDate)
        return metricsCache[dateKey]
    }

    func metrics(for date: Date) -> RecoveryMetrics? {
        let dateKey = Calendar.current.startOfDay(for: date)
        return metricsCache[dateKey]
    }

    func loadRecoveryMetrics(for date: Date? = nil) async {
        let targetDate = date ?? selectedDate
        let dateKey = Calendar.current.startOfDay(for: targetDate)
        
        // If it's the selected date and not in cache, show loading
        if date == nil || Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
            if metricsCache[dateKey] == nil {
                isLoading = true
            }
            errorMessage = nil
        }

        do {
            let metrics = try await healthKitManager.fetchRecoveryMetrics(for: targetDate)
            metricsCache[dateKey] = metrics

            // Update baseline status for UI if this is the selected date
            if Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
                if let baseline = metrics.baseline {
                    if baseline.isReliable {
                        baselineStatus = .ready(days: baseline.dataPointCount)
                    } else {
                        baselineStatus = .building(days: baseline.dataPointCount)
                    }
                } else {
                    baselineStatus = .notAvailable
                }
            }

            if Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
                await loadRecentWorkoutsCount()
            }
            
            // Preload adjacent days if we just loaded the main date
            if date == nil || Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
                await preloadAdjacentDays(for: targetDate)
            }

        } catch {
            if Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
                errorMessage = String(localized: "Unable to load recovery metrics: \(error.localizedDescription)", comment: "Recovery metrics loading error")
            }
        }

        if Calendar.current.isDate(targetDate, inSameDayAs: selectedDate) {
            isLoading = false
        }
    }
    
    private func preloadAdjacentDays(for date: Date) async {
        let prevDay = Calendar.current.date(byAdding: .day, value: -1, to: date) ?? date
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        
        // Check cache before loading
        let prevKey = Calendar.current.startOfDay(for: prevDay)
        if metricsCache[prevKey] == nil {
            Task {
                try? await loadRecoveryMetricsWithoutSideEffects(for: prevDay)
            }
        }
        
        // Only preload next day if it's not in future (assuming we don't predict future recovery)
        if nextDay <= Date() {
            let nextKey = Calendar.current.startOfDay(for: nextDay)
            if metricsCache[nextKey] == nil {
                Task {
                    try? await loadRecoveryMetricsWithoutSideEffects(for: nextDay)
                }
            }
        }
    }
    
    private func loadRecoveryMetricsWithoutSideEffects(for date: Date) async throws {
        let metrics = try await healthKitManager.fetchRecoveryMetrics(for: date)
        let dateKey = Calendar.current.startOfDay(for: date)
        metricsCache[dateKey] = metrics
    }

    /// Load count of recent workouts (last 7 days)
    private func loadRecentWorkoutsCount() async {
        do {
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            recentWorkoutsCount = try await healthKitManager.getRecentWorkoutsCount(since: sevenDaysAgo)
        } catch {
            recentWorkoutsCount = 0
        }
    }

    func refresh() async {
        metricsCache.removeAll() // Clear cache on pull-to-refresh
        await loadRecoveryMetrics()
    }

    func goToPreviousDay() async {
        if let newDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) {
            selectedDate = Calendar.current.startOfDay(for: newDate)
        }
        await loadRecoveryMetrics()
    }

    func goToNextDay() async {
        let today = Calendar.current.startOfDay(for: Date())
        if let newDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) {
            let normalizedNewDate = Calendar.current.startOfDay(for: newDate)
            // Don't go past today
            if normalizedNewDate <= today {
                selectedDate = normalizedNewDate
            }
        }
        await loadRecoveryMetrics()
    }

    func goToToday() async {
        selectedDate = Calendar.current.startOfDay(for: Date())
        await loadRecoveryMetrics()
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// Force refresh of personal baseline
    func refreshBaseline() async {
        do {
            let newBaseline = try await healthKitManager.computePersonalBaseline()
            PersonalBaselineStorage.shared.save(newBaseline)
            metricsCache.removeAll() // Invalidate all cached metrics as baseline changed
            await loadRecoveryMetrics()
        } catch {
            errorMessage = "Unable to refresh baseline: \(error.localizedDescription)"
        }
    }

    var formattedSelectedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current

        if Calendar.current.isDateInToday(selectedDate) {
            return String(localized: "Today", comment: "Label for today's date")
        } else if Calendar.current.isDateInYesterday(selectedDate) {
            return String(localized: "Yesterday", comment: "Label for yesterday's date")
        } else {
            formatter.dateFormat = "EEEE d MMMM yyyy"
            return formatter.string(from: selectedDate).capitalized
        }
    }

    /// Long format for dropdown: "Aujourd'hui, 23 décembre" or "Lundi, 22 décembre"
    var formattedSelectedDateLong: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current

        if Calendar.current.isDateInToday(selectedDate) {
            formatter.dateFormat = "d MMMM"
            let dateString = formatter.string(from: selectedDate)
            return String(localized: "Today, \(dateString)", comment: "Today with date format")
        } else if Calendar.current.isDateInYesterday(selectedDate) {
            formatter.dateFormat = "d MMMM"
            let dateString = formatter.string(from: selectedDate)
            return String(localized: "Yesterday, \(dateString)", comment: "Yesterday with date format")
        } else {
            formatter.dateFormat = "EEEE, d MMMM"
            return formatter.string(from: selectedDate).capitalized
        }
    }
}
