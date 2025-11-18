# Plan d'intégration Strava - InsightRun

## 📋 Vue d'ensemble

### Objectif
**Importer les workouts running de Strava vers InsightRun** pour enrichir les données disponibles en complément de HealthKit.

### Architecture cible
- **Strava = source de données supplémentaire** (en plus de HealthKit)
- **Objectif** : Récupérer les activités running de Strava et les afficher dans InsightRun
- **Stockage** : SwiftData pour persister les workouts Strava localement
- **AI** : Analyser les workouts Strava avec l'AI existante

---

## 🎯 Étapes d'implémentation

### **Phase 1 : Configuration Strava API**

#### 1. Créer une application Strava
- URL : https://www.strava.com/settings/api
- Obtenir Client ID et Client Secret
- Configurer les URLs de redirection OAuth
  - Format : `insightrun://strava/callback`
  - Pour dev : `http://localhost:8787/api/strava/auth/callback`

#### 2. Permissions requises
- `read` : Lire les informations du profil
- `activity:read` : Lire les activités
- `activity:read_all` : Lire toutes les activités (y compris privées)

---

### **Phase 2 : Backend - OAuth & API Proxy**

#### 3. Endpoints OAuth (Cloudflare Workers)
```typescript
// /api/strava/auth/callback
POST /api/strava/auth/callback
Body: { code: string, userId: string }
Response: { access_token, refresh_token, expires_at, athlete }

// /api/strava/auth/refresh
POST /api/strava/auth/refresh
Headers: X-User-ID
Body: { refresh_token: string }
Response: { access_token, refresh_token, expires_at }
```

#### 4. Endpoints Strava Data
```typescript
// Liste des activités
GET /api/strava/activities
Headers: X-User-ID, X-Access-Token
Query: ?page=1&per_page=30&after=timestamp&before=timestamp
Response: StravaActivity[]

// Détails d'une activité
GET /api/strava/activities/:id
Headers: X-User-ID, X-Access-Token
Response: StravaDetailedActivity

// Streams (données détaillées : GPS, HR, etc.)
GET /api/strava/activities/:id/streams
Headers: X-User-ID, X-Access-Token
Query: ?keys=time,latlng,heartrate,cadence,watts,altitude
Response: StravaStreams
```

