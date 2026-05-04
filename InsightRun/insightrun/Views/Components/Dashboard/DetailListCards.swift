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
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private func rowView(_ row: DetailComponentRow) -> some View {
        HStack {
            Text(row.label)
                .font(IRFont.footnote)
                .foregroundStyle(Color.irTextPrimary)

            Spacer()

            HStack(alignment: .lastTextBaseline, spacing: Spacing.xxs) {
                Text(row.value)
                    .font(IRFont.bodyEmphasized.weight(.bold))
                    .foregroundStyle(Color.irTextPrimary)

                if let unit = row.unit {
                    Text(unit)
                        .font(IRFont.eyebrow)
                        .foregroundStyle(Color.irTextSecondary)
                }

                if let target = row.target {
                    Text("/ \(target)")
                        .font(IRFont.monoSM)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                        .padding(.leading, 2)
                }
            }
        }
        .padding(.horizontal, Spacing.cardPadding)
        .padding(.vertical, Spacing.dash)
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
        VStack(alignment: .leading, spacing: Spacing.dash) {
            stackedBar
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(spacing: Spacing.md) {
                ForEach(slices) { slice in
                    HStack {
                        HStack(spacing: Spacing.sm) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(slice.color)
                                .frame(width: 8, height: 8)

                            Text(slice.label)
                                .font(IRFont.footnote)
                                .foregroundStyle(Color.irTextPrimary)
                        }

                        Spacer()

                        Text("\(Int(slice.weight))%")
                            .font(IRFont.footnote.weight(.bold))
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }

            if !explanation.isEmpty {
                Divider().background(Color.irBorder)

                Text(explanation)
                    .font(IRFont.caption)
                    .lineSpacing(2)
                    .foregroundStyle(Color.irTextSecondary)
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

                HStack(alignment: .top, spacing: Spacing.xs) {
                    Text("[\(index + 1)]")
                        .font(IRFont.monoSM)
                        .foregroundStyle(Color.irTextSecondary.opacity(0.55))

                    Text(source)
                        .font(IRFont.monoSM)
                        .lineSpacing(2)
                        .foregroundStyle(Color.irTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Spacing.cardPadding)
                .padding(.vertical, Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }
}

#Preview {
    ScrollView {
        VStack(spacing: Spacing.dash) {
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
