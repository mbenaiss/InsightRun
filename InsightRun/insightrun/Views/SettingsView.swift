//
//  SettingsView.swift
//  InsightRun
//
//  Settings view
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

    var body: some View {
        NavigationStack {
            List {
                // Subscription Section
                Section {
                    // TestFlight environment - show TestFlight badge
                    if revenueCatManager.isTestFlightEnvironment {
                        HStack {
                            Image(systemName: "airplane.circle.fill")
                                .foregroundStyle(Color.irPrimaryAccent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "TestFlight - Premium Access"))
                                    .font(.headline)
                                Text(String(localized: "All features unlocked for testing"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    } else if revenueCatManager.isSubscriptionActive {
                        // Production with active subscription
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.irSuccess)
                            Text(String(localized: "Active subscription"))
                            Spacer()
                        }

                        Button(String(localized: "Manage subscription")) {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                UIApplication.shared.open(url)
                            }
                        }
                    } else {
                        // Production without subscription - show subscribe button
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(Color.irWarning)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(String(localized: "Unlock Premium"))
                                        .font(.headline)
                                    Text(String(localized: "Access all features"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Button(String(localized: "Restore Purchases")) {
                            Task {
                                do {
                                    try await revenueCatManager.restorePurchases()
                                } catch {
                                    print("Error restoring purchases: \(error.localizedDescription)")
                                }
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "Subscription"))
                } footer: {
                    if !revenueCatManager.hasAIAccess {
                        Text(String(localized: "Unlock full access to advanced AI analysis, personalized advice and more."))
                    }
                }

                // Appearance Section
                Section {
                    Picker(String(localized: "Appearance"), selection: Bindable(themeManager).selectedTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Label(theme.rawValue, systemImage: theme.icon)
                                .tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: themeManager.selectedTheme) { oldValue, newValue in
                        AnalyticsService.shared.trackSettingsAppearanceChanged(
                            oldTheme: oldValue.rawValue,
                            newTheme: newValue.rawValue
                        )
                    }
                } header: {
                    Text(String(localized: "Appearance"))
                } footer: {
                    Text(String(localized: "Choose the app theme. System mode automatically adapts to your iOS settings."))
                }

                // Notifications Section
                Section {
                    Toggle(isOn: $notificationsEnabled) {
                        HStack {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(Color.irPrimaryAccent)
                            Text(String(localized: "Enable Notifications", comment: "Master notification toggle"))
                        }
                    }
                    .onChange(of: notificationsEnabled) { _, newValue in
                        if newValue {
                            Task {
                                let granted = await notificationManager.requestPermissions()
                                if !granted {
                                    notificationsEnabled = false
                                }
                            }
                        } else {
                            notificationManager.removeAllPendingNotifications()
                        }
                    }

                    if notificationsEnabled {
                        Toggle(isOn: Binding(
                            get: { notificationManager.isDailyReadinessEnabled },
                            set: { enabled in
                                if enabled {
                                    // Schedule with current saved time, will auto-update from wake-up on next launch
                                    notificationManager.scheduleDailyReadinessCheck(
                                        hour: notificationManager.savedReadinessHour,
                                        minute: notificationManager.savedReadinessMinute
                                    )
                                    Task {
                                        await notificationManager.updateDailyReadinessFromWakeUp()
                                    }
                                } else {
                                    notificationManager.cancelDailyReadinessCheck()
                                }
                            }
                        )) {
                            Text(String(localized: "Daily Readiness", comment: "Daily readiness notification toggle"))
                        }

                        if notificationManager.isDailyReadinessEnabled {
                            HStack {
                                Image(systemName: "alarm.fill")
                                    .foregroundStyle(.secondary)
                                Text(String(localized: "30 min after wake-up", comment: "Auto wake-up notification schedule"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%d:%02d", notificationManager.savedReadinessHour, notificationManager.savedReadinessMinute))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Toggle(isOn: Binding(
                            get: { notificationManager.isWeeklySummaryEnabled },
                            set: { enabled in
                                if enabled {
                                    notificationManager.scheduleWeeklySummary()
                                } else {
                                    notificationManager.cancelWeeklySummary()
                                }
                            }
                        )) {
                            Text(String(localized: "Weekly Summary", comment: "Weekly summary notification toggle"))
                        }

                        if notificationManager.isWeeklySummaryEnabled {
                            HStack {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.secondary)
                                Text(String(localized: "Sunday at 6:00 PM", comment: "Weekly summary schedule"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "Notifications", comment: "Notifications section header"))
                } footer: {
                    Text(String(localized: "Receive daily readiness reminders, weekly training summaries, and proactive coaching alerts.", comment: "Notifications section footer"))
                }

                // Medical Information Section
                Section {
                    Button {
                        showingMedicalSources = true
                        AnalyticsService.shared.trackSettingsMedicalSourcesViewed()
                    } label: {
                        HStack {
                            Image(systemName: "book.closed.fill")
                                .foregroundStyle(Color.irPrimaryAccent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "Medical Sources", comment: "Medical sources settings button"))
                                    .font(.body)
                                    .foregroundStyle(Color.irTextPrimary)
                                Text(String(localized: "View scientific references", comment: "Medical sources subtitle"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text(String(localized: "Medical Information", comment: "Medical information section header"))
                } footer: {
                    Text(String(localized: "Health metrics and recovery recommendations are based on published scientific research. Tap to view all sources.", comment: "Medical information footer"))
                }

                // Training Data Section
                Section {
                    if let summary = HistoricalSummaryStorage.shared.load() {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.irSuccess)
                                Text("\(summary.workoutCount) " + String(localized: "workouts indexed", comment: "Number of indexed workouts"))
                                    .font(.body)
                            }

                            Text(String(localized: "Last updated:", comment: "Last update label") + " \(formatDate(summary.indexedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            // Refresh indicator
                            let days = HistoricalSummaryStorage.shared.daysUntilRefresh()
                            if days > 0 {
                                Text(String(localized: "Next update in", comment: "Next update prefix") + " \(days) " + String(localized: "days", comment: "days unit"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(String(localized: "Update recommended", comment: "Update recommended message"))
                                    .font(.caption)
                                    .foregroundStyle(Color.irWarning)
                            }
                        }

                        // Refresh button
                        Button {
                            showRefreshSheet = true
                            AnalyticsService.shared.trackSettingsRefreshDataClicked()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text(String(localized: "Refresh data", comment: "Refresh data button"))
                            }
                        }
                        .disabled(!HistoricalSummaryStorage.shared.canManualRefresh())

                        if !HistoricalSummaryStorage.shared.canManualRefresh() {
                            Text(String(localized: "Available 1 month after last update", comment: "Refresh cooldown message"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading) {
                            HStack {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(Color.irWarning)
                                Text(String(localized: "No data indexed", comment: "No indexed data message"))
                                    .font(.body)
                            }

                            Button {
                                showRefreshSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text(String(localized: "Index now", comment: "Index now button"))
                                }
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "Training Data", comment: "Training data section header"))
                }

                // Strava Integration Section (conditionally shown based on feature flag)
                if remoteConfig.isFeatureEnabled(.strava) {
                    Section {
                        if stravaAuth.isAuthenticated {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.irSuccess)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(String(localized: "Strava Connected"))
                                            .font(.headline)
                                        if let syncResult = lastSyncResult {
                                            Text(syncResult)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text(String(localized: "Activities syncing automatically"))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }

                                // Powered by Strava logo (per Brand Guidelines)
                                PoweredByStravaLogo(variant: .orange)
                                    .frame(height: 20)
                            }

                            Button {
                                syncStravaActivities()
                            } label: {
                                HStack {
                                    if isSyncing {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    Text(String(localized: "Sync Now"))
                                }
                            }
                            .disabled(isSyncing)

                            Button(role: .destructive) {
                                Task {
                                    // Clear Strava cache
                                    try? StravaCache.shared.clearAll()
                                    print("🗑️  Cleared Strava cache")

                                    // Clear Strava-related unified workouts (strava-only + merged)
                                    try? UnifiedWorkoutCache.shared.clearStravaWorkouts()
                                    print("🗑️  Cleared Strava unified workouts")

                                    // Logout (calls backend cleanup + clears local tokens)
                                    await stravaAuth.logout()

                                    // Track disconnection
                                    AnalyticsService.shared.trackStravaDisconnected()
                                }
                            } label: {
                                Text(String(localized: "Disconnect"))
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
                        }
                    } header: {
                        Text(String(localized: "Integrations"))
                    }
                }

                // Apple Health Section
                Section {
                    Button {
                        Task {
                            do {
                                try await HealthKitManager.shared.requestAuthorization()
                                print("✅ HealthKit authorization requested")
                            } catch {
                                print("❌ HealthKit authorization failed: \(error)")
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "heart.text.square")
                                .foregroundStyle(.pink)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(String(localized: "Health Permissions"))
                                    .font(.body)
                                    .foregroundStyle(Color.irTextPrimary)
                                Text(String(localized: "Manage read and write access"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text(String(localized: "Apple Health"))
                } footer: {
                    Text(String(localized: "Grant write access to save imported workouts to the Health app."))
                }

                // Debug Section (for testing)
                #if DEBUG
                Section {
                    // Environment simulation
                    Button(String(localized: "Simuler TestFlight")) {
                        revenueCatManager.debugTestFlightOverride = true
                    }
                    .foregroundStyle(Color.irPrimaryAccent)

                    Button(String(localized: "Simuler Production")) {
                        revenueCatManager.debugTestFlightOverride = false
                    }
                    .foregroundStyle(.indigo)

                    Button(String(localized: "Reset environnement")) {
                        revenueCatManager.debugTestFlightOverride = nil
                    }
                    .foregroundStyle(.gray)

                    // Subscription simulation
                    Button(String(localized: "Simuler non-abonné")) {
                        revenueCatManager.debugTestFlightOverride = false
                        revenueCatManager.isSubscriptionActive = false
                    }
                    .foregroundStyle(.red)

                    Button(String(localized: "Simuler abonné")) {
                        revenueCatManager.debugTestFlightOverride = false
                        revenueCatManager.isSubscriptionActive = true
                    }
                    .foregroundStyle(Color.irSuccess)

                    // Paywall & Onboarding
                    Button(String(localized: "Afficher paywall")) {
                        showPaywall = true
                    }
                    .foregroundStyle(Color.irPrimaryAccent)

                    Button(String(localized: "Réinitialiser le paywall")) {
                        UserDefaults.standard.removeObject(forKey: "hasSeenInitialPaywall")
                        revenueCatManager.hasSeenInitialPaywall = false
                    }
                    .foregroundStyle(Color.irWarning)

                    Button(String(localized: "Réinitialiser l'onboarding")) {
                        OnboardingManager.shared.resetOnboarding()
                    }
                    .foregroundStyle(.purple)

                    // Data management
                    Button(String(localized: "Delete LLM History", comment: "Debug button to clear historical summary storage")) {
                        HistoricalSummaryStorage.shared.clear()
                    }
                    .foregroundStyle(Color.irError)

                    Button(String(localized: "Réinitialiser consentement IA")) {
                        ConsentService.shared.resetConsentState()
                    }
                    .foregroundStyle(Color.irError)
                } header: {
                    Text(String(localized: "Debug"))
                } footer: {
                    Text(String(localized: "Outils de test pour simuler différents états d'abonnement. Redémarrez l'app après avoir réinitialisé."))
                }
                #endif

                // App Information Section
                Section {
                    HStack {
                        Text(String(localized: "Version", comment: "Label for app version"))
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text(String(localized: "Build", comment: "Label for app build number"))
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "N/A")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(String(localized: "About", comment: "Section header for app information"))
                }
            }
            .navigationTitle(String(localized: "Settings", comment: "Navigation title for settings view"))
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
        }
    }

    // MARK: - Helper Methods

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

    /// Format date for display in settings
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
