//
//  StravaConnectButton.swift
//  InsightRun
//
//  Official "Connect with Strava" button following Strava Brand Guidelines
//  https://developers.strava.com/guidelines/
//

import SwiftUI

struct StravaConnectButton: View {
    let action: () -> Void
    let isLoading: Bool
    var variant: Variant = .orange

    enum Variant {
        case orange
        case white

        var imageName: String {
            switch self {
            case .orange: return "strava-connect-orange"
            case .white: return "strava-connect-white"
            }
        }
    }

    var body: some View {
        Button(action: action) {
            if isLoading {
                HStack {
                    ProgressView()
                        .tint(variant == .orange ? .white : Color.brandStrava)
                    Text(String(localized: "Connecting...", comment: "Loading state while connecting to Strava"))
                        .font(IRFont.headline)
                        .foregroundStyle(variant == .orange ? .white : Color.brandStrava)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48) // Official height @1x
                .background(variant == .orange ? Color.brandStrava : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
            } else {
                // Use official Strava button image (per Strava Brand Guidelines)
                // Button height: 48px @1x, 96px @2x
                Image(variant.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 48) // Official height @1x
            }
        }
        .disabled(isLoading)
    }
}

// MARK: - Strava Logo (Symbol only)

struct StravaLogo: View {
    var color: Color = .brandStrava
    var size: CGFloat = 32

    var body: some View {
        // Strava logo: two triangles forming a stylized "A"
        ZStack {
            // Left triangle (slightly behind)
            Triangle()
                .fill(color.opacity(0.7))
                .frame(width: size * 0.45, height: size * 0.7)
                .offset(x: -size * 0.12, y: size * 0.08)

            // Right triangle (main, in front)
            Triangle()
                .fill(color)
                .frame(width: size * 0.55, height: size * 0.85)
                .offset(x: size * 0.08, y: 0)
        }
        .frame(width: size, height: size)
    }
}

// Triangle shape for Strava logo
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Strava Navigation Row

struct StravaNavigationRow: View {
    let action: () -> Void
    let isLoading: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                StravaLogo(size: 28)

                Text("Strava")
                    .font(IRFont.body)
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(IRFont.caption)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Powered by Strava Logo

struct PoweredByStravaLogo: View {
    var variant: Variant = .orange

    enum Variant {
        case orange
        case white
        case black

        var imageName: String {
            switch self {
            case .orange: return "powered-by-strava-orange"
            case .white: return "powered-by-strava-white"
            case .black: return "powered-by-strava-black"
            }
        }
    }

    var body: some View {
        // Use official Strava "Powered by" logo (per Strava Brand Guidelines)
        // Logos available in orange, white, black (horizontal only)
        Image(variant.imageName)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

#Preview("Connect Button - Orange") {
    VStack(spacing: Spacing.lg) {
        StravaConnectButton(action: {}, isLoading: false, variant: .orange)
        StravaConnectButton(action: {}, isLoading: true, variant: .orange)
    }
    .padding()
}

#Preview("Connect Button - White") {
    VStack(spacing: Spacing.lg) {
        StravaConnectButton(action: {}, isLoading: false, variant: .white)
        StravaConnectButton(action: {}, isLoading: true, variant: .white)
    }
    .padding()
    .background(Color.black)
}

#Preview("Powered by Strava") {
    VStack(spacing: Spacing.lg) {
        PoweredByStravaLogo(variant: .orange)
            .frame(height: 30)

        PoweredByStravaLogo(variant: .black)
            .frame(height: 30)

        PoweredByStravaLogo(variant: .white)
            .frame(height: 30)
            .background(Color.black)
    }
    .padding()
}

#Preview("Strava Logo") {
    VStack(spacing: Spacing.lg) {
        StravaLogo(size: 48)

        StravaLogo(color: .white, size: 48)
            .padding()
            .background(Color.black)
    }
    .padding()
}

#Preview("Strava Navigation Row") {
    List {
        StravaNavigationRow(action: {}, isLoading: false)
        StravaNavigationRow(action: {}, isLoading: true)
    }
}
