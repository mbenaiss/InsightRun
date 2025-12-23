//
//  SuuntoImportService.swift
//  InsightRun
//
//  Service for importing Suunto JSON exports and matching with HealthKit
//

import Foundation
import SwiftData
import HealthKit
import Combine

// MARK: - Import Result

enum SuuntoImportResult {
    case created(ParsedSuuntoWorkout)
    case enriched(existingWorkout: WorkoutModel, suuntoData: ParsedSuuntoWorkout)
    case alreadyExists(ParsedSuuntoWorkout)
}

enum SuuntoImportError: Error, LocalizedError {
    case fileReadError(Error)
    case parseError(Error)
    case healthKitNotAvailable
    case saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .fileReadError(let error):
            return "Could not read file: \(error.localizedDescription)"
        case .parseError(let error):
            return "Could not parse Suunto data: \(error.localizedDescription)"
        case .healthKitNotAvailable:
            return "HealthKit is not available"
        case .saveFailed(let error):
            return "Could not save workout: \(error.localizedDescription)"
        }
    }
}

// MARK: - SwiftData Model for Cached Suunto Workouts

@Model
final class CachedSuuntoWorkout {
    @Attribute(.unique) var id: String // Based on start date + duration
    var startDate: Date
    var endDate: Date
    var duration: Double
    var distance: Double
    var calories: Double
    var elevationGain: Double
    var elevationLoss: Double

    // Heart rate
    var averageHeartRate: Double?
    var maxHeartRate: Double?

    // Speed
    var averageSpeed: Double?
    var maxSpeed: Double?

    // Running dynamics
    var averageGroundContactTime: Double?
    var averageVerticalOscillation: Double?
    var averageStrideLength: Double?
    var averageCadence: Double?
    var averagePower: Double?

    // Advanced metrics
    var vo2Max: Double?
    var epoc: Double?
    var trainingEffect: Double?

    // Route (stored as JSON)
    var routeCoordinatesJSON: Data?
    var hasRoute: Bool

    // Samples (stored as JSON for efficiency)
    var heartRateSamplesJSON: Data?
    var cadenceSamplesJSON: Data?
    var powerSamplesJSON: Data?

    // Splits (stored as JSON)
    var splitsJSON: Data?

    // Metadata
    var deviceName: String
    var activityType: String
    var feeling: Int?
    var notes: String?

    // Import metadata
    var importedAt: Date
    var sourceFileName: String?

    init(from parsed: ParsedSuuntoWorkout, fileName: String? = nil) {
        // Create unique ID from start date + duration
        self.id = "\(parsed.startDate.timeIntervalSince1970)-\(parsed.duration)"

        self.startDate = parsed.startDate
        self.endDate = parsed.endDate
        self.duration = parsed.duration
        self.distance = parsed.distance
        self.calories = parsed.calories
        self.elevationGain = parsed.elevationGain
        self.elevationLoss = parsed.elevationLoss

        self.averageHeartRate = parsed.averageHeartRate
        self.maxHeartRate = parsed.maxHeartRate
        self.averageSpeed = parsed.averageSpeed
        self.maxSpeed = parsed.maxSpeed

        self.averageGroundContactTime = parsed.averageGroundContactTime
        self.averageVerticalOscillation = parsed.averageVerticalOscillation
        self.averageStrideLength = parsed.averageStrideLength
        self.averageCadence = parsed.averageCadence
        self.averagePower = parsed.averagePower

        self.vo2Max = parsed.vo2Max
        self.epoc = parsed.epoc
        self.trainingEffect = parsed.trainingEffect

        self.hasRoute = parsed.hasRoute
        self.deviceName = parsed.deviceName
        self.activityType = parsed.activityType
        self.feeling = parsed.feeling
        self.notes = parsed.notes

        self.importedAt = Date()
        self.sourceFileName = fileName

        // Encode route coordinates
        if !parsed.routeCoordinates.isEmpty {
            let coords = parsed.routeCoordinates.map { ["lat": $0.latitude, "lon": $0.longitude] }
            self.routeCoordinatesJSON = try? JSONEncoder().encode(coords)
        }

        // Encode samples (limit to reduce storage)
        let maxSamples = 1000
        if !parsed.heartRateSamples.isEmpty {
            let samples = Array(parsed.heartRateSamples.prefix(maxSamples))
                .map { ["t": $0.date.timeIntervalSince1970, "v": $0.bpm] }
            self.heartRateSamplesJSON = try? JSONEncoder().encode(samples)
        }

        if !parsed.cadenceSamples.isEmpty {
            let samples = Array(parsed.cadenceSamples.prefix(maxSamples))
                .map { ["t": $0.date.timeIntervalSince1970, "v": $0.spm] }
            self.cadenceSamplesJSON = try? JSONEncoder().encode(samples)
        }

        if !parsed.powerSamples.isEmpty {
            let samples = Array(parsed.powerSamples.prefix(maxSamples))
                .map { ["t": $0.date.timeIntervalSince1970, "v": $0.watts] }
            self.powerSamplesJSON = try? JSONEncoder().encode(samples)
        }

        // Encode splits
        if !parsed.splits.isEmpty {
            let splitsData = parsed.splits.map { split -> [String: Any] in
                var dict: [String: Any] = [
                    "km": split.kilometer,
                    "time": split.time,
                    "pace": split.pace
                ]
                if let hr = split.averageHeartRate { dict["hr"] = hr }
                if let power = split.averagePower { dict["power"] = power }
                if let cadence = split.averageCadence { dict["cadence"] = cadence }
                if let elev = split.elevationGain { dict["elev"] = elev }
                return dict
            }
            self.splitsJSON = try? JSONSerialization.data(withJSONObject: splitsData)
        }
    }

