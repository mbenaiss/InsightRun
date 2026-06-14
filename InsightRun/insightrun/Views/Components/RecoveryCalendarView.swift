//
//  RecoveryCalendarView.swift
//  InsightRun
//
//  Calendar view for browsing recovery history with score indicators
//

import SwiftUI

struct RecoveryCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool
    let onDateSelected: (Date) async -> Void

    @State private var displayedMonth: Date = Date()
    @State private var recoveryScores: [Date: Int] = [:]
    @State private var isLoadingScores = false

    private let calendar = Calendar.current
    private let daysOfWeek: [String] = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        return formatter.veryShortWeekdaySymbols.rotatedToStartOnMonday()
    }()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Month Header
                monthHeader
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.base)

                // Days of Week Header
                daysOfWeekHeader
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.lg)

                // Calendar Grid
                calendarGrid
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)

                Spacer()

                // Bottom Bar
                bottomBar
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
            }
            .background(Color.irBackgroundApp)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(IRFont.title2)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .accessibilityLabel(String(localized: "Close", comment: "Accessibility label for sheet close button"))
                }
            }
        }
        .task {
            await loadRecoveryScores()
        }
        .onChange(of: displayedMonth) { _, _ in
            Task {
                await loadRecoveryScores()
            }
        }
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Text(monthYearString)
                .font(IRFont.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            // Navigation Arrows
            HStack(spacing: Spacing.base) {
                Button {
                    goToPreviousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(IRFont.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.irTextPrimary)
                        .frame(width: 40, height: 40)
                        .background(Color.irCardBackground)
                        .clipShape(Circle())
                }
                .accessibilityLabel(String(localized: "Previous month", comment: "Accessibility label for previous month navigation button"))

                Button {
                    goToNextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(IRFont.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(canGoToNextMonth ? Color.irTextPrimary : Color.irTextTertiary)
                        .frame(width: 40, height: 40)
                        .background(Color.irCardBackground)
                        .clipShape(Circle())
                }
                .disabled(!canGoToNextMonth)
                .accessibilityLabel(String(localized: "Next month", comment: "Accessibility label for next month navigation button"))
            }
        }
    }

    // MARK: - Days of Week Header

    private var daysOfWeekHeader: some View {
        HStack(spacing: 0) {
            ForEach(daysOfWeek, id: \.self) { day in
                Text(day)
                    .font(IRFont.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irTextSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let days = daysInMonth()

        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.xxs), count: 7), spacing: Spacing.md) {
            ForEach(days, id: \.self) { date in
                if let date = date {
                    dayCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 70)
                }
            }
        }
        .id(displayedMonth)
    }

    // MARK: - Day Cell

    private func dayCell(for date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let isFuture = date > Date()
        let score = recoveryScores[calendar.startOfDay(for: date)]

        return Button {
            if !isFuture {
                selectedDate = date
                Task {
                    await onDateSelected(date)
                    isPresented = false
                }
            }
        } label: {
            VStack(spacing: Spacing.xxs) {
                // Recovery Score Ring
                ZStack {
                    // Background ring
                    Circle()
                        .stroke(Color.irCardBackground, lineWidth: 4)
                        .frame(width: 40, height: 40)

                    if let score = score, !isFuture {
                        // Progress ring
                        Circle()
                            .trim(from: 0, to: CGFloat(score) / 100.0)
                            .stroke(
                                scoreColor(for: score),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(-90))
                    }

                    // Day number
                    Text("\(calendar.component(.day, from: date))")
                        .font(IRFont.body)
                        .fontWeight(isToday ? .bold : .medium)
                        .foregroundStyle(isFuture ? Color.irTextTertiary : Color.irTextPrimary)
                }

                // Sleep indicator (if score is low, show bed icon)
                if let score = score, score < 50, !isFuture {
                    Image(systemName: "bed.double.fill")
                        .font(IRFont.microLabel)
                        .foregroundStyle(scoreColor(for: score))
                }
            }
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isSelected ? Color.irCardBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(dayCellAccessibilityLabel(for: date, score: score, isFuture: isFuture))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            // Today Button
            Button {
                displayedMonth = Date()
                selectedDate = Date()
                Task {
                    await onDateSelected(Date())
                    isPresented = false
                }
            } label: {
                Text(String(localized: "Today", comment: "Button to go to today"))
                    .font(IRFont.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextPrimary)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .background(Color.irCardBackground)
                    .clipShape(Capsule())
            }

            Spacer()

            if isLoadingScores {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(String(localized: "Loading recovery scores", comment: "Accessibility label for calendar loading indicator"))
            }
        }
    }

    // MARK: - Helpers

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: displayedMonth).lowercased()
    }

    private var canGoToNextMonth: Bool {
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
        let startOfNextMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) ?? nextMonth
        return startOfNextMonth <= Date()
    }

    private func goToPreviousMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    private func goToNextMonth() {
        if canGoToNextMonth {
            displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
        }
    }

    private func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return []
        }

        // Get the first day of the month
        let firstDayOfMonth = monthInterval.start

        // Get the weekday of the first day (1 = Sunday, 2 = Monday, etc.)
        var weekdayOfFirst = calendar.component(.weekday, from: firstDayOfMonth)
        // Adjust for Monday start (Monday = 1, Sunday = 7)
        weekdayOfFirst = weekdayOfFirst == 1 ? 7 : weekdayOfFirst - 1

        // Number of days in month
        let numberOfDaysInMonth = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30

        var days: [Date?] = []

        // Add empty cells for days before the first day of the month
        for _ in 0..<(weekdayOfFirst - 1) {
            days.append(nil)
        }

        // Add all days of the month
        for day in 1...numberOfDaysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }

        // Fill remaining cells to complete the grid (up to 42 cells for 6 rows)
        while days.count < 42 && days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    private func scoreColor(for score: Int) -> Color {
        switch score {
        case 67...100:
            return Color.irSuccess
        case 50..<67:
            return Color.irWarning
        case 33..<50:
            return Color.irWarning
        default:
            return Color.irError
        }
    }

    private func dayCellAccessibilityLabel(for date: Date, score: Int?, isFuture: Bool) -> String {
        let dateText = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if let score, !isFuture {
            let format = String(localized: "%@, recovery score %lld out of 100", comment: "Accessibility label for a calendar day with a recovery score")
            return String(format: format, dateText, score)
        }
        return dateText
    }

    private func loadRecoveryScores() async {
        isLoadingScores = true

        // Get the date range for the displayed month
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            isLoadingScores = false
            return
        }

        // Load scores for each day of the month
        let healthKitManager = HealthKitManager.shared
        var scores: [Date: Int] = [:]

        let numberOfDays = calendar.range(of: .day, in: .month, for: displayedMonth)?.count ?? 30

        for dayOffset in 0..<numberOfDays {
            if let date = calendar.date(byAdding: .day, value: dayOffset, to: monthInterval.start) {
                let startOfDay = calendar.startOfDay(for: date)

                // Don't load future dates
                if startOfDay > Date() {
                    continue
                }

                do {
                    let metrics = try await healthKitManager.fetchRecoveryMetrics(for: date)
                    scores[startOfDay] = metrics.recoveryScore
                } catch {
                    // Skip days with no data
                }
            }
        }

        await MainActor.run {
            self.recoveryScores = scores
            self.isLoadingScores = false
        }
    }
}

// MARK: - Array Extension for Week Day Rotation

extension Array where Element == String {
    func rotatedToStartOnMonday() -> [String] {
        // Sunday is at index 0, we want Monday first
        guard count == 7 else { return self }
        return Array(self[1...]) + [self[0]]
    }
}

// MARK: - Preview

#Preview {
    RecoveryCalendarView(
        selectedDate: .constant(Date()),
        isPresented: .constant(true),
        onDateSelected: { _ in }
    )
}
