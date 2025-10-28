//
//  AppearancePreview.swift
//  InsightRun
//
//  Preview helpers for testing Light/Dark modes
//

import SwiftUI

// MARK: - Preview Container for Both Modes
/// Helper view for previewing components in both Light and Dark modes side by side
struct AppearancePreview<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            // Light Mode
            content
                .preferredColorScheme(.light)
                .previewDisplayName("Light Mode")

            Divider()

            // Dark Mode
            content
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}

// MARK: - Example Usage in Previews
/*
 Use this in your SwiftUI previews to see both modes at once:

 ```swift
 #Preview("Light & Dark") {
     AppearancePreview {
         WorkoutListView()
     }
 }
 ```

 Or test individual modes:

 ```swift
 #Preview("Light Mode") {
     WorkoutListView()
         .preferredColorScheme(.light)
 }

 #Preview("Dark Mode") {
     WorkoutListView()
         .preferredColorScheme(.dark)
 }
 ```
 */

// MARK: - Demo Component
#Preview("Theme Demo - Light") {
    VStack(spacing: 20) {
        Text("InsightRun")
            .font(.title)
            .foregroundStyle(.primary)

        VStack(spacing: 12) {
            Text("Primary Text")
                .foregroundStyle(.primary)
            Text("Secondary Text")
                .foregroundStyle(.secondary)
            Text("Tertiary Text")
                .foregroundStyle(.tertiary)
        }

        HStack(spacing: 16) {
            Circle()
                .fill(.blue.gradient)
                .frame(width: 50, height: 50)
            Circle()
                .fill(.green.gradient)
                .frame(width: 50, height: 50)
            Circle()
                .fill(.orange.gradient)
                .frame(width: 50, height: 50)
            Circle()
                .fill(.red.gradient)
                .frame(width: 50, height: 50)
        }

        VStack(spacing: 12) {
            Text("Matériaux Adaptatifs")
                .font(.headline)

            VStack {
                Text("Ultra Thin Material")
                    .padding()
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack {
                Text("Thin Material")
                    .padding()
            }
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Theme Demo - Dark") {
    VStack(spacing: 20) {
        Text("InsightRun")
            .font(.title)
            .foregroundStyle(.primary)

        VStack(spacing: 12) {
            Text("Primary Text")
                .foregroundStyle(.primary)
            Text("Secondary Text")
                .foregroundStyle(.secondary)
            Text("Tertiary Text")
                .foregroundStyle(.tertiary)
        }

        HStack(spacing: 16) {
            Circle()
                .fill(.blue.gradient)
                .frame(width: 50, height: 50)
            Circle()
                .fill(.green.gradient)
                .frame(width: 50, height: 50)
            Circle()
                .fill(.orange.gradient)
                .frame(width: 50, height: 50)
            Circle()
                .fill(.red.gradient)
                .frame(width: 50, height: 50)
        }

        VStack(spacing: 12) {
            Text("Matériaux Adaptatifs")
                .font(.headline)

            VStack {
                Text("Ultra Thin Material")
                    .padding()
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack {
                Text("Thin Material")
                    .padding()
            }
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    .padding()
    .preferredColorScheme(.dark)
}