    func toParsedWorkout() -> ParsedSuuntoWorkout {
        // Decode route coordinates
        var routeCoords: [CLLocationCoordinate2D] = []
        if let data = routeCoordinatesJSON,
           let coords = try? JSONDecoder().decode([[String: Double]].self, from: data) {
            routeCoords = coords.compactMap { dict in
                guard let lat = dict["lat"], let lon = dict["lon"] else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
        }

        // Decode samples
        var hrSamples: [(date: Date, bpm: Double)] = []
        if let data = heartRateSamplesJSON,
           let samples = try? JSONDecoder().decode([[String: Double]].self, from: data) {
            hrSamples = samples.compactMap { dict in
                guard let t = dict["t"], let v = dict["v"] else { return nil }
                return (date: Date(timeIntervalSince1970: t), bpm: v)
            }
        }

        var cadSamples: [(date: Date, spm: Double)] = []
        if let data = cadenceSamplesJSON,
           let samples = try? JSONDecoder().decode([[String: Double]].self, from: data) {
            cadSamples = samples.compactMap { dict in
                guard let t = dict["t"], let v = dict["v"] else { return nil }
                return (date: Date(timeIntervalSince1970: t), spm: v)
            }
        }

        var powSamples: [(date: Date, watts: Double)] = []
        if let data = powerSamplesJSON,
           let samples = try? JSONDecoder().decode([[String: Double]].self, from: data) {
            powSamples = samples.compactMap { dict in
                guard let t = dict["t"], let v = dict["v"] else { return nil }
                return (date: Date(timeIntervalSince1970: t), watts: v)
            }
        }

        // Decode splits
        var splits: [SuuntoSplit] = []
        if let data = splitsJSON,
           let splitsArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            splits = splitsArray.compactMap { dict in
                guard let km = dict["km"] as? Int,
                      let time = dict["time"] as? Double,
                      let pace = dict["pace"] as? Double else { return nil }
                return SuuntoSplit(
                    kilometer: km,
                    time: time,
                    pace: pace,
                    averageHeartRate: dict["hr"] as? Double,
                    averagePower: dict["power"] as? Double,
                    averageCadence: dict["cadence"] as? Double,
                    elevationGain: dict["elev"] as? Double
                )
            }
        }

        return ParsedSuuntoWorkout(
            startDate: startDate,
            endDate: endDate,
            duration: duration,
            distance: distance,
            calories: calories,
            elevationGain: elevationGain,
            elevationLoss: elevationLoss,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            averageGroundContactTime: averageGroundContactTime,
            averageVerticalOscillation: averageVerticalOscillation,
            averageStrideLength: averageStrideLength,
            averageCadence: averageCadence,
            averagePower: averagePower,
            vo2Max: vo2Max,
            epoc: epoc,
            trainingEffect: trainingEffect,
            routeCoordinates: routeCoords,
            hasRoute: hasRoute,
            heartRateSamples: hrSamples,
            cadenceSamples: cadSamples,
            powerSamples: powSamples,
            altitudeSamples: [],
            splits: splits,
            deviceName: deviceName,
            activityType: activityType,
            feeling: feeling,
            notes: notes
        )
    }
}