#### 5. Sécurité Backend
- Client Secret stocké dans Cloudflare Secrets (jamais dans l'app)
- Rate limiting par user
- Validation des tokens
- Proxy pour cacher les credentials

#### 6. Storage (Cloudflare KV)
```typescript
// Stockage des tokens par user
KV Key: `strava:tokens:${userId}`
Value: { access_token, refresh_token, expires_at, athlete_id }
```

---

### **Phase 3 : iOS - Modèles de données**

#### 7. StravaActivity.swift (SwiftData Model)
```swift
@Model
class StravaActivity {
    @Attribute(.unique) var stravaID: Int64
    var name: String
    var activityType: String  // "Run", "Race", etc.
    var startDate: Date
    var timezone: String

    // Metrics basiques
    var distance: Double  // mètres
    var movingTime: TimeInterval  // secondes
    var elapsedTime: TimeInterval

    // Performance
    var averageSpeed: Double?  // m/s
    var maxSpeed: Double?
    var averagePace: Double?  // min/km
    var elevationGain: Double?
    var elevationLoss: Double?

    // Heart rate
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var hasHeartRate: Bool

    // Autres
    var calories: Double?
    var averageCadence: Double?
    var averageWatts: Double?

    // Metadata
    var mapPolyline: String?  // Encoded polyline
    var stravaURL: String?
    var kudosCount: Int?
    var achievementCount: Int?

    // Sync
    var lastSyncDate: Date
    var detailedDataFetched: Bool = false

    init(stravaID: Int64, name: String, ...) { ... }
}
```

#### 8. StravaDetailedMetrics.swift
```swift
struct StravaDetailedMetrics {
    let activityID: Int64

    // Route GPS
    var routePoints: [StravaRoutePoint]

    // Time series data
    var heartRateSamples: [TimedValue<Double>]
    var cadenceSamples: [TimedValue<Double>]
    var powerSamples: [TimedValue<Double>]
    var altitudeSamples: [TimedValue<Double>]
    var speedSamples: [TimedValue<Double>]

    // Splits (calculés côté client)
    var splits: [Split]

    // Heart rate zones
    var heartRateZones: HeartRateZones?
}

struct StravaRoutePoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let altitude: Double?
    let timestamp: Date
    let distance: Double  // Distance cumulée
}

struct TimedValue<T> {
    let value: T
    let timestamp: Date
    let distance: Double?
}
```

#### 9. StravaAuthToken.swift
```swift
struct StravaAuthToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let athleteID: Int64
    let scope: String

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var needsRefresh: Bool {
        // Refresh 1h avant expiration
        Date().addingTimeInterval(3600) >= expiresAt
    }
}

struct StravaAthlete: Codable {
    let id: Int64
    let username: String?
    let firstname: String
    let lastname: String
    let profile: String?  // Photo URL
}
```

---

### **Phase 4 : iOS - Services**

#### 10. StravaManager.swift
```swift
@MainActor
class StravaManager: ObservableObject {
    static let shared = StravaManager()

    @Published var isAuthenticated: Bool = false
    @Published var currentAthlete: StravaAthlete?
    @Published var lastSyncDate: Date?

    private let apiClient: StravaAPIClient
    private let keychainManager: StravaKeychainManager

    // OAuth
    func authenticate() async throws -> StravaAuthToken
    func refreshTokenIfNeeded() async throws
    func disconnect() async

    // Sync
    func syncActivities(since: Date?) async throws -> [StravaActivity]
    func fetchDetailedMetrics(for activityID: Int64) async throws -> StravaDetailedMetrics

    // Token management
    private func storeToken(_ token: StravaAuthToken)
    private func loadToken() -> StravaAuthToken?
    private func clearToken()
}
```

#### 11. StravaAPIClient.swift
```swift
class StravaAPIClient {
    private let backendURL: URL
    private let userID: String

    // Auth
    func exchangeCode(_ code: String) async throws -> StravaAuthToken
    func refreshToken(_ refreshToken: String) async throws -> StravaAuthToken

    // Activities
    func fetchActivities(
        page: Int,
        perPage: Int,
        after: Date?,
        before: Date?
    ) async throws -> [StravaActivityResponse]

    func fetchActivityDetail(_ id: Int64) async throws -> StravaDetailedActivityResponse

    func fetchActivityStreams(
        _ id: Int64,
        keys: [StreamType]
    ) async throws -> StravaStreamsResponse

    enum StreamType: String {
        case time, latlng, distance, altitude
        case heartrate, cadence, watts, temp
    }
}
```

#### 12. StravaSyncService.swift
```swift
@MainActor
class StravaSyncService: ObservableObject {
    @Published var isSyncing: Bool = false
    @Published var syncProgress: Double = 0.0
    @Published var lastError: Error?

    private let modelContext: ModelContext
    private let stravaManager: StravaManager

    // Initial sync (toutes les activités)
    func performInitialSync() async throws -> Int

    // Incremental sync (nouvelles activités)
    func performIncrementalSync() async throws -> Int

    // Fetch detailed data for activity
    func fetchDetailedData(for activity: StravaActivity) async throws

    // Background sync
    func scheduleBackgroundSync()
    func performBackgroundSync() async throws

    // Helpers
    private func convertToStravaActivity(_ response: StravaActivityResponse) -> StravaActivity
    private func detectDuplicates(_ activity: StravaActivity) -> [WorkoutModel]
}
```

#### 13. StravaKeychainManager.swift
```swift
class StravaKeychainManager {
    private let service = "com.insightrun.strava"

    func saveToken(_ token: StravaAuthToken) throws
    func loadToken() throws -> StravaAuthToken?
    func deleteToken() throws

    private func save(_ data: Data, forKey key: String) throws
    private func load(key: String) throws -> Data?
    private func delete(key: String) throws
}
```

---

### **Phase 5 : iOS - Modèle de données unifié**

#### 14. WorkoutSource enum
```swift
enum WorkoutSource: String, Codable {
    case healthKit
    case strava

    var displayName: String {
        switch self {
        case .healthKit: return "Apple Health"
        case .strava: return "Strava"
        }
    }

    var icon: String {
        switch self {
        case .healthKit: return "heart.fill"
        case .strava: return "figure.run"
        }
    }
}
```

#### 15. UnifiedWorkout (Protocol ou Wrapper)
```swift
protocol UnifiedWorkout {
    var id: String { get }
    var source: WorkoutSource { get }
    var workoutType: String { get }
    var startDate: Date { get }
    var endDate: Date { get }
    var duration: TimeInterval { get }
    var distance: Double? { get }
    var averagePace: Double? { get }
    var hasDetailedMetrics: Bool { get }
}

// Extension pour WorkoutModel
extension WorkoutModel: UnifiedWorkout {
    var source: WorkoutSource { .healthKit }
    // ...
}

// Extension pour StravaActivity
extension StravaActivity: UnifiedWorkout {
    var source: WorkoutSource { .strava }
    var endDate: Date { startDate.addingTimeInterval(elapsedTime) }
    // ...
}
```

#### 16. Adapter les ViewModels
```swift
@MainActor
class WorkoutListViewModel: ObservableObject {
    @Published var healthKitWorkouts: [WorkoutModel] = []
    @Published var stravaActivities: [StravaActivity] = []
    @Published var selectedSource: WorkoutSource? = nil  // Filter

    var allWorkouts: [any UnifiedWorkout] {
        let all: [any UnifiedWorkout] = healthKitWorkouts + stravaActivities
        return all.sorted { $0.startDate > $1.startDate }
    }

    var filteredWorkouts: [any UnifiedWorkout] {
        guard let source = selectedSource else { return allWorkouts }
        return allWorkouts.filter { $0.source == source }
    }

    func loadStravaActivities() async {
        // Fetch from SwiftData
    }
}
```

---

### **Phase 6 : iOS - Interface Utilisateur**

#### 17. StravaConnectionView.swift
```swift
struct StravaConnectionView: View {
    @StateObject private var stravaManager = StravaManager.shared
    @StateObject private var syncService: StravaSyncService

    var body: some View {
        List {
            // Connection status
            Section("Connection") {
                if stravaManager.isAuthenticated {
                    ConnectedStatusRow()
                    DisconnectButton()
                } else {
                    ConnectButton()
                }
            }

            // Sync settings
            if stravaManager.isAuthenticated {
                Section("Synchronisation") {
                    LastSyncRow()
                    SyncNowButton()
                    Toggle("Sync automatique", isOn: $autoSync)
                }

                Section("Statistiques") {
                    StatRow(label: "Activités Strava", value: "\(activityCount)")
                }
            }
        }
    }
}
```

#### 18. Modifier WorkoutListView.swift
```swift
struct WorkoutListView: View {
    @StateObject private var viewModel: WorkoutListViewModel

    var body: some View {
        List {
            // Source filter
            Picker("Source", selection: $viewModel.selectedSource) {
                Text("Toutes").tag(nil as WorkoutSource?)
                Text("Apple Health").tag(WorkoutSource.healthKit as WorkoutSource?)
                Text("Strava").tag(WorkoutSource.strava as WorkoutSource?)
            }
            .pickerStyle(.segmented)

            // Workouts
            ForEach(viewModel.filteredWorkouts) { workout in
                WorkoutRowView(workout: workout)
                    .badge(workout.source.icon)  // Icône source
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}
```

#### 19. Modifier WorkoutDetailView.swift
```swift
struct WorkoutDetailView: View {
    let workout: any UnifiedWorkout

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Source badge
                SourceBadge(source: workout.source)

                // Métriques communes
                MetricsSection(workout: workout)

                // Source-specific sections
                if let stravaActivity = workout as? StravaActivity {
                    StravaSpecificSection(activity: stravaActivity)

                    // Lien vers Strava
                    if let url = stravaActivity.stravaURL {
                        Link("Voir sur Strava", destination: URL(string: url)!)
                    }
                }

                // Route map (si disponible)
                if workout.hasDetailedMetrics {
                    RouteMapView(...)
                }
            }
        }
    }
}
```

#### 20. Ajouter dans SettingsView
```swift
struct SettingsView: View {
    var body: some View {
        List {
            // ... sections existantes ...

            Section("Intégrations") {
                NavigationLink("Strava") {
                    StravaConnectionView()
                }
            }
        }
    }
}
```

---

### **Phase 7 : Synchronisation & Performance**

#### 21. Background Sync
```swift
// AppDelegate ou App extension
extension InsightRunApp {
    func scheduleBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.insightrun.strava.sync",
            using: nil
        ) { task in
            await handleStravaSync(task: task as! BGAppRefreshTask)
        }
    }

    func handleStravaSync(task: BGAppRefreshTask) async {
        let syncService = StravaSyncService(...)

        do {
            let count = try await syncService.performIncrementalSync()
            print("✅ Synced \(count) new activities")
            task.setTaskCompleted(success: true)
        } catch {
            print("❌ Sync failed: \(error)")
            task.setTaskCompleted(success: false)
        }

        // Schedule next sync
        scheduleNextSync()
    }
}
```

#### 22. Mapping détaillé Strava → InsightRun
```swift
extension StravaSyncService {
    func convertStreamsToDetailedMetrics(
        _ streams: StravaStreamsResponse,
        for activity: StravaActivity
    ) -> StravaDetailedMetrics {

        // GPS Route
        let routePoints = zipStreams(
            time: streams.time,
            latlng: streams.latlng,
            altitude: streams.altitude,
            distance: streams.distance
        ).map { StravaRoutePoint(...) }

        // Heart rate
        let heartRateSamples = zipStreams(
            time: streams.time,
            values: streams.heartrate
        ).map { TimedValue(...) }

        // Calculate splits (1km intervals)
        let splits = calculateSplits(
            from: routePoints,
            heartRate: heartRateSamples,
            power: powerSamples
        )

        return StravaDetailedMetrics(
            activityID: activity.stravaID,
            routePoints: routePoints,
            heartRateSamples: heartRateSamples,
            // ...
            splits: splits
        )
    }

    func calculateSplits(
        from routePoints: [StravaRoutePoint],
        heartRate: [TimedValue<Double>],
        power: [TimedValue<Double>]?
    ) -> [Split] {
        // Regrouper par km
        var splits: [Split] = []
        var currentKm = 0
        var kmStart = 0

        for (index, point) in routePoints.enumerated() {
            let distanceKm = point.distance / 1000.0
            if distanceKm >= Double(currentKm + 1) {
                let split = createSplit(
                    km: currentKm,
                    points: Array(routePoints[kmStart..<index]),
                    heartRate: heartRate,
                    power: power
                )
                splits.append(split)
                currentKm += 1
                kmStart = index
            }
        }

        return splits
    }
}
```

#### 23. Gestion des doublons
```swift
extension StravaSyncService {
    func detectDuplicates(_ stravaActivity: StravaActivity) async -> [WorkoutModel] {
        // Chercher dans HealthKit
        let healthKitWorkouts = try? await HealthKitManager.shared.fetchRunningWorkouts()

        // Critères de match :
        // - Même date (± 5 minutes)
        // - Distance similaire (± 100m)
        // - Durée similaire (± 30s)

        let matches = healthKitWorkouts?.filter { workout in
            let timeDiff = abs(workout.startDate.timeIntervalSince(stravaActivity.startDate))
            let distanceDiff = abs((workout.distance ?? 0) - stravaActivity.distance)
            let durationDiff = abs(workout.duration - stravaActivity.movingTime)

            return timeDiff < 300 &&  // 5 min
                   distanceDiff < 100 &&  // 100m
                   durationDiff < 30  // 30s
        }

        return matches ?? []
    }

    func handleDuplicate(
        strava: StravaActivity,
        healthKit: WorkoutModel,
        strategy: DuplicateStrategy
    ) {
        switch strategy {
        case .keepBoth:
            // Marquer comme duplicata mais garder les 2
            strava.isDuplicate = true
            strava.duplicateSourceID = healthKit.id.uuidString

        case .preferStrava:
            // Masquer le workout HealthKit
            healthKit.isHidden = true

        case .preferHealthKit:
            // Ne pas importer l'activité Strava
            return

        case .merge:
            // Créer un merged workout (complexe)
            // Prendre GPS de Strava, HR de HealthKit (si meilleur)
            break
        }
    }
}

enum DuplicateStrategy {
    case keepBoth
    case preferStrava
    case preferHealthKit
    case merge
}
```

---

### **Phase 8 : AI Integration**

#### 24. Intégrer Strava dans l'AI
```swift
// Modifier BackendAPIClient.swift
extension BackendAPIClient {
    func generateWorkout(
        userInput: String,
        healthProfile: HealthProfile,
        historicalSummary: HistoricalSummary,
        stravaActivities: [StravaActivitySummary]?  // NOUVEAU
    ) async throws -> AIGeneratedWorkout {

        var context = buildContext(
            profile: healthProfile,
            summary: historicalSummary
        )

        // Ajouter contexte Strava
        if let strava = stravaActivities, !strava.isEmpty {
            context += "\n\nActivités Strava récentes:\n"
            context += strava.map { activity in
                "- \(activity.date): \(activity.distance)km en \(activity.duration)"
            }.joined(separator: "\n")
        }

        // ...
    }
}

// Modifier WorkoutAIService.swift
extension WorkoutAIService {
    func getHistoricalContext() async -> String {
        var context = ""

        // HealthKit context (existant)
        context += await getHealthKitContext()

        // Strava context (nouveau)
        context += await getStravaContext()

        return context
    }

    private func getStravaContext() async -> String {
        let activities = try? await fetchRecentStravaActivities(limit: 10)
        guard let activities = activities, !activities.isEmpty else {
            return ""
        }

        var context = "\n\n### Activités Strava récentes:\n"
        for activity in activities {
            context += """
            - \(activity.startDate.formatted()): \(activity.name)
              Distance: \(activity.distance/1000)km
              Temps: \(formatDuration(activity.movingTime))
              Allure: \(activity.averagePace ?? 0) min/km
              FC moy: \(activity.averageHeartRate ?? 0) bpm

            """
        }

        return context
    }
}
```

---

### **Phase 9 : Tests & Polish**

#### 25. Tests unitaires
```swift
// Tests/StravaManagerTests.swift
class StravaManagerTests: XCTestCase {
    func testTokenRefresh() async throws {
        // Mock token expiré
        let expiredToken = StravaAuthToken(...)

        // Refresh
        let newToken = try await stravaManager.refreshToken(expiredToken.refreshToken)

        // Vérifier
        XCTAssertFalse(newToken.isExpired)
        XCTAssertNotEqual(newToken.accessToken, expiredToken.accessToken)
    }

    func testActivitySync() async throws {
        // Mock API response
        let activities = try await syncService.performIncrementalSync()

        XCTAssertGreaterThan(activities, 0)
    }
}
```

#### 26. Tests d'intégration
- OAuth flow complet
- Import de 100+ activités
- Gestion des erreurs réseau (retry)
- Token expiration & refresh
- Duplicate detection
- Background sync

#### 27. Localisation
```swift
// Localizable.xcstrings - Ajouter :
{
  "strava.connect" : {
    "en" : "Connect to Strava",
    "fr" : "Connecter à Strava"
  },
  "strava.connected" : {
    "en" : "Connected to Strava",
    "fr" : "Connecté à Strava"
  },
  "strava.sync.success" : {
    "en" : "Synced %d activities",
    "fr" : "%d activités synchronisées"
  },
  "strava.error.auth" : {
    "en" : "Failed to authenticate with Strava",
    "fr" : "Échec de l'authentification Strava"
  }
  // ... etc
}
```

---

## 📊 Ordre d'implémentation recommandé

### **Sprint 1 : OAuth + Basic Fetch** (2-3 jours)
- Étapes 1-13
- Connexion à Strava fonctionnelle
- Récupération de la liste des activités
- Stockage basique en SwiftData
- Affichage dans une liste séparée (test)

**Livrable** : Pouvoir se connecter à Strava et voir la liste des runs

---

### **Sprint 2 : Detailed Data + Unified UI** (3-4 jours)
- Étapes 14-20
- Récupération des streams détaillés (GPS, HR, etc.)
- Modèle unifié HealthKit + Strava
- Intégration dans WorkoutListView
- Détails dans WorkoutDetailView
- UI complète avec filtres et badges

**Livrable** : Voir les workouts Strava avec les mêmes détails que HealthKit

---

### **Sprint 3 : Sync & Performance** (2-3 jours)
- Étapes 21-23
- Sync automatique en background
- Gestion des doublons
- Cache et optimisation
- Calcul des splits
- Gestion d'erreurs robuste

**Livrable** : Synchronisation automatique et détection de doublons

---

### **Sprint 4 : AI Integration & Polish** (2 jours)
- Étapes 24-27
- Intégration dans l'AI
- Tests complets
- Localisation FR/EN
- Documentation utilisateur
- Analytics

**Livrable** : Feature complète et prête pour production

---

## 🔧 Configuration requise

### Backend (Cloudflare)
```bash
# Variables d'environnement
STRAVA_CLIENT_ID=xxxxx
STRAVA_CLIENT_SECRET=xxxxx
STRAVA_REDIRECT_URI=insightrun://strava/callback
```

### iOS
```swift
// Info.plist - URL Scheme
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>insightrun</string>
        </array>
    </dict>
</array>

// Strava URL handling
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>strava</string>
</array>
```

### Entitlements
```xml
<!-- insightrun.entitlements -->
<!-- Ajouter si besoin de background sync -->
<key>com.apple.developer.healthkit.background-delivery</key>
<true/>
```

---

## 🎨 Design Notes

### Icônes & Couleurs
- **Couleur Strava** : `#FC4C02` (orange)
- **Icône Strava** : SF Symbol `figure.run` ou custom logo
- **Badge source** : Petit indicateur discret sur WorkoutRowView

### UX
- Connexion OAuth : Modal ASWebAuthenticationSession
- First sync : Progress bar avec nombre d'activités
- Incremental sync : Pull to refresh ou automatique
- Erreurs : Alerts avec retry button

---

## 🚀 API Strava - Référence

### Rate Limits
- **600 requests per 15 minutes**
- **30,000 requests per day**
→ Implémenter retry avec exponential backoff

### Endpoints utilisés
```
GET /api/v3/athlete
GET /api/v3/athlete/activities
GET /api/v3/activities/:id
GET /api/v3/activities/:id/streams
```

### Scopes OAuth
```
read,activity:read_all
```

---

## ✅ Checklist finale avant release

- [ ] OAuth flow complet testé
- [ ] Import initial de 100+ activités
- [ ] Sync incrémentale fonctionnelle
- [ ] Gestion des doublons implémentée
- [ ] UI responsive et accessible
- [ ] Localisation FR/EN complète
- [ ] Tests unitaires passent
- [ ] Tests d'intégration passent
- [ ] Documentation utilisateur
- [ ] Analytics configurés
- [ ] Rate limiting respecté
- [ ] Gestion d'erreurs robuste
- [ ] Background sync testé
- [ ] AI integration fonctionnelle

---

## 📝 Notes supplémentaires

### Limitations connues
- Strava API ne donne pas accès à certaines métriques premium (Suffer Score, etc.)
- Rate limits peuvent ralentir l'import initial
- Pas de webhook Strava → sync périodique nécessaire

### Améliorations futures
- Upload vers Strava (bidirectionnel)
- Sync des segments Strava
- Comparaison avec KOMs/PRs
- Social features (kudos, comments)
- Strava Clubs integration

---

**Date de création** : 2025-11-18
**Auteur** : Claude
**Version** : 1.0
