//
//  WeeklySummaryView.swift
//  InsightRun
//
//  Weekly recap screen following the Insight Run "v4-weekly-recap" design.
//  Sections (in order): Recovery + inline coach insight, Running, Sleep, Biometry,
//  vs Previous Week. Section eyebrows are unnumbered.
//

import SwiftUI

struct WeeklySummaryView: View {
    @StateObject private var viewModel = WeeklySummaryViewModel()

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else {
                summaryContent
            }
        }
        .background(Color.irBackgroundApp.ignoresSafeArea())
        .navigationTitle(String(localized: "Weekly Summary", comment: "Navigation title for weekly summary"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            ProgressView().scaleEffect(1.2)
            Text(String(localized: "Loading...", comment: "Loading indicator text"))
                .font(IRFont.eyebrow)
                .tracking(IRTracking.eyebrow)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.base) {
            Image(systemName: "exclamationmark.triangle")
                .font(IRFont.numMD)
                .foregroundStyle(Color.irWarning)
            Text(message)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xxl)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    // MARK: - Content

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            weekHeader
                .padding(.horizontal)

            section(title: String(localized: "Recovery", comment: "Weekly recap section: recovery")) {
                recoveryHeroCard
            }

            section(title: String(localized: "Coach", comment: "Weekly recap section: coach")) {
                weeklyCoachCard
            }

            section(title: String(localized: "Running", comment: "Weekly recap section: running")) {
                runningCard
            }

            if viewModel.averageSleepDuration > 0 {
                section(title: String(localized: "Sleep", comment: "Weekly recap section: sleep")) {
                    sleepCard
                }
            }

            if hasAnyBiometric {
                section(title: String(localized: "Biometrics", comment: "Weekly recap section: biometrics")) {
                    biometricsGrid
                }
            }

            if hasAnyComparison {
                section(title: String(localized: "vs Previous Week", comment: "Section header for comparison with previous week")) {
                    comparisonCard
                }
            }
        }
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xl)
    }

    // MARK: - Section helper (no numbers, just hairline + uppercase title)

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardEyebrow(title: title)
            content()
        }
        .padding(.horizontal)
    }

    // MARK: - Week header (editorial)

    private var weekHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(spacing: Spacing.xs) {
                Text(weekEyebrowLabel)
                    .font(IRFont.monoSM)
                    .tracking(IRTracking.eyebrow)
                    .foregroundStyle(Color.irTextTertiary)

                Spacer()
            }

            Text(weekRangeShort)
                .font(IRFont.numMD)
                .kerning(-0.6)
                .foregroundStyle(Color.irTextPrimary)
        }
    }

    private var weekEyebrowLabel: String {
        let week = Calendar.current.component(.weekOfYear, from: viewModel.weekEnd)
        let prefix = String(localized: "Week", comment: "Week prefix in weekly recap header")
        let inProgress = String(localized: "in progress", comment: "Indicates the current week is ongoing")
        return "\(prefix.uppercased()) \(week) · \(inProgress.uppercased())"
    }

    private var weekRangeShort: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "d MMM"
        return "\(formatter.string(from: viewModel.weekStart)) — \(formatter.string(from: viewModel.weekEnd))"
    }

    // MARK: - Recovery hero (with inline coach insight)

    private var recoveryHeroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(String(localized: "AVG SCORE", comment: "Eyebrow above weekly average recovery score").uppercased())
                        .font(IRFont.monoSM)
                        .tracking(IRTracking.eyebrow)
                        .foregroundStyle(Color.irTextTertiary)

                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(viewModel.averageRecoveryScore)")
                            .font(IRFont.numeric(size: 72, weight: .heavy))
                            .kerning(-2.8)
                            .foregroundStyle(Color.irTextPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)

                        Text("/100")
                            .font(IRFont.numSM.weight(.semibold))
                            .foregroundStyle(Color.irTextTertiary)
                    }

                    if let recDelta = viewModel.recoveryScoreChange {
                        let isUp = recDelta >= 0
                        HStack(spacing: 4) {
                            Image(systemName: isUp ? "arrow.up" : "arrow.down")
                                .font(.system(size: 9, weight: .heavy))
                            Text(deltaPointsLabel(recDelta))
                                .font(IRFont.monoSM.weight(.bold))
                        }
                        .foregroundStyle(isUp ? Color.irSuccess : Color.irWarning)
                    }
                }

                Spacer()

                RecoveryRing(score: viewModel.averageRecoveryScore)
                    .frame(width: 88, height: 88)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.irPrimaryAccent.opacity(0.06),
                    Color.irCardBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Coach card (LLM-driven, mirrors Dashboard PulseCoachingCard)

    @ViewBuilder
    private var weeklyCoachCard: some View {
        if !viewModel.coachingTLDR.isEmpty {
            PulseCoachingCard(
                timestampLabel: coachTimestampLabel,
                tldr: viewModel.coachingTLDR,
                highlightWord: viewModel.coachingHighlight,
                reasons: viewModel.coachingReasons,
                detail: viewModel.coachingDetail
            )
        } else {
            coachLoadingCard
        }
    }

    private var coachLoadingCard: some View {
        HStack(spacing: Spacing.md) {
            ProgressView().scaleEffect(0.85)
            Text(String(localized: "Coach is reading your week...", comment: "Coach card loading placeholder"))
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
            Spacer()
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var coachTimestampLabel: String {
        let date = viewModel.coachingTimestamp ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Running card

    private var runningCard: some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            HStack {
                Text(runDaysLabel)
                    .font(IRFont.monoSM)
                    .tracking(IRTracking.eyebrow)
                    .foregroundStyle(Color.irTextTertiary)

                Spacer()

                statusChip
            }

            HStack(alignment: .top, spacing: 0) {
                runKPI(
                    label: String(localized: "Distance", comment: "Weekly distance label"),
                    value: viewModel.runCount > 0 ? String(format: "%.1f", viewModel.totalDistance / 1000.0) : "0.0",
                    unit: String(localized: "km", comment: "Unit abbreviation for kilometers"),
                    muted: viewModel.runCount == 0,
                    leadingDivider: false
                )
                runKPI(
                    label: String(localized: "Time", comment: "Weekly time label"),
                    value: runDurationValue,
                    unit: runDurationUnit,
                    muted: viewModel.runCount == 0,
                    leadingDivider: true
                )
                runKPI(
                    label: String(localized: "Pace", comment: "Weekly pace label"),
                    value: viewModel.runCount > 0 ? viewModel.formattedAveragePace : "—",
                    unit: "",
                    muted: viewModel.runCount == 0,
                    leadingDivider: true
                )
            }

            DailyStepperBar(
                dailyKm: viewModel.dailyRunDistancesKm,
                todayIndex: viewModel.todayIndexInWeek,
                firstWeekday: Calendar.current.firstWeekday
            )
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var runDaysLabel: String {
        let active = viewModel.dailyRunDistancesKm.filter { $0 > 0 }.count
        let days = String(localized: "days", comment: "Days suffix in weekly recap")
        return "\(active) / 7 \(days.uppercased())"
    }

    @ViewBuilder
    private var statusChip: some View {
        if viewModel.runCount == 0 {
            chip(
                text: String(localized: "No runs", comment: "Status chip when no runs in the week"),
                color: .irError
            )
        } else if let change = viewModel.distanceChange, change >= 10 {
            chip(
                text: String(localized: "Solid week", comment: "Status chip for a strong training week"),
                color: .irSuccess
            )
        } else if let change = viewModel.distanceChange, change <= -25 {
            chip(
                text: String(localized: "Lighter week", comment: "Status chip for reduced training volume"),
                color: .irWarning
            )
        } else {
            chip(
                text: String(localized: "On track", comment: "Default status chip when training is on plan"),
                color: .irPrimaryAccent
            )
        }
    }

    private func chip(text: String, color: Color) -> some View {
        Text(text)
            .font(IRFont.eyebrow.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: 0.5))
    }

    private var runDurationValue: String {
        guard viewModel.runCount > 0 else { return "0" }
        let minutes = Int(viewModel.totalDuration) / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            return "\(hours)h\(String(format: "%02d", mins))"
        }
        return "\(minutes)"
    }

    private var runDurationUnit: String {
        guard viewModel.runCount > 0 else { return String(localized: "min", comment: "Unit abbreviation for minutes") }
        let minutes = Int(viewModel.totalDuration) / 60
        return minutes >= 60 ? "" : String(localized: "min", comment: "Unit abbreviation for minutes")
    }

    private func runKPI(label: String, value: String, unit: String, muted: Bool, leadingDivider: Bool) -> some View {
        HStack(spacing: 0) {
            if leadingDivider {
                Rectangle()
                    .fill(Color.irBorder)
                    .frame(width: 0.5)
                    .padding(.trailing, Spacing.md)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(IRFont.numeric(size: 24, weight: .bold))
                        .kerning(-0.5)
                        .foregroundStyle(muted ? Color.irTextTertiary : Color.irTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(IRFont.monoSM.weight(.semibold))
                            .foregroundStyle(Color.irTextTertiary)
                    }
                }
                Text(label.uppercased())
                    .font(IRFont.microLabel.weight(.bold))
                    .tracking(IRTracking.microLabel)
                    .foregroundStyle(Color.irTextTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Sleep card

    private var sleepCard: some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "AVG DURATION", comment: "Eyebrow above weekly average sleep duration").uppercased())
                        .font(IRFont.monoSM)
                        .tracking(IRTracking.eyebrow)
                        .foregroundStyle(Color.irTextTertiary)

                    sleepDurationDisplay
                }

                Spacer()

                HStack(spacing: Spacing.lg) {
                    sleepKpi(
                        value: String(format: "%.0f", viewModel.averageSleepEfficiency),
                        suffix: "%",
                        label: String(localized: "Efficiency", comment: "Average sleep efficiency label")
                    )
                    sleepKpi(
                        value: "\(viewModel.averageQualityScore)",
                        suffix: "",
                        label: String(localized: "Quality", comment: "Average sleep quality label")
                    )
                }
            }

            if hasSleepStages {
                sleepStagesStack
            }
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var sleepDurationDisplay: some View {
        let total = Int(viewModel.averageSleepDuration)
        let hours = total / 3600
        let minutes = total / 60 % 60
        return HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text("\(hours)")
                .font(IRFont.numeric(size: 44, weight: .heavy))
                .kerning(-1.3)
                .foregroundStyle(Color.irTextPrimary)
            Text("h")
                .font(IRFont.numeric(size: 22, weight: .semibold))
                .foregroundStyle(Color.irTextSecondary)
            Text(String(format: "%02d", minutes))
                .font(IRFont.numeric(size: 44, weight: .heavy))
                .kerning(-1.3)
                .foregroundStyle(Color.irTextPrimary)
        }
    }

    private func sleepKpi(value: String, suffix: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text(value)
                    .font(IRFont.numeric(size: 18, weight: .bold))
                    .foregroundStyle(Color.irTextPrimary)
                if !suffix.isEmpty {
                    Text(suffix)
                        .font(IRFont.monoSM)
                        .foregroundStyle(Color.irTextTertiary)
                }
            }
            Text(label.uppercased())
                .font(IRFont.microLabel.weight(.bold))
                .tracking(IRTracking.microLabel)
                .foregroundStyle(Color.irTextTertiary)
        }
    }

    private var hasSleepStages: Bool {
        viewModel.averageDeepPercent > 0 || viewModel.averageCorePercent > 0 || viewModel.averageRemPercent > 0
    }

    private var sleepStagesStack: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            GeometryReader { geo in
                let total = max(0.001, viewModel.averageDeepPercent + viewModel.averageCorePercent + viewModel.averageRemPercent)
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.irPrimaryAccent.opacity(0.9))
                        .frame(width: max(0, geo.size.width * viewModel.averageDeepPercent / total))
                    Rectangle()
                        .fill(Color.irPrimaryAccent.opacity(0.5))
                        .frame(width: max(0, geo.size.width * viewModel.averageCorePercent / total))
                    Rectangle()
                        .fill(Color.irPurple)
                        .frame(width: max(0, geo.size.width * viewModel.averageRemPercent / total))
                }
            }
            .frame(height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: Spacing.md) {
                stageLegend(
                    color: Color.irPrimaryAccent.opacity(0.9),
                    label: String(localized: "Deep", comment: "Deep sleep stage legend"),
                    percent: viewModel.averageDeepPercent
                )
                stageLegend(
                    color: Color.irPrimaryAccent.opacity(0.5),
                    label: String(localized: "Light", comment: "Light/Core sleep stage legend"),
                    percent: viewModel.averageCorePercent
                )
                stageLegend(
                    color: Color.irPurple,
                    label: String(localized: "REM", comment: "REM sleep stage legend"),
                    percent: viewModel.averageRemPercent
                )
                Spacer(minLength: 0)
            }
        }
    }

    private func stageLegend(color: Color, label: String, percent: Double) -> some View {
        HStack(spacing: Spacing.xs) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(IRFont.eyebrow)
                .foregroundStyle(Color.irTextSecondary)
            Text("\(Int(percent.rounded()))%")
                .font(IRFont.monoSM.weight(.semibold))
                .foregroundStyle(Color.irTextPrimary)
        }
    }

    // MARK: - Biometrics 2x2 grid

    private var hasAnyBiometric: Bool {
        viewModel.averageHRV != nil || viewModel.averageRestingHR != nil
            || viewModel.averageSpO2 != nil || viewModel.averageRespRate != nil
    }

    private var biometricsGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm)
            ],
            spacing: Spacing.sm
        ) {
            if let hrv = viewModel.averageHRV {
                BioTile(
                    icon: "waveform.path.ecg",
                    label: String(localized: "HRV", comment: "Heart rate variability label"),
                    value: String(format: "%.0f", hrv),
                    unit: String(localized: "ms", comment: "Unit abbreviation for milliseconds"),
                    delta: viewModel.hrvDelta,
                    deltaFormat: "%+.0f",
                    higherIsBetter: true,
                    color: .irPrimaryAccent,
                    spark: viewModel.dailyHRV
                )
            }
            if let rhr = viewModel.averageRestingHR {
                BioTile(
                    icon: "heart.fill",
                    label: String(localized: "Resting HR", comment: "Resting heart rate label"),
                    value: String(format: "%.0f", rhr),
                    unit: String(localized: "bpm", comment: "Unit abbreviation for beats per minute"),
                    delta: viewModel.restingHRDelta,
                    deltaFormat: "%+.0f",
                    higherIsBetter: false,
                    color: .irError,
                    spark: viewModel.dailyRestingHR
                )
            }
            if let spo2 = viewModel.averageSpO2 {
                BioTile(
                    icon: "drop.fill",
                    label: String(localized: "SpO2", comment: "Blood oxygen saturation label"),
                    value: String(format: "%.1f", spo2),
                    unit: "%",
                    delta: viewModel.spo2Delta,
                    deltaFormat: "%+.1f",
                    higherIsBetter: true,
                    color: Color(red: 0.357, green: 0.765, blue: 1.0),
                    spark: viewModel.dailySpO2
                )
            }
            if let resp = viewModel.averageRespRate {
                BioTile(
                    icon: "lungs.fill",
                    label: String(localized: "Resp.", comment: "Respiratory rate short label"),
                    value: String(format: "%.1f", resp),
                    unit: String(localized: "rpm", comment: "Respirations per minute unit"),
                    delta: viewModel.respRateDelta,
                    deltaFormat: "%+.1f",
                    higherIsBetter: false,
                    color: .irPurple,
                    spark: viewModel.dailyRespRate
                )
            }
        }
    }

    // MARK: - Comparison vs previous week

    private var hasAnyComparison: Bool {
        viewModel.distanceChange != nil
            || viewModel.durationChange != nil
            || viewModel.recoveryScoreChange != nil
            || viewModel.sleepDurationChange != nil
            || viewModel.hrvDelta != nil
    }

    private var comparisonCard: some View {
        VStack(spacing: 0) {
            ForEach(comparisonRows.indices, id: \.self) { idx in
                let row = comparisonRows[idx]
                if idx > 0 {
                    Rectangle().fill(Color.irBorder).frame(height: 0.5)
                }
                comparisonRow(row)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private struct ComparisonRow {
        let label: String
        let current: String
        let previous: String
        let delta: String
        let isNegative: Bool
    }

    private var comparisonRows: [ComparisonRow] {
        var rows: [ComparisonRow] = []

        if viewModel.distanceChange != nil || viewModel.prevTotalDistance > 0 {
            let cur = String(format: "%.1f km", viewModel.totalDistance / 1000.0)
            let prev = String(format: "%.1f km", viewModel.prevTotalDistance / 1000.0)
            let change = viewModel.distanceChange ?? 0
            let neg = change < 0
            rows.append(ComparisonRow(
                label: String(localized: "Distance", comment: "Distance comparison row label"),
                current: cur, previous: prev,
                delta: String(format: "%+.0f%%", change),
                isNegative: neg
            ))
        }

        if viewModel.durationChange != nil || viewModel.prevTotalDuration > 0 {
            let cur = formatDuration(viewModel.totalDuration)
            let prev = formatDuration(viewModel.prevTotalDuration)
            let change = viewModel.durationChange ?? 0
            rows.append(ComparisonRow(
                label: String(localized: "Duration", comment: "Duration comparison row label"),
                current: cur, previous: prev,
                delta: String(format: "%+.0f%%", change),
                isNegative: change < 0
            ))
        }

        if let recDelta = viewModel.recoveryScoreChange {
            rows.append(ComparisonRow(
                label: String(localized: "Recovery score", comment: "Recovery score comparison row label"),
                current: "\(viewModel.averageRecoveryScore)",
                previous: "\(viewModel.prevAverageRecoveryScore)",
                delta: deltaPointsLabel(recDelta),
                isNegative: recDelta < 0
            ))
        }

        if viewModel.sleepDurationChange != nil || viewModel.prevAverageSleepDuration > 0 {
            let cur = formatSleepShort(viewModel.averageSleepDuration)
            let prev = formatSleepShort(viewModel.prevAverageSleepDuration)
            let secondsDelta = viewModel.sleepDurationChange ?? 0
            let minutesDelta = Int(secondsDelta / 60)
            let mins = String(localized: "min", comment: "Unit abbreviation for minutes")
            rows.append(ComparisonRow(
                label: String(localized: "Sleep", comment: "Sleep duration comparison row label"),
                current: cur, previous: prev,
                delta: String(format: "%+d %@", minutesDelta, mins),
                isNegative: minutesDelta < 0
            ))
        }

        if let hrvDelta = viewModel.hrvDelta, let avg = viewModel.averageHRV {
            let cur = String(format: "%.0f ms", avg)
            let prev = String(format: "%.0f ms", viewModel.prevAverageHRV ?? 0)
            rows.append(ComparisonRow(
                label: String(localized: "Average HRV", comment: "Average HRV comparison row label"),
                current: cur, previous: prev,
                delta: String(format: "%+.0f ms", hrvDelta),
                isNegative: hrvDelta < 0
            ))
        }

        return rows
    }

    private func comparisonRow(_ row: ComparisonRow) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(row.label)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)

            Spacer(minLength: Spacing.xs)

            Text(row.previous)
                .font(IRFont.monoSM)
                .foregroundStyle(Color.irTextTertiary)
                .strikethrough(true, color: Color.irTextTertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(row.current)
                .font(IRFont.numXS.weight(.semibold))
                .foregroundStyle(Color.irTextPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(row.delta)
                .font(IRFont.monoSM.weight(.bold))
                .foregroundStyle(row.isNegative ? Color.irError : Color.irSuccess)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill((row.isNegative ? Color.irError : Color.irSuccess).opacity(0.14))
                )
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, Spacing.base - 2)
    }

    // MARK: - Helpers

    private func deltaPointsLabel(_ delta: Int) -> String {
        let pts = String(localized: "pts", comment: "Unit abbreviation for points")
        let sign = delta >= 0 ? "+" : "−"
        return "\(sign)\(abs(delta)) \(pts)"
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return "\(h)h \(String(format: "%02d", m))"
        }
        let mins = String(localized: "min", comment: "Unit abbreviation for minutes")
        return "\(minutes) \(mins)"
    }

    private func formatSleepShort(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = total / 60 % 60
        return "\(h)h \(String(format: "%02d", m))"
    }
}

