//
//  SplashScreenView.swift
//  InsightRun
//
//  Animated splash screen shown once per app launch
//

import SwiftUI

struct SplashScreenView: View {
    @State private var iconScale: CGFloat = 0
    @State private var iconOpacity: Double = 0
    @State private var textOffset: CGFloat = 20
    @State private var textOpacity: Double = 0
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Solid background
            Color.irBackgroundApp
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // App icon
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .scaleEffect(iconScale * pulseScale)
                    .opacity(iconOpacity)

                // App name
                Text("Insight Run")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.irTextPrimary)
                    .offset(y: textOffset)
                    .opacity(textOpacity)
            }
        }
        .onAppear {
            // Phase 1: Icon scales in with spring
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }

            // Phase 2: Text fades in with upward motion
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                textOffset = 0
                textOpacity = 1.0
            }

            // Phase 3: Subtle pulse on the icon
            withAnimation(
                .easeInOut(duration: 0.8)
                .repeatCount(2, autoreverses: true)
                .delay(0.7)
            ) {
                pulseScale = 1.08
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
