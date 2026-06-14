//
//  ViewOnStravaLink.swift
//  InsightRun
//
//  Link to original Strava activity following Brand Guidelines
//  Guidelines: "View on Strava" text in bold, underline, or orange #FC5200
//

import SwiftUI

struct ViewOnStravaLink: View {
    let activityId: Int64
    var style: LinkStyle = .orange

    enum LinkStyle {
        case bold
        case underline
        case orange
        case boldOrange
    }

    private var stravaURL: URL {
        URL(string: "https://www.strava.com/activities/\(activityId)")!
    }

    var body: some View {
        Link(destination: stravaURL) {
            HStack(spacing: Spacing.xxs) {
                Text(String(localized: "strava.viewOnStrava", defaultValue: "View on Strava", comment: "Link to the original activity on Strava"))
                    .applyLinkStyle(style)
                Image(systemName: "arrow.up.right.square")
                    .font(IRFont.caption)
            }
        }
    }
}

// MARK: - Text Style Extension

private extension Text {
    func applyLinkStyle(_ style: ViewOnStravaLink.LinkStyle) -> some View {
        switch style {
        case .bold:
            return self
                .fontWeight(.bold)
                .foregroundStyle(Color.irTextPrimary)
        case .underline:
            return self
                .underline()
                .foregroundStyle(Color.irTextPrimary)
        case .orange:
            return self
                .foregroundStyle(Color.brandStrava)
        case .boldOrange:
            return self
                .fontWeight(.bold)
                .foregroundStyle(Color.brandStrava)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: Spacing.base) {
        Text("Link Styles (per Strava Guidelines):")
            .font(IRFont.headline)

        ViewOnStravaLink(activityId: 123456789, style: .bold)
        ViewOnStravaLink(activityId: 123456789, style: .underline)
        ViewOnStravaLink(activityId: 123456789, style: .orange)
        ViewOnStravaLink(activityId: 123456789, style: .boldOrange)
    }
    .padding()
}