// MARK: - Recovery semi-ring

private struct RecoveryRing: View {
    let score: Int

    var body: some View {
        let progress = max(0, min(1, Double(score) / 100.0))
        ZStack {
            Circle()
                .stroke(Color.irTextPrimary.opacity(0.06), lineWidth: 6)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.irPrimaryAccent,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 1) {
                Text(String(localized: "RECOV", comment: "Recovery ring inner eyebrow").uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(IRTracking.microLabel)
                    .foregroundStyle(Color.irTextTertiary)
                Text(ringLabel)
                    .font(IRFont.monoSM.weight(.bold))
                    .foregroundStyle(Color.irPrimaryAccent)
            }
        }
    }

    private var ringLabel: String {
        switch score {
        case 75...:
            return String(localized: "GOOD", comment: "Recovery ring label: good").uppercased()
        case 55..<75:
            return String(localized: "FAIR", comment: "Recovery ring label: fair").uppercased()
        case 1..<55:
            return String(localized: "LOW", comment: "Recovery ring label: low").uppercased()
        default:
            return String(localized: "—", comment: "Recovery ring label: no data")
        }
    }
}

// MARK: - Bio tile (with sparkline)

private struct BioTile: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let delta: Double?
    let deltaFormat: String
    let higherIsBetter: Bool
    let color: Color
    let spark: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.opacity(0.18))
                    )

                Text(label.uppercased())
                    .font(IRFont.microLabel.weight(.bold))
                    .tracking(IRTracking.microLabel)
                    .foregroundStyle(Color.irTextTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)

                if let delta = delta {
                    Text(String(format: deltaFormat, delta))
                        .font(IRFont.monoSM.weight(.bold))
                        .foregroundStyle(deltaColor)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(IRFont.numeric(size: 26, weight: .bold))
                    .kerning(-0.5)
                    .foregroundStyle(Color.irTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(unit)
                    .font(IRFont.monoSM.weight(.semibold))
                    .foregroundStyle(Color.irTextTertiary)
            }

            if spark.count > 1 {
                MicroSparkline(values: spark, color: color)
                    .frame(height: 24)
                    .padding(.horizontal, -4)
                    .padding(.bottom, -4)
            } else {
                Color.clear.frame(height: 24)
            }
        }
        .padding(Spacing.base - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var deltaColor: Color {
        guard let delta = delta else { return .irTextTertiary }
        if abs(delta) < 0.05 { return .irTextSecondary }
        let positive = delta > 0
        let good = positive == higherIsBetter
        return good ? .irSuccess : .irWarning
    }
}

