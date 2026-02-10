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
                VStack(alignment: .leading, spacing: 24) {
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
                            .font(.title3)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
            }
            .onAppear {
                AnalyticsService.shared.trackMedicalSourcesViewed()
            }
        }
    }

    // MARK: - Disclaimer Section

    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange.gradient)

                Text(String(localized: "Medical Disclaimer", comment: "Medical disclaimer section title"))
                    .font(.headline)
                    .foregroundStyle(Color.irTextPrimary)
            }

            Text(MedicalSourcesDatabase.disclaimer)
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)
                .lineSpacing(4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.orange.opacity(0.1))
        )
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Filter by Category", comment: "Category picker label"))
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
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
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .white : Color.irTextPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isSelected ? AnyShapeStyle(Color.irPrimaryAccent.gradient) : AnyShapeStyle(Color.irSurface))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sources Section

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(format: String(localized: "%d Scientific Sources", comment: "Number of sources label"), MedicalSourcesDatabase.sources(for: selectedCategory).count))
                .font(.headline)
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
        VStack(alignment: .leading, spacing: 12) {
            // Year badge + Journal
            HStack(spacing: 8) {
                Text("\(source.year)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.blue.gradient)
                    )

                Text(source.journal)
                    .font(.caption)
                    .foregroundStyle(Color.irTextSecondary)
                    .lineLimit(1)

                Spacer()
            }

            // Title
            Text(source.title)
                .font(.headline)
                .foregroundStyle(Color.irTextPrimary)
                .lineSpacing(2)

            // Authors
            Text(source.authors)
                .font(.subheadline)
                .foregroundStyle(Color.irTextSecondary)
                .italic()

            Divider()
                .padding(.vertical, 4)

            // Summary
            Text(source.summary)
                .font(.subheadline)
                .foregroundStyle(Color.irTextPrimary)
                .lineSpacing(4)

            // Link button
            if let urlString = source.url,
               let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack {
                        Image(systemName: "link")
                            .font(.subheadline)
                        Text(String(localized: "View Source", comment: "Button to view source link"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(Color.irPrimaryAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.irPrimaryAccent.opacity(0.1))
                    )
                }
            }

            // Citation
            Text(source.citation)
                .font(.caption2)
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.irCardBackground)
                .shadow(color: Color.irShadow, radius: 8, y: 2)
        )
    }
}

#Preview {
    MedicalSourcesView()
}
