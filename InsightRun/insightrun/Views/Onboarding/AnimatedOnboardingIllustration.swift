//
//  AnimatedOnboardingIllustration.swift
//  InsightRun
//
//  Reusable animated illustrations for onboarding steps.
//  Pure SwiftUI animations, no external dependencies.
//

import SwiftUI

// MARK: - Onboarding Illustration Type

enum OnboardingIllustrationType {
    case welcome
    case healthKit
    case notifications
    case strava
    case paywall
}

// MARK: - Main Container

struct AnimatedOnboardingIllustration: View {
    let type: OnboardingIllustrationType

    @State private var appeared = false

    var body: some View {
        Group {
            switch type {
            case .welcome:
                WelcomeIllustration()
            case .healthKit:
                HeartbeatIllustration()
            case .notifications:
                BellRingIllustration()
            case .strava:
                StravaChevronIllustration()
            case .paywall:
                CrownShimmerIllustration()
            }
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.8)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
    }
}

// MARK: - Welcome: Animated Runner with Motion Trail + Pulsing Glow

private struct WelcomeIllustration: View {
    @State private var runnerOffset: CGFloat = 0
    @State private var glowScale: CGFloat = 1.0
    @State private var trailOpacity: Double = 0.0

    var body: some View {
        ZStack {
            // Pulsing glow background
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.irPrimaryAccent.opacity(0.3),
                            Color.irPrimaryAccent.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(glowScale)

            // Motion trail (staggered copies behind the runner)
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "figure.run")
                    .font(IRFont.display)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irPrimaryAccent.opacity(0.15 - Double(index) * 0.05))
                    .offset(x: -CGFloat(index + 1) * 12, y: CGFloat(index) * 2)
                    .opacity(trailOpacity)
            }

            // Main runner figure
            Image(systemName: "figure.run")
                .font(IRFont.display)
                .fontWeight(.medium)
                .foregroundStyle(Color.irPrimaryAccent.gradient)
                .offset(y: runnerOffset)
        }
        .frame(width: 160, height: 160)
        .onAppear {
            // Subtle bounce animation for the runner
            withAnimation(
                .easeInOut(duration: 0.8)
                .repeatForever(autoreverses: true)
            ) {
                runnerOffset = -6
            }

            // Pulsing glow
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
                glowScale = 1.2
            }

            // Fade in motion trail
            withAnimation(.easeIn(duration: 0.8).delay(0.3)) {
                trailOpacity = 1.0
            }
        }
    }
}

// MARK: - HealthKit: Heart with Heartbeat Pulse Animation

private struct HeartbeatIllustration: View {
    @State private var heartScale: CGFloat = 1.0
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 0.6

    var body: some View {
        ZStack {
            // Expanding pulse rings
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .stroke(Color.irError.opacity(ringOpacity), lineWidth: 2)
                    .frame(width: 100, height: 100)
                    .scaleEffect(ringScale + CGFloat(index) * 0.15)
                    .opacity(ringOpacity - Double(index) * 0.2)
            }

            // Heart icon background glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.irError.opacity(0.2),
                            Color.irError.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 60
                    )
                )
                .frame(width: 140, height: 140)
                .scaleEffect(heartScale)

            // Heart icon
            Image(systemName: "heart.fill")
                .font(IRFont.numXL)
                .foregroundStyle(Color.irError.gradient)
                .scaleEffect(heartScale)
        }
        .frame(width: 160, height: 160)
        .onAppear {
            // Heartbeat animation using a spring for a snappy pulse feel
            withAnimation(
                .spring(response: 0.4, dampingFraction: 0.4, blendDuration: 0.2)
                .repeatForever(autoreverses: true)
            ) {
                heartScale = 1.15
            }

            // Pulse rings expand outward continuously
            withAnimation(
                .easeOut(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                ringScale = 1.4
                ringOpacity = 0.0
            }
        }
    }
}

// MARK: - Notifications: Bell with Shake/Ring Animation

private struct BellRingIllustration: View {
    @State private var bellRotation: Double = -12
    @State private var showWaves = false

    var body: some View {
        ZStack {
            // Sound wave arcs
            ForEach(0..<3, id: \.self) { index in
                SoundWaveArc(index: index)
                    .opacity(showWaves ? 1 : 0)
            }

            // Glow behind bell
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.irPrimaryAccent.opacity(0.15),
                            Color.irPrimaryAccent.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 70
                    )
                )
                .frame(width: 150, height: 150)

            // Bell icon
            Image(systemName: "bell.fill")
                .font(IRFont.numXL)
                .foregroundStyle(Color.irPrimaryAccent.gradient)
                .rotationEffect(.degrees(bellRotation), anchor: .top)

            // Badge dot
            Circle()
                .fill(Color.irError)
                .frame(width: 16, height: 16)
                .offset(x: 20, y: -24)
                .scaleEffect(showWaves ? 1 : 0.5)
        }
        .frame(width: 160, height: 160)
        .onAppear {
            // Bell ring: pendulum swing
            withAnimation(
                .easeInOut(duration: 0.4)
                .repeatForever(autoreverses: true)
            ) {
                bellRotation = 12
            }

            // Show sound waves with delay
            withAnimation(.easeIn(duration: 0.5).delay(0.3)) {
                showWaves = true
            }
        }
    }
}