// MARK: - 7-day stepper bar

private struct DailyStepperBar: View {
    let dailyKm: [Double]
    let todayIndex: Int
    let firstWeekday: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { idx in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: idx))
                        .frame(height: 4)

                    Text(weekdayLetter(for: idx))
                        .font(IRFont.monoSM.weight(idx == todayIndex ? .heavy : .medium))
                        .foregroundStyle(idx == todayIndex ? Color.irPrimaryAccent : Color.irTextTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func barColor(for idx: Int) -> Color {
        let value = idx < dailyKm.count ? dailyKm[idx] : 0
        if value > 0 {
            return Color.irPrimaryAccent
        }
        if idx == todayIndex {
            return Color.irTextPrimary.opacity(0.20)
        }
        return Color.irTextPrimary.opacity(0.06)
    }

    /// Returns a single-letter weekday label honouring `firstWeekday` and the current locale.
    private func weekdayLetter(for idx: Int) -> String {
        let calendar = Calendar.current
        // veryShortStandaloneWeekdaySymbols is indexed Sunday=0 in iOS regardless of firstWeekday.
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let weekdayNumber = ((firstWeekday - 1 + idx) % 7) + 1 // 1..7 (1=Sunday)
        let symbolIdx = (weekdayNumber - 1) % symbols.count
        return symbols[symbolIdx].uppercased()
    }
}

#Preview {
    NavigationStack {
        WeeklySummaryView()
    }
    .preferredColorScheme(.dark)
}
