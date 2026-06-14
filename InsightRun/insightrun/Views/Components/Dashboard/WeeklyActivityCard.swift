//
//  WeeklyActivityCard.swift
//  InsightRun
//
//  Weekly activity card: 3 stat columns + 7-day effort bar chart.
//

import SwiftUI

struct WeeklyActivityCard: View {
    let weekLabel: String
    let totalDistanceLabel: String
    let totalDurationLabel: String
    let averagePaceLabel: String
    let dailyEfforts: [Double]
    let highlightedIndex: Int
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text(weekLabel)
                        .font(IRFont.caption)
                        .foregroundStyle(Color.irTextSecondary)

                    Spacer()

                    Text(totalDistanceLabel)
                        .font(IRFont.monoSM)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                }

                HStack(spacing: 0) {
                    statColumn(label: String(localized: "Distance", comment: "Weekly distance label"), value: totalDistanceLabel)
                    statColumn(label: String(localized: "Time", comment: "Weekly time label"), value: totalDurationLabel)
                    statColumn(label: String(localized: "Pace", comment: "Weekly pace label"), value: averagePaceLabel)
                }

                BarChartRow(values: dailyEfforts, highlighted: highlightedIndex)
                    .frame(height: 32)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .detailCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("weekly-summary-link")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(weekLabel), \(totalDistanceLabel), \(totalDurationLabel), \(averagePaceLabel)")
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(IRFont.title3.weight(.bold))
                .foregroundStyle(Color.irTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(IRFont.microLabel)
                .foregroundStyle(Color.irTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Bar chart row

struct BarChartRow: View {
    let values: [Double]
    let highlighted: Int

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let count = max(1, values.count)
            let gap: CGFloat = 4
            let totalGap = gap * CGFloat(count - 1)
            let barWidth = max(2, (width - totalGap) / CGFloat(count))
            let maxValue = max(0.0001, values.max() ?? 1)

            HStack(alignment: .bottom, spacing: gap) {
                ForEach(Array(values.enumerated()), id: \.offset) { idx, v in
                    let h = max(2, CGFloat(v / maxValue) * height)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(idx == highlighted ? Color.irPrimaryAccent : Color.irBorderStrong)
                        .frame(width: barWidth, height: h)
                }
            }
            .frame(width: width, height: height, alignment: .bottom)
        }
    }
}

#Preview {
    WeeklyActivityCard(
        weekLabel: "Sem 18 · 4/7 jours",
        totalDistanceLabel: "8.5 km",
        totalDurationLabel: "56m",
        averagePaceLabel: "6'38\"",
        dailyEfforts: [5, 8, 3, 12, 6, 9, 4],
        highlightedIndex: 6
    )
    .padding()
    .background(Color.irBackgroundApp)
    .preferredColorScheme(.dark)
}
