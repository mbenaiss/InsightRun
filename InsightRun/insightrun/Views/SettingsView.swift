//
//  SettingsView.swift
//  InsightRun
//
//  V4 settings — dark cards, lime accent, eyebrow sections, 0.5pt dividers.
//

import SwiftUI

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @EnvironmentObject private var revenueCatManager: RevenueCatManager
    @State private var showPaywall = false
    @State private var showingMedicalSources = false
    @State private var showRefreshSheet = false
    @State private var showSuuntoImport = false
    @ObservedObject private var stravaAuth = StravaAuthService.shared
    @ObservedObject private var remoteConfig = RemoteConfigService.shared
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var isSyncing = false
    @State private var lastSyncResult: String?
    @State private var notificationsEnabled = false
    @State private var aiDataSharingEnabled = false
    @State private var showRevokeAlert = false
    @State private var skipConsentOnChange = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    Text(String(localized: "Settings", comment: "Navigation title for settings view"))
                        .font(IRFont.title1.weight(.heavy))
                        .tracking(-1.0)
                        .foregroundStyle(Color.irTextPrimary)
                        .padding(.top, Spacing.xxs)

                    sectionSubscription
                    sectionAppearance
                    sectionNotifications
                    sectionPrivacy
                    sectionMedical
                    sectionFeedback
                    sectionTrainingData
                    if remoteConfig.isFeatureEnabled(.strava) {
                        sectionStrava
                    }
                    sectionAppleHealth
                    #if DEBUG
                    sectionDebug
                    #endif
                    sectionAbout
                }
                .padding(.horizontal, Spacing.cardPadding)
                .padding(.bottom, Spacing.xxl)
            }
            .background(Color.irBackgroundApp)
            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showPaywall) {
                SubscriptionPaywallView()
            }
            .sheet(isPresented: $showingMedicalSources) {
                MedicalSourcesView()
            }
            .sheet(isPresented: $showRefreshSheet) {
                HistoricalIndexationSheet()
            }
            .sheet(isPresented: $showSuuntoImport) {
                SuuntoImportView()
            }
        }
        .preferredColorScheme(themeManager.selectedTheme.colorScheme)
        .task {
            await notificationManager.checkPermissionStatus()
            notificationsEnabled = notificationManager.isNotificationsEnabled
            aiDataSharingEnabled = ConsentService.shared.hasConsentedToAIDataSharing
        }
        .alert(
            String(localized: "Disable AI Features?", comment: "Revoke AI consent alert title"),
            isPresented: $showRevokeAlert
        ) {
            Button(String(localized: "Cancel", comment: "Cancel revoke AI consent"), role: .cancel) {}
            Button(String(localized: "Disable", comment: "Confirm revoke AI consent"), role: .destructive) {
                ConsentService.shared.revokeAIConsent()
                skipConsentOnChange = true
                aiDataSharingEnabled = false
            }
        } message: {
            Text(String(localized: "Revoking AI data sharing will disable all AI-powered features including workout analysis, coaching and recovery insights.", comment: "Revoke AI consent alert message"))
        }
    }

    // MARK: - Subscription

    private var sectionSubscription: some View {
        sectionContainer(
            title: String(localized: "Subscription"),
            footer: revenueCatManager.hasAIAccess ? nil : String(localized: "Unlock full access to advanced AI analysis, personalized advice and more.")
        ) {
            if revenueCatManager.isTestFlightEnvironment {
                settingsRow(
                    icon: "airplane.circle.fill",
                    iconColor: Color.irPrimaryAccent,
                    title: String(localized: "TestFlight - Premium Access"),
                    subtitle: String(localized: "All features unlocked for testing")
                )
            } else if revenueCatManager.isSubscriptionActive {
                settingsRow(
                    icon: "checkmark.circle.fill",
                    iconColor: Color.irSuccess,
                    title: String(localized: "Active subscription")
                )
                rowDivider
                settingsButtonRow(
                    icon: "creditcard",
                    iconColor: Color.irPrimaryAccent,
                    title: String(localized: "Manage subscription"),
                    trailing: .external
                ) {
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                settingsButtonRow(
                    icon: "crown.fill",
                    iconColor: Color.irWarning,
                    title: String(localized: "Unlock Premium"),
                    subtitle: String(localized: "Access all features"),
                    trailing: .chevron
                ) {
                    showPaywall = true
                }
                rowDivider
                settingsButtonRow(
                    icon: "arrow.clockwise",
                    iconColor: Color.irPrimaryAccent,
                    title: String(localized: "Restore Purchases")
                ) {
                    Task {
                        do {
                            try await revenueCatManager.restorePurchases()
                        } catch {
                            print("Error restoring purchases: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Appearance

    private var sectionAppearance: some View {
        sectionContainer(
            title: String(localized: "Appearance"),
            footer: String(localized: "Choose the app theme. System mode automatically adapts to your iOS settings.")
        ) {
            HStack(spacing: Spacing.md) {
                iconTile(systemName: "paintbrush", color: Color.irPrimaryAccent)
                Text(String(localized: "Appearance"))
                    .font(IRFont.body.weight(.semibold))
                    .foregroundStyle(Color.irTextPrimary)
                Spacer()
                Picker("", selection: Bindable(themeManager).selectedTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Label(theme.localizedName, systemImage: theme.icon)
                            .tag(theme)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.irPrimaryAccent)
                .onChange(of: themeManager.selectedTheme) { oldValue, newValue in
                    AnalyticsService.shared.trackSettingsAppearanceChanged(
                        oldTheme: oldValue.rawValue,
                        newTheme: newValue.rawValue
                    )
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.dash)
        }
    }

    // MARK: - Notifications

    private var sectionNotifications: some View {
        sectionContainer(
            title: String(localized: "Notifications", comment: "Notifications section header"),
            footer: String(localized: "Receive daily readiness reminders, weekly training summaries, and proactive coaching alerts.", comment: "Notifications section footer")
        ) {
            settingsToggleRow(
                icon: "bell.fill",
                iconColor: Color.irPrimaryAccent,
                title: String(localized: "Enable Notifications", comment: "Master notification toggle"),
                isOn: $notificationsEnabled
            )
            .onChange(of: notificationsEnabled) { _, newValue in
                if newValue {
                    Task {
                        let granted = await notificationManager.requestPermissions()
                        if !granted { notificationsEnabled = false }
                    }
                } else {
                    notificationManager.removeAllPendingNotifications()
                }
            }

            if notificationsEnabled {
                rowDivider
                settingsToggleRow(
                    icon: "sun.max",
                    iconColor: Color.irWarning,
                    title: String(localized: "Daily Readiness", comment: "Daily readiness notification toggle"),
                    subtitle: notificationManager.isDailyReadinessEnabled ? String(localized: "After wake-up detection", comment: "Wake-up based notification schedule") : nil,
                    isOn: Binding(
                        get: { notificationManager.isDailyReadinessEnabled },
                        set: { enabled in
                            if enabled {
                                notificationManager.enableDailyReadiness()
                            } else {
                                notificationManager.cancelDailyReadiness()
                            }
                        }
                    )
                )

                rowDivider
                settingsToggleRow(
                    icon: "calendar",
                    iconColor: Color.irPrimaryAccent,
                    title: String(localized: "Weekly Summary", comment: "Weekly summary notification toggle"),
                    subtitle: notificationManager.isWeeklySummaryEnabled ? String(localized: "Sunday at 6:00 PM", comment: "Weekly summary schedule") : nil,
                    isOn: Binding(
                        get: { notificationManager.isWeeklySummaryEnabled },
                        set: { enabled in
                            if enabled {
                                notificationManager.scheduleWeeklySummary()
                            } else {
                                notificationManager.cancelWeeklySummary()
                            }
                        }
                    )
                )
            }
        }
    }

    // MARK: - Privacy & AI

    private var sectionPrivacy: some View {
        sectionContainer(
            title: String(localized: "Privacy & AI", comment: "Privacy and AI section header"),
            footer: String(localized: "settings.ai_privacy.footer")
        ) {
            settingsToggleRow(
                icon: "brain.head.profile",
                iconColor: Color.irPrimaryAccent,
                title: String(localized: "AI Data Sharing", comment: "AI data sharing toggle"),
                subtitle: aiDataSharingEnabled ? ConsentService.shared.consentDate.map { String(localized: "Consent granted on", comment: "Consent date label") + " " + formatDate($0) } : nil,
                isOn: $aiDataSharingEnabled
            )
            .onChange(of: aiDataSharingEnabled) { _, newValue in
                guard !skipConsentOnChange else {
                    skipConsentOnChange = false
                    return
                }
                if newValue {
                    if !ConsentService.shared.hasConsentedToAIDataSharing {
                        ConsentService.shared.grantAIConsent()
                    }
                } else {
                    skipConsentOnChange = true
                    aiDataSharingEnabled = true
                    showRevokeAlert = true
                }
            }

            rowDivider
            settingsButtonRow(
                icon: "hand.raised.fill",
                iconColor: Color.irPrimaryAccent,
                title: String(localized: "Privacy Policy", comment: "Privacy policy link"),
                trailing: .external
            ) {
                if let url = URL(string: "https://insightrun.altcode.studio/privacy") {
                    openURL(url)
                }
            }
        }
    }

    // MARK: - Medical Information

    private var sectionMedical: some View {
        sectionContainer(
            title: String(localized: "Medical Information", comment: "Medical information section header"),
            footer: String(localized: "Health metrics and recovery recommendations are based on published scientific research. Tap to view all sources.", comment: "Medical information footer")
        ) {
            settingsButtonRow(
                icon: "book.closed.fill",
                iconColor: Color.irPrimaryAccent,
                title: String(localized: "Medical Sources", comment: "Medical sources settings button"),
                subtitle: String(localized: "View scientific references", comment: "Medical sources subtitle"),
                trailing: .chevron
            ) {
                showingMedicalSources = true
                AnalyticsService.shared.trackSettingsMedicalSourcesViewed()
            }
        }
    }

    // MARK: - Feedback

    private var sectionFeedback: some View {
        sectionContainer(
            title: String(localized: "Feedback", comment: "Feedback section header")
        ) {
            settingsButtonRow(
                icon: "star.fill",
                iconColor: Color.irWarning,
                title: String(localized: "Rate Insight Run", comment: "Rate app button in settings"),
                trailing: .external
            ) {
                if let url = ReviewManager.shared.reviewURL {
                    openURL(url)
                    AnalyticsService.shared.trackReviewManualTap()
                }
            }

            rowDivider
            settingsButtonRow(
                icon: "envelope.fill",
                iconColor: Color.irPrimaryAccent,
                title: String(localized: "Send Feedback", comment: "Send feedback button in settings"),
                trailing: .external
            ) {
                openFeedbackEmail()
            }
        }
    }

    // MARK: - Training Data

    private var sectionTrainingData: some View {
        sectionContainer(
            title: String(localized: "Training Data", comment: "Training data section header")
        ) {
            if let summary = HistoricalSummaryStorage.shared.load() {
                let days = HistoricalSummaryStorage.shared.daysUntilRefresh()
                let subtitle: String = {
                    var parts: [String] = [
                        String(localized: "Last updated:", comment: "Last update label") + " " + formatDate(summary.indexedAt)
                    ]
                    if days > 0 {
                        parts.append(String(localized: "Next update in", comment: "Next update prefix") + " \(days) " + String(localized: "days", comment: "days unit"))
                    } else {
                        parts.append(String(localized: "Update recommended", comment: "Update recommended message"))
                    }
                    return parts.joined(separator: " · ")
                }()

                settingsRow(
                    icon: "checkmark.circle.fill",
                    iconColor: Color.irSuccess,
                    title: "\(summary.workoutCount) " + String(localized: "workouts indexed", comment: "Number of indexed workouts"),
                    subtitle: subtitle
                )

                rowDivider
                let canRefresh = HistoricalSummaryStorage.shared.canManualRefresh()
                settingsButtonRow(
                    icon: "arrow.clockwise",
                    iconColor: canRefresh ? Color.irPrimaryAccent : Color.irTextSecondary,
                    title: String(localized: "Refresh data", comment: "Refresh data button"),
                    subtitle: canRefresh ? nil : String(localized: "Available 1 month after last update", comment: "Refresh cooldown message"),
                    trailing: .chevron,
                    disabled: !canRefresh
                ) {
                    showRefreshSheet = true
                    AnalyticsService.shared.trackSettingsRefreshDataClicked()
                }
            } else {
                settingsRow(
                    icon: "exclamationmark.circle",
                    iconColor: Color.irWarning,
                    title: String(localized: "No data indexed", comment: "No indexed data message")
                )
                rowDivider
                settingsButtonRow(
                    icon: "arrow.clockwise",
                    iconColor: Color.irPrimaryAccent,
                    title: String(localized: "Index now", comment: "Index now button"),
                    trailing: .chevron
                ) {
                    showRefreshSheet = true
                }
            }
        }
    }

    // MARK: - Strava

    private var sectionStrava: some View {
        sectionContainer(title: String(localized: "Integrations")) {
            if stravaAuth.isAuthenticated {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.md) {
                        iconTile(systemName: "checkmark.circle.fill", color: Color.irSuccess)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Strava Connected"))
                                .font(IRFont.body.weight(.semibold))
                                .foregroundStyle(Color.irTextPrimary)
                            Text(lastSyncResult ?? String(localized: "Activities syncing automatically"))
                                .font(IRFont.eyebrow)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                        Spacer(minLength: 8)
                    }
                    PoweredByStravaLogo(variant: .orange)
                        .frame(height: 18)
                        .padding(.leading, 44)
                }
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, Spacing.dash)

                rowDivider
                settingsButtonRow(
                    icon: isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise",
                    iconColor: Color.irPrimaryAccent,
                    title: String(localized: "Sync Now"),
                    trailing: isSyncing ? .progress : .chevron,
                    disabled: isSyncing
                ) {
                    syncStravaActivities()
                }

                rowDivider
                settingsButtonRow(
                    icon: "link.badge.plus",
                    iconColor: Color.irError,
                    title: String(localized: "Disconnect"),
                    titleColor: Color.irError
                ) {
                    Task {
                        try? StravaCache.shared.clearAll()
                        try? UnifiedWorkoutCache.shared.clearStravaWorkouts()
                        await stravaAuth.logout()
                        AnalyticsService.shared.trackStravaDisconnected()
                    }
                }
            } else {
                StravaConnectButton(
                    action: {
                        Task {
                            do {
                                try await stravaAuth.authenticate()
                            } catch {
                                print("Strava auth error: \(error)")
                            }
                        }
                    },
                    isLoading: false,
                    variant: .orange
                )
                .padding(.horizontal, Spacing.base)
                .padding(.vertical, Spacing.dash)
            }
        }
    }

    // MARK: - Apple Health

    private var sectionAppleHealth: some View {
        sectionContainer(
            title: String(localized: "Apple Health"),
            footer: String(localized: "Grant write access to save imported workouts to the Health app.")
        ) {
            settingsButtonRow(
                icon: "heart.text.square",
                iconColor: Color.irError,
                title: String(localized: "Health Permissions"),
                subtitle: String(localized: "Manage read and write access"),
                trailing: .external
            ) {
                Task {
                    do {
                        try await HealthKitManager.shared.requestAuthorization()
                        print("✅ HealthKit authorization requested")
                    } catch {
                        print("❌ HealthKit authorization failed: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - About

    private var sectionAbout: some View {
        sectionContainer(title: String(localized: "About", comment: "Section header for app information")) {
            settingsValueRow(
                icon: "app.badge",
                iconColor: Color.irPrimaryAccent,
                title: String(localized: "Version", comment: "Label for app version"),
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
            )
            rowDivider
            settingsValueRow(
                icon: "hammer",
                iconColor: Color.irPrimaryAccent,
                title: String(localized: "Build", comment: "Label for app build number"),
                value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
            )
        }
    }

    // MARK: - Debug

    #if DEBUG
    private var sectionDebug: some View {
        sectionContainer(
            title: String(localized: "Debug"),
            footer: String(localized: "Outils de test pour simuler différents états d'abonnement. Redémarrez l'app après avoir réinitialisé.")
        ) {
            settingsButtonRow(icon: "airplane.circle.fill", iconColor: Color.irPrimaryAccent, title: String(localized: "Simuler TestFlight")) {
                revenueCatManager.debugTestFlightOverride = true
            }
            rowDivider
            settingsButtonRow(icon: "globe", iconColor: Color.irPrimaryAccent, title: String(localized: "Simuler Production")) {
                revenueCatManager.debugTestFlightOverride = false
            }
            rowDivider
            settingsButtonRow(icon: "arrow.uturn.backward", iconColor: Color.irTextSecondary, title: String(localized: "Reset environnement")) {
                revenueCatManager.debugTestFlightOverride = nil
            }
            rowDivider
            settingsButtonRow(icon: "person.crop.circle.badge.xmark", iconColor: Color.irError, title: String(localized: "Simuler non-abonné")) {
                revenueCatManager.debugTestFlightOverride = false
                revenueCatManager.isSubscriptionActive = false
                revenueCatManager.debugExhaustFreeRequests()
            }
            rowDivider
            settingsButtonRow(icon: "person.crop.circle.badge.checkmark", iconColor: Color.irSuccess, title: String(localized: "Simuler abonné")) {
                revenueCatManager.debugTestFlightOverride = false
                revenueCatManager.isSubscriptionActive = true
                revenueCatManager.resetFreeRequestCount()
            }
            rowDivider
            settingsButtonRow(icon: "rectangle.portrait.on.rectangle.portrait", iconColor: Color.irPrimaryAccent, title: String(localized: "Afficher paywall")) {
                showPaywall = true
            }
            rowDivider
            settingsButtonRow(icon: "arrow.uturn.backward.circle", iconColor: Color.irWarning, title: String(localized: "Réinitialiser le paywall")) {
                UserDefaults.standard.removeObject(forKey: "hasSeenInitialPaywall")
                revenueCatManager.hasSeenInitialPaywall = false
            }
            rowDivider
            settingsButtonRow(icon: "arrow.uturn.backward.circle.badge.ellipsis", iconColor: Color.irPrimaryAccent, title: String(localized: "Réinitialiser l'onboarding")) {
                OnboardingManager.shared.resetOnboarding()
            }
            rowDivider
            settingsButtonRow(icon: "trash", iconColor: Color.irError, title: String(localized: "Delete LLM History", comment: "Debug button to clear historical summary storage"), titleColor: Color.irError) {
                HistoricalSummaryStorage.shared.clear()
            }
            rowDivider
            settingsButtonRow(icon: "shield.slash", iconColor: Color.irError, title: String(localized: "Réinitialiser consentement IA"), titleColor: Color.irError) {
                ConsentService.shared.resetConsentState()
            }
        }
    }
    #endif

    // MARK: - Section container

    @ViewBuilder
    private func sectionContainer<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DashboardEyebrow(title: title)

            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
            )

            if let footer {
                Text(footer)
                    .font(IRFont.eyebrow)
                    .lineSpacing(2)
                    .foregroundStyle(Color.irTextSecondary.opacity(0.7))
                    .padding(.horizontal, Spacing.xxs)
                    .padding(.top, Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Row helpers

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.irBorder)
            .frame(height: 0.5)
    }

    private func iconTile(systemName: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xs)
                .fill(color.opacity(0.16))
                .frame(width: 32, height: 32)
            Image(systemName: systemName)
                .font(IRFont.body)
                .foregroundStyle(color)
        }
    }

    private func settingsRow(
        icon: String,
        iconColor: Color = Color.irPrimaryAccent,
        title: String,
        subtitle: String? = nil
    ) -> some View {
        HStack(spacing: Spacing.md) {
            iconTile(systemName: icon, color: iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(IRFont.body.weight(.semibold))
                    .foregroundStyle(Color.irTextPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(IRFont.eyebrow)
                        .lineSpacing(1)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.dash)
    }

    private func settingsValueRow(
        icon: String,
        iconColor: Color = Color.irPrimaryAccent,
        title: String,
        value: String
    ) -> some View {
        HStack(spacing: Spacing.md) {
            iconTile(systemName: icon, color: iconColor)
            Text(title)
                .font(IRFont.body.weight(.semibold))
                .foregroundStyle(Color.irTextPrimary)
            Spacer()
            Text(value)
                .font(IRFont.monoSM.weight(.medium))
                .foregroundStyle(Color.irTextSecondary)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.dash)
    }

    private func settingsToggleRow(
        icon: String,
        iconColor: Color = Color.irPrimaryAccent,
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: Spacing.md) {
            iconTile(systemName: icon, color: iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(IRFont.body.weight(.semibold))
                    .foregroundStyle(Color.irTextPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(IRFont.eyebrow)
                        .foregroundStyle(Color.irTextSecondary)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color.irPrimaryAccent)
        }
        .padding(.horizontal, Spacing.base)
        .padding(.vertical, Spacing.dash)
    }

    enum RowTrailing {
        case chevron
        case external
        case progress
        case none
    }

    private func settingsButtonRow(
        icon: String,
        iconColor: Color = Color.irPrimaryAccent,
        title: String,
        subtitle: String? = nil,
        titleColor: Color = Color.irTextPrimary,
        trailing: RowTrailing = .none,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                iconTile(systemName: icon, color: iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(IRFont.body.weight(.semibold))
                        .foregroundStyle(titleColor)
                    if let subtitle {
                        Text(subtitle)
                            .font(IRFont.eyebrow)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
                Spacer(minLength: 8)
                switch trailing {
                case .chevron:
                    Image(systemName: "chevron.right")
                        .font(IRFont.eyebrow.weight(.semibold))
                        .foregroundStyle(Color.irTextSecondary)
                case .external:
                    Image(systemName: "arrow.up.forward")
                        .font(IRFont.eyebrow.weight(.semibold))
                        .foregroundStyle(Color.irTextSecondary)
                case .progress:
                    ProgressView().controlSize(.small).tint(Color.irPrimaryAccent)
                case .none:
                    EmptyView()
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.dash)
            .contentShape(Rectangle())
            .opacity(disabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Helper methods (preserved)

    private func syncStravaActivities() {
        isSyncing = true
        lastSyncResult = nil

        Task {
            let backendClient = StravaBackendClient.shared
            let userId = UserIdentityService.shared.userID

            AnalyticsService.shared.trackStravaSyncStarted(initiatedBy: "manual")

            do {
                let syncResponse = try await backendClient.syncActivities(userId: userId, force: false)
                lastSyncResult = String(localized: "\(syncResponse.newActivities) new activities synced")
                print("✅ Manual sync complete: \(syncResponse.newActivities) new, \(syncResponse.totalActivities) total")

                AnalyticsService.shared.trackStravaSyncCompleted(
                    newActivitiesCount: syncResponse.newActivities,
                    totalActivitiesCount: syncResponse.totalActivities
                )
            } catch {
                lastSyncResult = String(localized: "Sync failed: \(error.localizedDescription)")
                print("❌ Manual sync failed: \(error)")

                AnalyticsService.shared.trackStravaSyncFailed(
                    errorType: String(describing: type(of: error)),
                    errorMessage: error.localizedDescription
                )
            }

            isSyncing = false
        }
    }

    private func openFeedbackEmail() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
        let iosVersion = UIDevice.current.systemVersion
        let subject = "Insight Run Feedback (v\(appVersion))"
        let body = "\n\n---\nApp: \(appVersion) (\(buildNumber))\niOS: \(iosVersion)"

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@altcode.studio"
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]

        if let url = components.url {
            openURL(url)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    SettingsView()
        .environment(ThemeManager())
        .environmentObject(RevenueCatManager.shared)
}
