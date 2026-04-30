//
//  OnboardingComponents.swift
//  InsightRun
//
//  Shared Pulse-Ring building blocks for the onboarding flow:
//  scaffold (header + scroll + CTA pair), feature card, primary/secondary buttons.
//
//  Each step composes these instead of redefining its own visual language so the
//  flow matches the rest of the app (irBackgroundApp, 34pt heavy titles, eyebrow
//  tracking 1.4, 0.5px border cards on irCardBackground, lime CTAs).
//

import SwiftUI

// MARK: - Editorial header (eyebrow + 34pt heavy title + body)

struct OnboardingEditorialHeader: View {
    let eyebrow: String
    let title: String
    let bodyText: String?

    init(eyebrow: String, title: String, body: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.bodyText = body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.irTextSecondary.opacity(0.7))

            Text(title)
                .font(.system(size: 34, weight: .heavy))
                .kerning(-1)
                .foregroundStyle(Color.irTextPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let bodyText, !bodyText.isEmpty {
                Text(bodyText)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.irTextSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Feature card row (Pulse-Ring style)

struct OnboardingFeatureCard: View {
    let icon: String
    let iconTint: Color
    let title: String
    let description: String
    let trailing: TrailingDecoration

    enum TrailingDecoration {
        case none
        case checkmark
        case chevron
    }

    init(
        icon: String,
        iconTint: Color = .irPrimaryAccent,
        title: String,
        description: String,
        trailing: TrailingDecoration = .none
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.description = description
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconTint.opacity(0.14))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.irTextPrimary)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.irTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            switch trailing {
            case .none:
                EmptyView()
            case .checkmark:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.irSuccess)
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.55))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Primary CTA (lime, black text)

struct OnboardingPrimaryButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    init(title: String, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                } else {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.black)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.irPrimaryAccent)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Secondary CTA (text only, irTextSecondary)

struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.irTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Scaffold (background + scroll + CTA pair)

struct OnboardingScaffold<Content: View>: View {
    let content: Content
    let primaryTitle: String
    let primaryAction: () -> Void
    let isPrimaryLoading: Bool
    let secondaryTitle: String?
    let secondaryAction: (() -> Void)?

    init(
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        isPrimaryLoading: Bool = false,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.primaryTitle = primaryTitle
        self.primaryAction = primaryAction
        self.isPrimaryLoading = isPrimaryLoading
        self.secondaryTitle = secondaryTitle
        self.secondaryAction = secondaryAction
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                content
                    .padding(.horizontal, 18)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 4) {
                OnboardingPrimaryButton(title: primaryTitle, isLoading: isPrimaryLoading, action: primaryAction)
                if let secondaryTitle, let secondaryAction {
                    OnboardingSecondaryButton(title: secondaryTitle, action: secondaryAction)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.irBackgroundApp)
    }
}