import CoreLocation

// MARK: - Import Service

@MainActor
class SuuntoImportService: ObservableObject {
    static let shared = SuuntoImportService()

    @Published var isImporting = false
    @Published var lastImportResult: SuuntoImportResult?
    @Published var lastError: SuuntoImportError?

    // Separate ModelContainer for Suunto data (avoids migration issues)
    private var suuntoContainer: ModelContainer?
    private var suuntoContext: ModelContext?
    private let healthKitManager = HealthKitManager.shared

    private init() {
        setupSuuntoContainer()
    }

    /// Setup a separate container just for Suunto data
    private func setupSuuntoContainer() {
        do {
            let schema = Schema([CachedSuuntoWorkout.self])
            let config = ModelConfiguration(
                "SuuntoData",
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            suuntoContainer = try ModelContainer(for: schema, configurations: [config])
            suuntoContext = ModelContext(suuntoContainer!)
            print("✅ SuuntoImportService: Separate container initialized")
        } catch {
            print("⚠️ SuuntoImportService: Could not create separate container: \(error)")
        }
    }

    func setModelContext(_ context: ModelContext) {
        // Keep for compatibility, but we use our own container now
        print("✅ SuuntoImportService: ModelContext set (using separate container)")
    }

    private func getContext() throws -> ModelContext {
        guard let context = suuntoContext else {
            throw NSError(domain: "SuuntoImportService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Suunto ModelContext not initialized"
            ])
        }
        return context
    }

    // MARK: - Import from URL

    func importWorkout(from url: URL, fileName: String? = nil) async throws -> SuuntoImportResult {
        isImporting = true
        defer { isImporting = false }

        // Parse the JSON file
        let parsed: ParsedSuuntoWorkout
        do {
            parsed = try SuuntoParser.parse(from: url)
            print("✅ Parsed Suunto workout: \(parsed.activityType) - \(parsed.distance)m")
        } catch {
            let importError = SuuntoImportError.parseError(error)
            lastError = importError
            throw importError
        }

        // Delete existing if already imported (to allow re-import with updated splits calculation)
        let workoutId = "\(parsed.startDate.timeIntervalSince1970)-\(parsed.duration)"
        if (try? isAlreadyImported(parsed)) == true {
            do {
                try deleteCachedWorkout(id: workoutId)
                print("🔄 Deleted existing Suunto workout to re-import with fresh data")
            } catch {
                print("⚠️ Could not delete existing workout: \(error.localizedDescription)")
            }
        }

        // Check if matching workout exists in HealthKit
        let existingWorkout = try await findMatchingHealthKitWorkout(for: parsed)

        // Save to cache (gracefully handle database errors - import still succeeds)
        do {
            try saveToCache(parsed, fileName: fileName)
        } catch {
            print("⚠️ Could not save to cache (migration needed?): \(error.localizedDescription)")
        }

        let result: SuuntoImportResult
        if let existing = existingWorkout {
            result = .enriched(existingWorkout: existing, suuntoData: parsed)
            print("✅ Found matching HealthKit workout, will enrich with Suunto data")
        } else {
            result = .created(parsed)
            print("✅ No matching HealthKit workout, Suunto data saved locally")
        }

        lastImportResult = result
        return result
    }

    // MARK: - HealthKit Matching

