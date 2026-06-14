//
//  MedicalSourcesView.swift
//  InsightRun
//
//  View displaying medical sources and references for health metrics
//

import SwiftUI

struct MedicalSourcesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: MedicalSourceCategory = .general

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // Disclaimer Section
                    disclaimerSection

                    // Category Picker
                    categoryPicker

                    // Sources for selected category
                    sourcesSection
                }
                .padding()
            }
            .background(Color.irBackgroundApp)
            .navigationTitle(String(localized: "Medical Sources", comment: "Medical sources view title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(IRFont.title3)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                    .accessibilityLabel(String(localized: "Close", comment: "Close button"))
                }
            }
            .onAppear {
                AnalyticsService.shared.trackMedicalSourcesViewed()
            }
        }
    }

    // MARK: - Disclaimer Section

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(IRFont.title2)
                    .foregroundStyle(Color.irWarning.gradient)

                Text(String(localized: "Medical Disclaimer", comment: "Medical disclaimer section title"))
                    .font(IRFont.headline)
                    .foregroundStyle(Color.irTextPrimary)
            }

            Text(MedicalSourcesDatabase.disclaimer)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
                .lineSpacing(4)
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.irWarning.opacity(0.1))
        )
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(String(localized: "Filter by Category", comment: "Category picker label"))
                .font(IRFont.headline)
                .foregroundStyle(Color.irTextPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(MedicalSourceCategory.allCases) { category in
                        categoryButton(for: category)
                    }
                }
            }
        }
    }

    // Helper function to avoid type-checking issues
    private func categoryButton(for category: MedicalSourceCategory) -> some View {
        let isSelected = selectedCategory == category

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = category
            }
        } label: {
            Text(category.localizedTitle)
                .font(IRFont.body)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.irTextOnAccent : Color.irTextPrimary)
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(isSelected ? AnyShapeStyle(Color.irPrimaryAccent.gradient) : AnyShapeStyle(Color.irCard2))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sources Section

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.base) {
            Text(String(format: String(localized: "%d Scientific Sources", comment: "Number of sources label"), MedicalSourcesDatabase.sources(for: selectedCategory).count))
                .font(IRFont.headline)
                .foregroundStyle(Color.irTextPrimary)

            ForEach(MedicalSourcesDatabase.sources(for: selectedCategory)) { source in
                SourceCard(source: source)
            }
        }
    }
}

// MARK: - Source Card Component

struct SourceCard: View {
    let source: MedicalSource

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Year badge + Journal
            HStack(spacing: Spacing.sm) {
                Text("\(source.year)")
                    .font(IRFont.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.irTextOnAccent)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.xs)
                            .fill(Color.irPrimaryAccent.gradient)
                    )

                Text(source.journal)
                    .font(IRFont.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineLimit(1)

                Spacer()
            }

            // Title
            Text(source.title)
                .font(IRFont.headline)
                .foregroundStyle(Color.irTextPrimary)
                .lineSpacing(2)

            // Authors
            Text(source.authors)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextSecondary)
                .italic()

            Divider()
                .padding(.vertical, Spacing.xxs)

            // Summary
            Text(source.summary)
                .font(IRFont.body)
                .foregroundStyle(Color.irTextPrimary)
                .lineSpacing(4)

            // Link button
            if let urlString = source.url,
               let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "link")
                            .font(IRFont.body)
                        Text(String(localized: "View Source", comment: "Button to view source link"))
                            .font(IRFont.body)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.irPrimaryAccent)
                    .padding(.horizontal, Spacing.base)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.xs)
                            .fill(Color.irPrimaryAccent.opacity(0.1))
                    )
                }
            }

            // Citation
            Text(source.citation)
                .font(IRFont.microLabel)
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                .padding(.top, Spacing.xxs)
        }
        .padding(Spacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .detailCard()
    }
}

#Preview {
    MedicalSourcesView()
}
