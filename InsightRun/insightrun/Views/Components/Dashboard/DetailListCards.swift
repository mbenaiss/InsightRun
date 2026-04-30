//
//  DetailListCards.swift
//  InsightRun
//
//  Three list-style cards used in the metric detail sheet:
//   · DetailComponentsCard — "Composantes du jour" (label/value/target rows)
//   · DetailFormulaCard    — "Comment c'est calculé" (stacked weights bar + legend + explanation)
//   · DetailReferencesCard — "Références scientifiques" (numbered mono list)
//

import SwiftUI

// MARK: - Components

struct DetailComponentRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var unit: String?
    var target: String?
}

struct DetailComponentsCard: View {
    let title: String
    let rows: [DetailComponentRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().background(Color.irBorder)
                }
                rowView(row)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private func rowView(_ row: DetailComponentRow) -> some View {
        HStack {
            Text(row.label)
                .font(.system(size: 13))
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(row.value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.irTextPrimary)

                if let unit = row.unit {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.irTextSecondary)
                }

                if let target = row.target {
                    Text("/ \(target)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                        .padding(.leading, 2)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

// MARK: - Formula

struct DetailFormulaSlice: Identifiable {
    let id = UUID()
    let label: String
    let weight: Double
    let color: Color
}

struct DetailFormulaCard: View {
    let slices: [DetailFormulaSlice]
    let explanation: String

    private var totalWeight: Double {
        max(0.0001, slices.reduce(0) { $0 + $1.weight })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            stackedBar
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(spacing: 10) {
                ForEach(slices) { slice in
                    HStack {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(slice.color)
                                .frame(width: 8, height: 8)

                            Text(slice.label)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.irTextPrimary)
                        }

                        Spacer()

                        Text("\(Int(slice.weight))%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }

            if !explanation.isEmpty {
                Divider().background(Color.irBorder)

                Text(explanation)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(Color.irTextSecondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(slices) { slice in
                    let width = CGFloat(slice.weight / totalWeight) * geo.size.width
                    Rectangle()
                        .fill(slice.color)
                        .frame(width: width)
                }
            }
        }
    }
}

// MARK: - References

struct DetailReferencesCard: View {
    let sources: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                if index > 0 {
                    Divider().background(Color.irBorder)
                }

                HStack(alignment: .top, spacing: 6) {
                    Text("[\(index + 1)]")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.irTextSecondary.opacity(0.55))

                    Text(source)
                        .font(.system(size: 12, design: .monospaced))
                        .lineSpacing(2)
                        .foregroundStyle(Color.irTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Analysis (coach card with sparkle glyph)

struct DetailAnalysisCard: View {
    let text: String
    var isLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            LinearGradient(
                                colors: [Color.irAIAccent, Color.irAIAccentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.black)
                }
                .frame(width: 22, height: 22)

                Text(String(localized: "Coach", comment: "Detail sheet AI analysis label"))
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()
            }

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else if !text.isEmpty {
                Text(text)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(Color.irTextPrimary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 14) {
            DetailComponentsCard(title: "Composantes", rows: [
                DetailComponentRow(label: "Pas", value: "3 752", unit: nil, target: "10 000"),
                DetailComponentRow(label: "Calories actives", value: "177", unit: "kcal", target: "400"),
                DetailComponentRow(label: "Minutes d'exercice", value: "15", unit: "min", target: "30"),
            ])

            DetailFormulaCard(
                slices: [
                    DetailFormulaSlice(label: "Pas", weight: 30, color: .irSuccess),
                    DetailFormulaSlice(label: "Calories actives", weight: 35, color: .irWarning),
                    DetailFormulaSlice(label: "Minutes d'exercice", weight: 35, color: .irError),
                ],
                explanation: "Score quotidien mesurant ta progression vers tes objectifs personnels."
            )

            DetailAnalysisCard(text: "Score 39% : tu es en dessous de tes objectifs sur les pas, calories et minutes d'exercice.")

            DetailReferencesCard(sources: [
                "Tudor-Locke C, Bassett DR · Sports Medicine 2004",
                "Ainsworth BE et coll. · Compendium MSSE 2011",
            ])
        }
        .padding()
    }
    .background(Color.irBackgroundApp)
    .preferredColorScheme(.dark)
}