    private func findMatchingHealthKitWorkout(for suunto: ParsedSuuntoWorkout) async throws -> WorkoutModel? {
        let workouts = try await healthKitManager.fetchRunningWorkouts()

        // Find workout with matching time window
        let tolerance: TimeInterval = 5 * 60 // 5 minutes

        for workout in workouts {
            let timeDiff = abs(workout.startDate.timeIntervalSince(suunto.startDate))
            if timeDiff < tolerance {
                // Check duration similarity (within 5%)
                let durationDiff = abs(workout.duration - suunto.duration) / max(workout.duration, suunto.duration)
                if durationDiff < 0.05 {
                    print("🔍 Found matching HealthKit workout: \(workout.startDate)")
                    return workout
                }
            }
        }

        return nil
    }

    // MARK: - Cache Management

    private func isAlreadyImported(_ parsed: ParsedSuuntoWorkout) throws -> Bool {
        let context = try getContext()
        let id = "\(parsed.startDate.timeIntervalSince1970)-\(parsed.duration)"

        let descriptor = FetchDescriptor<CachedSuuntoWorkout>(
            predicate: #Predicate { $0.id == id }
        )

        return try !context.fetch(descriptor).isEmpty
    }

    private func saveToCache(_ parsed: ParsedSuuntoWorkout, fileName: String?) throws {
        let context = try getContext()
        let cached = CachedSuuntoWorkout(from: parsed, fileName: fileName)
        context.insert(cached)
        try context.save()
        print("💾 Saved Suunto workout to cache")
    }

    func fetchAllCachedWorkouts() throws -> [ParsedSuuntoWorkout] {
        let context = try getContext()
        let descriptor = FetchDescriptor<CachedSuuntoWorkout>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )

        let cached = try context.fetch(descriptor)
        return cached.map { $0.toParsedWorkout() }
    }

    func getCachedWorkoutCount() throws -> Int {
        guard let context = suuntoContext else { return 0 }
        let descriptor = FetchDescriptor<CachedSuuntoWorkout>()
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    func deleteCachedWorkout(id: String) throws {
        let context = try getContext()
        let descriptor = FetchDescriptor<CachedSuuntoWorkout>(
            predicate: #Predicate { $0.id == id }
        )

        if let workout = try context.fetch(descriptor).first {
            context.delete(workout)
            try context.save()
        }
    }

    func clearAllCache() throws {
        let context = try getContext()
        try context.delete(model: CachedSuuntoWorkout.self)
        try context.save()
        print("🗑️ Cleared all Suunto cache")
    }
}

// MARK: - Suunto Activity (for UnifiedWorkout compatibility)

struct SuuntoActivity {
    let id: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let distance: Double
    let calories: Double
    let elevationGain: Double

    let averageSpeed: Double?
    let maxSpeed: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?

    let averageCadence: Double?
    let averagePower: Double?
    let averageGroundContactTime: Double?
    let averageVerticalOscillation: Double?
    let averageStrideLength: Double?

    let vo2Max: Double?
    let trainingEffect: Double?

    let hasRoute: Bool
    let deviceName: String
    let activityType: String

    // Splits
    let splits: [SuuntoSplit]

    init(from parsed: ParsedSuuntoWorkout) {
        self.id = "suunto-\(parsed.startDate.timeIntervalSince1970)"
        self.startDate = parsed.startDate
        self.endDate = parsed.endDate
        self.duration = parsed.duration
        self.distance = parsed.distance
        self.calories = parsed.calories
        self.elevationGain = parsed.elevationGain

        self.averageSpeed = parsed.averageSpeed
        self.maxSpeed = parsed.maxSpeed
        self.averageHeartRate = parsed.averageHeartRate
        self.maxHeartRate = parsed.maxHeartRate

        self.averageCadence = parsed.averageCadence
        self.averagePower = parsed.averagePower
        self.averageGroundContactTime = parsed.averageGroundContactTime
        self.averageVerticalOscillation = parsed.averageVerticalOscillation
        self.averageStrideLength = parsed.averageStrideLength

        self.vo2Max = parsed.vo2Max
        self.trainingEffect = parsed.trainingEffect

        self.hasRoute = parsed.hasRoute
        self.deviceName = parsed.deviceName
        self.activityType = parsed.activityType
        self.splits = parsed.splits
    }

    var averagePace: Double? {
        guard let speed = averageSpeed, speed > 0 else { return nil }
        return (1000.0 / speed) / 60.0 // min/km
    }
}
