//
//  CardiacLoadCard.swift
//  InsightRun
//
//  Garmin-style cardiac load card with score, status, and mini area chart
//

import SwiftUI
import Charts

struct CardiacLoadCard: View {
    let score: Int
    let status: CardiacLoadStatus
    let trendData: [TrendDataPoint]
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "shoe.2.fill")
                            .font(.subheadline)
                            .foregroundStyle(status.color.opacity(0.8))

                        Text(String(localized: "Cardiac Load", comment: "Cardiac load card title"))
                            .font(.subheadline)
                            .foregroundStyle(Color.irTextSecondary)
                    }

                    Text("\(score)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.irTextPrimary)

                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: status.icon)
                            .font(.caption)
                            .foregroundStyle(status.color)

                        Text(status.title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(status.color)
                    }
                }

                Spacer()

                if !trendData.isEmpty {
                    MiniTrendChart(data: trendData, accentColor: status.color)
                        .frame(width: 120, height: 50)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextSecondary.opacity(0.4))
            }
            .padding(Spacing.base)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .shadow(color: Color.irShadow, radius: 10, y: 5)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let sampleData = (0..<14).map { day in
        TrendDataPoint(
            date: Calendar.current.date(byAdding: .day, value: -13 + day, to: Date())!,
            value: Double.random(in: 20...80)
        )
    }

    return VStack(spacing: 16) {
        CardiacLoadCard(score: 38, status: .maintaining, trendData: sampleData)
        CardiacLoadCard(score: 72, status: .increasing, trendData: sampleData)
        CardiacLoadCard(score: 15, status: .decreasing, trendData: sampleData)
    }
    .padding()
    .background(Color.irBackgroundApp)
}