private struct SoundWaveArc: View {
    let index: Int

    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0.6

    var body: some View {
        Circle()
            .trim(from: 0.05, to: 0.2)
            .stroke(Color.irPrimaryAccent.opacity(opacity), lineWidth: 2.5)
            .frame(width: 100 + CGFloat(index) * 24, height: 100 + CGFloat(index) * 24)
            .rotationEffect(.degrees(-50))
            .scaleEffect(scale)
            .onAppear {
                let delay = Double(index) * 0.2
                withAnimation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    scale = 1.0
                    opacity = 0.1
                }
            }
    }
}

// MARK: - Strava: Chevron with Draw-On Animation

private struct StravaChevronIllustration: View {
    @State private var drawProgress: CGFloat = 0
    @State private var glowOpacity: Double = 0

    var body: some View {
        ZStack {
            // Strava brand circle
            Circle()
                .fill(Color.brandStrava)
                .frame(width: 120, height: 120)
                .shadow(color: Color.brandStrava.opacity(glowOpacity * 0.4), radius: 20, y: 8)

            // Strava double-chevron logo
            StravaLogoShape()
                .fill(Color.white)
                .frame(width: 50, height: 60)
                .opacity(drawProgress)
        }
        .frame(width: 160, height: 160)
        .onAppear {
            // Draw-on animation
            withAnimation(.easeInOut(duration: 1.2).delay(0.2)) {
                drawProgress = 1.0
            }

            // Glow appears after draw completes
            withAnimation(.easeIn(duration: 0.6).delay(1.0)) {
                glowOpacity = 1.0
            }

            // Subtle pulsing glow after initial draw
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true)
                ) {
                    glowOpacity = 0.6
                }
            }
        }
    }
}

private struct StravaLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()

        // Front chevron (taller, full opacity)
        path.move(to: CGPoint(x: w * 0.14, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.44, y: 0))
        path.addLine(to: CGPoint(x: w * 0.73, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.44, y: h * 0.34))
        path.addLine(to: CGPoint(x: w * 0.31, y: h * 0.58))
        path.closeSubpath()

        // Back chevron (shorter, offset right)
        path.move(to: CGPoint(x: w * 0.56, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.73, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.58))
        path.addLine(to: CGPoint(x: w * 0.64, y: h))
        path.addLine(to: CGPoint(x: w * 0.43, y: h * 0.58))
        path.closeSubpath()

        return path
    }
}

// MARK: - Paywall: Crown with Sparkle/Shimmer Effect

private struct CrownShimmerIllustration: View {
    @State private var shimmerOffset: CGFloat = -100
    @State private var sparkleScale: [CGFloat] = [0, 0, 0, 0]
    @State private var crownScale: CGFloat = 0.9

    var body: some View {
        ZStack {
            // Golden glow background
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.irWarning.opacity(0.3),
                            Color.irWarning.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 15,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(crownScale)

            // Crown icon with shimmer overlay
            ZStack {
                Image(systemName: "crown.fill")
                    .font(IRFont.numXL)
                    .foregroundStyle(Color.irWarning.gradient)

                // Shimmer sweep
                Image(systemName: "crown.fill")
                    .font(IRFont.numXL)
                    .foregroundStyle(Color.irTextPrimary.opacity(0.3))
                    .mask(
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, Color.irTextPrimary, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 40)
                            .offset(x: shimmerOffset)
                    )
            }
            .scaleEffect(crownScale)

            // Sparkle particles around the crown
            ForEach(0..<4, id: \.self) { index in
                SparkleParticle(index: index, scale: sparkleScale[index])
            }
        }
        .frame(width: 160, height: 160)
        .onAppear {
            // Crown scale breathing
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                crownScale = 1.05
            }

            // Shimmer sweep across crown
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: false)
                .delay(0.5)
            ) {
                shimmerOffset = 100
            }

            // Staggered sparkle animations
            for i in 0..<4 {
                let delay = Double(i) * 0.3 + 0.4
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    sparkleScale[i] = 1.0
                }
            }
        }
    }
}

private struct SparkleParticle: View {
    let index: Int
    let scale: CGFloat

    // Position sparkles around the crown
    private var offset: CGSize {
        let positions: [CGSize] = [
            CGSize(width: -40, height: -35),
            CGSize(width: 42, height: -30),
            CGSize(width: -30, height: 15),
            CGSize(width: 35, height: 20)
        ]
        return positions[index % positions.count]
    }

    var body: some View {
        Image(systemName: "sparkle")
            .font(IRFont.body)
            .foregroundStyle(Color.irWarning)
            .scaleEffect(scale)
            .opacity(Double(scale))
            .offset(offset)
    }
}

// MARK: - Preview

#Preview("Welcome") {
    AnimatedOnboardingIllustration(type: .welcome)
        .padding()
}

#Preview("HealthKit") {
    AnimatedOnboardingIllustration(type: .healthKit)
        .padding()
}

#Preview("Notifications") {
    AnimatedOnboardingIllustration(type: .notifications)
        .padding()
}

#Preview("Strava") {
    AnimatedOnboardingIllustration(type: .strava)
        .padding()
}

#Preview("Paywall") {
    AnimatedOnboardingIllustration(type: .paywall)
        .padding()
}
