    //
//  HealthKitManager.swift
//  InsightRun
//
//  Service layer for interacting with HealthKit
//

import Foundation
import HealthKit
import CoreLocation
import Combine
import WorkoutKit

enum HealthKitError: Error {
    case notAvailable
    case authorizationDenied
    case dataNotAvailable
    case queryFailed(Error)
}

@MainActor
class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()

    private init() {}

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }

        // Track permission request
        AnalyticsService.shared.trackHealthKitPermissionRequested()

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKQuantityType.quantityType(forIdentifier: .runningPower)!,
            HKQuantityType.quantityType(forIdentifier: .runningStrideLength)!,
            HKQuantityType.quantityType(forIdentifier: .runningGroundContactTime)!,
            HKQuantityType.quantityType(forIdentifier: .runningVerticalOscillation)!,
            HKQuantityType.quantityType(forIdentifier: .runningSpeed)!,
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
        ]

        var typesToRead: Set<HKObjectType> = [
            // Workouts
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),

            // Running Metrics
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .runningSpeed)!,
            HKObjectType.quantityType(forIdentifier: .runningPower)!,
            HKObjectType.quantityType(forIdentifier: .runningStrideLength)!,
            HKObjectType.quantityType(forIdentifier: .runningGroundContactTime)!,
            HKObjectType.quantityType(forIdentifier: .runningVerticalOscillation)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,

            // Mobility Metrics (Apple Watch Series 4+)
            HKObjectType.quantityType(forIdentifier: .appleWalkingSteadiness)!,
            HKObjectType.quantityType(forIdentifier: .walkingSpeed)!,
            HKObjectType.quantityType(forIdentifier: .walkingAsymmetryPercentage)!,
            HKObjectType.quantityType(forIdentifier: .walkingDoubleSupportPercentage)!,
            HKObjectType.quantityType(forIdentifier: .stairAscentSpeed)!,
            HKObjectType.quantityType(forIdentifier: .stairDescentSpeed)!,

            // Cardio Fitness
            HKObjectType.quantityType(forIdentifier: .vo2Max)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .walkingHeartRateAverage)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,

            // Sleep
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,

            // Activity
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .appleStandTime)!,
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,

            // Cross-training
            HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
            HKObjectType.quantityType(forIdentifier: .distanceSwimming)!,
            HKObjectType.quantityType(forIdentifier: .cyclingSpeed)!,
            HKObjectType.quantityType(forIdentifier: .cyclingCadence)!,
            HKObjectType.quantityType(forIdentifier: .cyclingPower)!,
            HKObjectType.quantityType(forIdentifier: .cyclingFunctionalThresholdPower)!,

            // Health & Body
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)!,
            HKObjectType.quantityType(forIdentifier: .leanBodyMass)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .bodyTemperature)!,
        ]

        // Add characteristic types (age, biological sex, etc.)
        let characteristicTypes: Set<HKObjectType> = [
            HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
            HKObjectType.characteristicType(forIdentifier: .biologicalSex)!,
        ]

        typesToRead.formUnion(characteristicTypes)

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)

            // Mark that user has completed the authorization flow
            hasCompletedHealthKitSetup = true

            // Track permission granted (user allowed access)
            AnalyticsService.shared.trackHealthKitPermissionGranted()
        } catch {
            // Track permission denied
            AnalyticsService.shared.trackHealthKitPermissionDenied()
            throw error
        }
    }

    /// Check if we can access HealthKit data
    /// Returns true only if user has completed the authorization flow
    func checkDataAccess() async -> Bool {
        // If already marked as setup, verify we can query
        if hasCompletedHealthKitSetup {
            do {
                _ = try await fetchRunningWorkouts()
                return true
            } catch {
                return false
            }
        }

        // Migration: Check if existing user has workout data (means they authorized before)
        do {
            let workouts = try await fetchRunningWorkouts()
            if !workouts.isEmpty {
                // User has workout data, so they authorized before - set the flag
                hasCompletedHealthKitSetup = true
                return true
            }
            // No workouts and no flag = new user who hasn't authorized
            return false
        } catch {
            return false
        }
    }

    /// Track if user has completed HealthKit authorization flow
    var hasCompletedHealthKitSetup: Bool {
        get { UserDefaults.standard.bool(forKey: "hasCompletedHealthKitSetup") }
        set { UserDefaults.standard.set(newValue, forKey: "hasCompletedHealthKitSetup") }
    }

    // MARK: - Fetch Running Workouts

    /// Fetch ALL running workouts (deprecated - use paginated version instead)
    /// WARNING: This loads all workouts at once. For large histories, use fetchRunningWorkouts(limit:anchor:)
    func fetchRunningWorkouts() async throws -> [WorkoutModel] {
        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)

        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: runningPredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                let workoutModels = workouts.map { WorkoutModel(from: $0) }
                continuation.resume(returning: workoutModels)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch running workouts within a date range
    /// - Parameters:
    ///   - startDate: Start of the date range
    ///   - endDate: End of the date range
    /// - Returns: Array of workouts within the date range, sorted by date descending
    func fetchRunningWorkouts(from startDate: Date, to endDate: Date) async throws -> [WorkoutModel] {
        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let datePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [runningPredicate, datePredicate])

        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: [])
                    return
                }

                let workoutModels = workouts.map { workout in
                    // Use statistics(for:) instead of deprecated totalEnergyBurned (iOS 18+)
                    let energyType = HKQuantityType(.activeEnergyBurned)
                    let energyBurned = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie())

                    return WorkoutModel(
                        id: workout.uuid,
                        workoutType: workout.workoutActivityType,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        duration: workout.duration,
                        distance: workout.totalDistance?.doubleValue(for: .meter()),
                        totalEnergyBurned: energyBurned,
                        sourceName: workout.sourceRevision.source.name,
                        sourceVersion: workout.sourceRevision.version,
                        metadata: workout.metadata,
                        averageHeartRate: nil,
                        maxHeartRate: nil,
                        elevationGain: nil,
                        hasRoute: workout.workoutActivities.contains { $0.allStatistics[.init(.distanceWalkingRunning)] != nil }
                    )
                }

                continuation.resume(returning: workoutModels)
            }

            self.healthStore.execute(query)
        }
    }

    /// Fetch running workouts with pagination (RECOMMENDED)
    /// - Parameters:
    ///   - limit: Number of workouts to fetch (default: 100, similar to Strava's per_page=200 but conservative)
    ///   - startDate: Optional date to fetch workouts before (for pagination)
    /// - Returns: Tuple with workouts and the oldest workout date (use for next page)
    func fetchRunningWorkouts(limit: Int = 100, startingBefore date: Date? = nil) async throws -> (workouts: [WorkoutModel], hasMore: Bool) {
        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)

        // If we have a date, only fetch workouts before that date (for pagination)
        let predicate: NSPredicate
        if let beforeDate = date {
            let datePredicate = HKQuery.predicateForSamples(
                withStart: nil,
                end: beforeDate,
                options: .strictEndDate
            )
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [runningPredicate, datePredicate])
        } else {
            predicate = runningPredicate
        }

        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            // Fetch limit + 1 to check if there are more workouts
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: limit + 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume(returning: ([], false))
                    return
                }

                // Check if there are more workouts
                let hasMore = workouts.count > limit

                // Take only the requested limit
                let limitedWorkouts = hasMore ? Array(workouts.prefix(limit)) : workouts
                let workoutModels = limitedWorkouts.map { WorkoutModel(from: $0) }

                continuation.resume(returning: (workoutModels, hasMore))
            }

            healthStore.execute(query)
        }
    }

    /// Get total count of running workouts (for progress tracking during backfill)
    func getRunningWorkoutsCount() async throws -> Int {
        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: runningPredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                continuation.resume(returning: samples?.count ?? 0)
            }

            healthStore.execute(query)
        }
    }

    /// Get count of running workouts in a date range (optimized - no data transfer)
    func getRecentWorkoutsCount(since startDate: Date) async throws -> Int {
        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let datePredicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [runningPredicate, datePredicate])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                continuation.resume(returning: samples?.count ?? 0)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch recent workouts with a limit
    func fetchWorkouts(limit: Int) async -> [WorkoutModel] {
        let workoutType = HKObjectType.workoutType()
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)

        do {
            return try await withCheckedThrowingContinuation { continuation in
                let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

                let query = HKSampleQuery(
                    sampleType: workoutType,
                    predicate: runningPredicate,
                    limit: limit,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: HealthKitError.queryFailed(error))
                        return
                    }

                    guard let workouts = samples as? [HKWorkout] else {
                        continuation.resume(returning: [])
                        return
                    }

                    let workoutModels = workouts.map { WorkoutModel(from: $0) }
                    continuation.resume(returning: workoutModels)
                }

                healthStore.execute(query)
            }
        } catch {
            return []
        }
    }

    /// Fetch latest VO2 Max value
    func fetchLatestVO2Max() async -> Double? {
        guard let vo2MaxType = HKQuantityType.quantityType(forIdentifier: .vo2Max) else {
            return nil
        }

        // Query VO2Max from the last 30 days
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate) ?? endDate

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        do {
            return try await withCheckedThrowingContinuation { continuation in
                let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

                let query = HKSampleQuery(
                    sampleType: vo2MaxType,
                    predicate: predicate,
                    limit: 1,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: HealthKitError.queryFailed(error))
                        return
                    }

                    if let sample = samples?.first as? HKQuantitySample {
                        let vo2Max = sample.quantity.doubleValue(
                            for: HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute()))
                        )
                        continuation.resume(returning: vo2Max)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }

                healthStore.execute(query)
            }
        } catch {
            return nil
        }
    }

    // MARK: - Fetch Workout Details

    func fetchWorkoutMetrics(for workoutModel: WorkoutModel) async throws -> WorkoutMetrics {
        // Find the original HKWorkout by UUID first
        var workout = try await findWorkout(with: workoutModel.id)

        // Fallback: search by date if UUID doesn't match (common with cached workouts)
        if workout == nil {
            print("⚠️ Workout not found by UUID, trying date fallback...")
            workout = try await findWorkoutByDate(
                startDate: workoutModel.startDate,
                duration: workoutModel.duration
            )
        }

        guard let workout = workout else {
            print("❌ Workout not found by UUID or date")
            throw HealthKitError.dataNotAvailable
        }

        print("✅ Found workout: \(workout.uuid) (duration: \(workout.duration)s)")

        // Fetch all metrics in parallel with graceful error handling
        // Each query returns nil/default on error instead of failing the entire operation
        // This is critical for indoor workouts where GPS/route data is unavailable

        async let heartRateData = safeHeartRateData(for: workout)
        async let firstLastHR = fetchFirstLastHeartRate(for: workout)
        async let paceData = safePaceData(for: workout)
        async let stepCountData = fetchStepCount(for: workout)
        async let strideLengthData = safeStrideLength(for: workout)
        async let powerData = safeRunningPower(for: workout)
        async let firstLastPower = fetchFirstLastPower(for: workout)
        async let elevationData = safeElevation(for: workout)
        async let routeData = safeRoute(for: workout)
        async let vo2MaxData = safeVO2Max(around: workoutModel.startDate)
        async let advancedMetrics = safeAdvancedRunningMetrics(for: workout)
        async let mobilityMetrics = fetchMobilityMetrics(for: workout)
        async let weatherData = extractWeatherData(from: workout)
        async let intervalsData = fetchWorkoutIntervals(for: workout)

        // Await all results (none will throw now)
        let steps = await stepCountData
        let weather = await weatherData
        let mobility = await mobilityMetrics
        let hrFirstLast = await firstLastHR
        let powerFirstLast = await firstLastPower
        let hr = await heartRateData
        let pace = await paceData
        let stride = await strideLengthData
        let power = await powerData
        let elevation = await elevationData
        let route = await routeData
        let vo2Max = await vo2MaxData
        let advanced = await advancedMetrics
        let intervals = await intervalsData

        // Calculate cadence from steps
        let cadence = calculateCadence(steps: steps, duration: workout.duration)

        // Calculate elevation from route if not available
        let finalElevation: (ascent: Double?, descent: Double?)
        if elevation.ascent == nil && elevation.descent == nil, let route = route {
            finalElevation = calculateElevationFromRoute(route)
        } else {
            finalElevation = elevation
        }

        // Calculate splits (safe version)
        let splits = await safeSplits(for: workout, routePoints: route)

        return WorkoutMetrics(
            workout: workoutModel,
            averageHeartRate: hr.average,
            minHeartRate: hr.min,
            maxHeartRate: hr.max,
            firstHeartRate: hrFirstLast.first,
            lastHeartRate: hrFirstLast.last,
            heartRateZones: hr.zones,
            averagePace: pace.average,
            minPace: pace.min,
            maxPace: pace.max,
            averageSpeed: workoutModel.averageSpeed,
            maxSpeed: pace.maxSpeed,
            totalSteps: steps,
            averageCadence: cadence,
            strideLength: stride,
            runningPower: power,
            firstPower: powerFirstLast.first,
            lastPower: powerFirstLast.last,
            totalElevationAscent: finalElevation.ascent,
            totalElevationDescent: finalElevation.descent,
            splits: splits,
            intervals: intervals,
            routePoints: route,
            groundContactTime: advanced.groundContactTime,
            groundContactTimeBalance: advanced.groundContactTimeBalance,
            verticalOscillation: advanced.verticalOscillation,
            runningEfficiency: advanced.efficiency,
            walkingSteadiness: mobility.walkingSteadiness,
            walkingAsymmetry: mobility.walkingAsymmetry,
            doubleSupportPercentage: mobility.doubleSupportPercentage,
            walkingSpeed: mobility.walkingSpeed,
            stairAscentSpeed: mobility.stairAscentSpeed,
            stairDescentSpeed: mobility.stairDescentSpeed,
            vo2Max: vo2Max,
            temperature: weather.temperature,
            humidity: weather.humidity,
            movingTime: calculateMovingTime(for: workout),
            pausedTime: nil
        )
    }

    // MARK: - Helper: Find Workout by UUID or Date

    private func findWorkout(with uuid: UUID) async throws -> HKWorkout? {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForObject(with: uuid)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                continuation.resume(returning: samples?.first as? HKWorkout)
            }

            healthStore.execute(query)
        }
    }

    /// Fallback search: find workout by date range when UUID doesn't match
    /// This handles cases where cached workouts have different UUIDs than HealthKit
    private func findWorkoutByDate(startDate: Date, duration: TimeInterval) async throws -> HKWorkout? {
        let workoutType = HKObjectType.workoutType()

        // Search within a 1-minute window of the start date
        let startWindow = startDate.addingTimeInterval(-30)
        let endWindow = startDate.addingTimeInterval(30)

        let datePredicate = HKQuery.predicateForSamples(
            withStart: startWindow,
            end: endWindow,
            options: .strictStartDate
        )
        let runningPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, runningPredicate])

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 10,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                guard let workouts = samples as? [HKWorkout], !workouts.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                // Find the workout with the closest matching duration
                let targetDuration = duration
                let bestMatch = workouts.min(by: { workout1, workout2 in
                    abs(workout1.duration - targetDuration) < abs(workout2.duration - targetDuration)
                })

                continuation.resume(returning: bestMatch)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Safe Wrappers (Non-throwing)
    // These wrappers catch errors and return defaults, ensuring partial data is still available
    // Critical for indoor workouts where GPS/route data doesn't exist

    private func safeHeartRateData(for workout: HKWorkout) async -> (
        average: Double?, min: Double?, max: Double?, zones: HeartRateZones?
    ) {
        do {
            return try await fetchHeartRateData(for: workout)
        } catch {
            print("⚠️ Heart rate fetch failed: \(error.localizedDescription)")
            return (nil, nil, nil, nil)
        }
    }


    private func safePaceData(for workout: HKWorkout) async -> (
        average: Double?, min: Double?, max: Double?, maxSpeed: Double?
    ) {
        do {
            return try await fetchPaceData(for: workout)
        } catch {
            print("⚠️ Pace data fetch failed: \(error.localizedDescription)")
            // Fall back to calculated pace from workout totals
            let avgPace = workout.duration > 0 && workout.totalDistance != nil
                ? (workout.duration / 60.0) / (workout.totalDistance!.doubleValue(for: .meter()) / 1000.0)
                : nil
            return (avgPace, nil, nil, nil)
        }
    }

    private func safeStrideLength(for workout: HKWorkout) async -> Double? {
        do {
            return try await fetchStrideLength(for: workout)
        } catch {
            print("⚠️ Stride length fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func safeRunningPower(for workout: HKWorkout) async -> Double? {
        do {
            return try await fetchRunningPower(for: workout)
        } catch {
            print("⚠️ Running power fetch failed: \(error.localizedDescription)")
            return nil
        }
    }


    private func safeElevation(for workout: HKWorkout) async -> (ascent: Double?, descent: Double?) {
        do {
            return try await fetchElevation(for: workout)
        } catch {
            print("⚠️ Elevation fetch failed: \(error.localizedDescription)")
            return (nil, nil)
        }
    }

    private func safeRoute(for workout: HKWorkout) async -> [RoutePoint]? {
        do {
            return try await fetchRoute(for: workout)
        } catch {
            print("⚠️ Route fetch failed (expected for indoor workouts): \(error.localizedDescription)")
            return nil
        }
    }

    private func safeVO2Max(around date: Date) async -> Double? {
        do {
            return try await fetchVO2Max(around: date)
        } catch {
            print("⚠️ VO2Max fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func safeAdvancedRunningMetrics(for workout: HKWorkout) async -> (
        groundContactTime: Double?, groundContactTimeBalance: Double?,
        verticalOscillation: Double?, efficiency: Double?
    ) {
        do {
            return try await fetchAdvancedRunningMetrics(for: workout)
        } catch {
            print("⚠️ Advanced metrics fetch failed: \(error.localizedDescription)")
            return (nil, nil, nil, nil)
        }
    }

    private func safeSplits(for workout: HKWorkout, routePoints: [RoutePoint]?) async -> [Split]? {
        do {
            return try await calculateSplits(for: workout, routePoints: routePoints)
        } catch {
            print("⚠️ Splits calculation failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Workout Intervals (Activities)
    // iOS 16+ stores structured workout intervals in workout.workoutActivities
    // Each HKWorkoutActivity has metadata with the interval type (warmup, work, recovery, etc.)

    private func fetchWorkoutIntervals(for workout: HKWorkout) async -> [WorkoutInterval]? {
        // iOS 16+ uses workoutActivities for structured intervals
        let activities = workout.workoutActivities

        print("📊 Workout activities count: \(activities.count)")

        guard !activities.isEmpty else {
            print("ℹ️ No workout activities (intervals) found")
            return nil
        }

        // Fetch target paces from WorkoutPlan (iOS 17+)
        var targetPaces: [IntervalTargetPace] = []
        if #available(iOS 17.0, *) {
            targetPaces = await fetchTargetPacesFromWorkoutPlan(for: workout)
        }

        var intervals: [WorkoutInterval] = []

        for (index, activity) in activities.enumerated() {
            let startDate = activity.startDate
            let endDate = activity.endDate ?? workout.endDate
            let duration = activity.duration

            // Debug: print all metadata keys and values
            print("📋 Activity \(index):")
            print("   - duration: \(duration)s (\(duration/60.0)min)")
            print("   - config.activityType: \(activity.workoutConfiguration.activityType.rawValue)")
            print("   - config.lapLength: \(String(describing: activity.workoutConfiguration.lapLength))")
            if let metadata = activity.metadata {
                print("   - metadata keys: \(metadata.keys.sorted())")
                for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
                    print("     • \(key): \(value)")
                }
            } else {
                print("   - metadata: nil")
            }

            // Get interval type from metadata
            let intervalType = determineIntervalTypeFromActivity(activity, index: index, totalActivities: activities.count)
            print("   - intervalType: \(intervalType.rawValue)")

            // Get statistics for this activity
            let heartRateStat = activity.statistics(for: HKQuantityType(.heartRate))
            let averageHeartRate = heartRateStat?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

            let distanceStat = activity.statistics(for: HKQuantityType(.distanceWalkingRunning))
            let distance = distanceStat?.sumQuantity()?.doubleValue(for: .meter())

            let powerStat = activity.statistics(for: HKQuantityType(.runningPower))
            let averagePower = powerStat?.averageQuantity()?.doubleValue(for: .watt())

            // Calculate pace if we have distance
            var pace: Double?
            if let dist = distance, dist > 0, duration > 0 {
                pace = (duration / 60.0) / (dist / 1000.0) // min/km
            }

            // Find target pace for this step from WorkoutPlan
            let targetPace = targetPaces.first { $0.stepIndex == index }
            if let target = targetPace {
                print("   - target pace: \(target.paceMinPerKm)-\(target.paceMaxPerKm) min/km")
            }

            let interval = WorkoutInterval(
                index: index + 1,
                type: intervalType,
                startDate: startDate,
                endDate: endDate,
                duration: duration,
                distance: distance,
                pace: pace,
                averageHeartRate: averageHeartRate,
                averagePower: averagePower,
                targetPaceMin: targetPace?.paceMinPerKm,
                targetPaceMax: targetPace?.paceMaxPerKm
            )

            intervals.append(interval)
        }

        // Classify unknown intervals as work/recovery based on pace
        if !intervals.isEmpty {
            classifyIntervalsBasedOnPace(&intervals)
        }

        return intervals.isEmpty ? nil : intervals
    }

    private func determineIntervalTypeFromActivity(_ activity: HKWorkoutActivity, index: Int, totalActivities: Int) -> IntervalType {
        // Check metadata for explicit interval type
        if let metadata = activity.metadata {
            // Apple uses HKMetadataKeyWorkoutBrandName or custom keys for interval type
            if let purposeRaw = metadata[HKMetadataKeyWorkoutBrandName] as? String {
                return parseIntervalType(from: purposeRaw)
            }

            // Check for "purpose" or "type" keys
            for (key, value) in metadata {
                let keyLower = key.lowercased()
                if keyLower.contains("purpose") || keyLower.contains("type") || keyLower.contains("goal") {
                    if let stringValue = value as? String {
                        return parseIntervalType(from: stringValue)
                    }
                }
            }
        }

        // Fallback: use position-based heuristics for first/last
        if index == 0 && totalActivities > 1 {
            return .warmup
        } else if index == totalActivities - 1 && totalActivities > 1 {
            return .cooldown
        }

        return .unknown
    }

    /// Analyzes intervals to determine work vs recovery based on pace comparison
    /// Work intervals have faster pace (lower min/km), recovery has slower pace
    private func classifyIntervalsBasedOnPace(_ intervals: inout [WorkoutInterval]) {
        // Skip first (warmup) and last (cooldown) intervals
        guard intervals.count > 2 else { return }

        let middleIntervals = intervals[1..<(intervals.count - 1)]

        // Get paces of middle intervals (excluding warmup/cooldown)
        let paces = middleIntervals.compactMap { $0.pace }
        guard paces.count >= 2 else { return }

        // Calculate median pace to separate work from recovery
        let sortedPaces = paces.sorted()
        let medianPace = sortedPaces[sortedPaces.count / 2]

        print("🔍 Classifying intervals - median pace: \(medianPace) min/km")

        // Classify each middle interval
        for i in 1..<(intervals.count - 1) {
            if intervals[i].type == .unknown, let pace = intervals[i].pace {
                // Faster than median = work, slower = recovery
                if pace < medianPace {
                    intervals[i] = WorkoutInterval(
                        index: intervals[i].index,
                        type: .work,
                        startDate: intervals[i].startDate,
                        endDate: intervals[i].endDate,
                        duration: intervals[i].duration,
                        distance: intervals[i].distance,
                        pace: intervals[i].pace,
                        averageHeartRate: intervals[i].averageHeartRate,
                        averagePower: intervals[i].averagePower,
                        targetPaceMin: intervals[i].targetPaceMin,
                        targetPaceMax: intervals[i].targetPaceMax
                    )
                    print("   Interval \(intervals[i].index): pace \(pace) < median \(medianPace) → WORK")
                } else {
                    intervals[i] = WorkoutInterval(
                        index: intervals[i].index,
                        type: .recovery,
                        startDate: intervals[i].startDate,
                        endDate: intervals[i].endDate,
                        duration: intervals[i].duration,
                        distance: intervals[i].distance,
                        pace: intervals[i].pace,
                        averageHeartRate: intervals[i].averageHeartRate,
                        averagePower: intervals[i].averagePower,
                        targetPaceMin: intervals[i].targetPaceMin,
                        targetPaceMax: intervals[i].targetPaceMax
                    )
                    print("   Interval \(intervals[i].index): pace \(pace) >= median \(medianPace) → RECOVERY")
                }
            }
        }
    }

    private func parseIntervalType(from string: String) -> IntervalType {
        let lower = string.lowercased()
        if lower.contains("warmup") || lower.contains("warm-up") || lower.contains("warm up") || lower.contains("échauffement") {
            return .warmup
        } else if lower.contains("work") || lower.contains("interval") || lower.contains("fast") || lower.contains("travail") {
            return .work
        } else if lower.contains("recovery") || lower.contains("rest") || lower.contains("jog") || lower.contains("récup") {
            return .recovery
        } else if lower.contains("cooldown") || lower.contains("cool-down") || lower.contains("cool down") || lower.contains("retour") {
            return .cooldown
        }
        return .unknown
    }

    // MARK: - WorkoutPlan Target Pace Extraction
    // iOS 17+ can access the original workout plan with target paces via WorkoutKit

    /// Target pace information for an interval step
    private struct IntervalTargetPace {
        let stepIndex: Int
        let paceMinPerKm: Double // min/km (lower bound = faster)
        let paceMaxPerKm: Double // min/km (upper bound = slower)
    }

    /// Extracts target pace ranges from a workout's WorkoutPlan (iOS 17+)
    /// Returns an array of target paces indexed by step order
    @available(iOS 17.0, *)
    private func fetchTargetPacesFromWorkoutPlan(for workout: HKWorkout) async -> [IntervalTargetPace] {
        do {
            guard let workoutPlan = try await workout.workoutPlan else {
                print("ℹ️ No WorkoutPlan found for workout")
                return []
            }

            print("📋 Found WorkoutPlan, extracting target paces...")

            var targets: [IntervalTargetPace] = []
            var stepIndex = 0

            switch workoutPlan.workout {
            case .custom(let customWorkout):
                print("   - Custom workout: \(customWorkout.displayName ?? "unnamed")")

                // Warmup step
                if let warmup = customWorkout.warmup {
                    if let targetPace = extractTargetPaceFromAlert(warmup.alert) {
                        targets.append(IntervalTargetPace(stepIndex: stepIndex, paceMinPerKm: targetPace.min, paceMaxPerKm: targetPace.max))
                        print("   - Warmup target: \(targetPace.min)-\(targetPace.max) min/km")
                    }
                    stepIndex += 1
                }

                // Interval blocks
                for (blockIndex, block) in customWorkout.blocks.enumerated() {
                    print("   - Block \(blockIndex): \(block.iterations) iterations, \(block.steps.count) steps")
                    for iteration in 0..<block.iterations {
                        for intervalStep in block.steps {
                            let alertType = intervalStep.step.alert.map { String(describing: type(of: $0)) } ?? "none"
                            print("   - Step \(stepIndex) (\(intervalStep.purpose), iter \(iteration)): alert type = \(alertType)")
                            if let targetPace = extractTargetPaceFromAlert(intervalStep.step.alert) {
                                targets.append(IntervalTargetPace(stepIndex: stepIndex, paceMinPerKm: targetPace.min, paceMaxPerKm: targetPace.max))
                                print("     → target: \(targetPace.min)-\(targetPace.max) min/km")
                            } else {
                                print("     → no speed target found")
                            }
                            stepIndex += 1
                        }
                    }
                }

                // Cooldown step
                if let cooldown = customWorkout.cooldown {
                    if let targetPace = extractTargetPaceFromAlert(cooldown.alert) {
                        targets.append(IntervalTargetPace(stepIndex: stepIndex, paceMinPerKm: targetPace.min, paceMaxPerKm: targetPace.max))
                        print("   - Cooldown target: \(targetPace.min)-\(targetPace.max) min/km")
                    }
                    stepIndex += 1
                }

            case .goal, .pacer, .swimBikeRun:
                print("   - Non-custom workout type, no interval targets")
            @unknown default:
                print("   - Unknown workout type")
            }

            return targets

        } catch {
            print("⚠️ Error fetching WorkoutPlan: \(error)")
            return []
        }
    }

    /// Extracts pace range from a WorkoutAlert (SpeedRangeAlert or SpeedThresholdAlert)
    /// Returns pace as min/km (lower = faster, higher = slower)
    @available(iOS 17.0, *)
    private func extractTargetPaceFromAlert(_ alert: (any WorkoutAlert)?) -> (min: Double, max: Double)? {
        guard let alert = alert else { return nil }

        // SpeedRangeAlert contains the target speed range (min-max)
        if let speedAlert = alert as? SpeedRangeAlert {
            // Convert speed (m/s) to pace (min/km)
            let lowerSpeedMps = speedAlert.target.lowerBound.converted(to: .metersPerSecond).value
            let upperSpeedMps = speedAlert.target.upperBound.converted(to: .metersPerSecond).value

            // Pace = 1000 / (speed * 60) = min/km
            // Faster speed = lower pace, so we swap bounds
            let paceMax = lowerSpeedMps > 0 ? (1000.0 / (lowerSpeedMps * 60.0)) : 0
            let paceMin = upperSpeedMps > 0 ? (1000.0 / (upperSpeedMps * 60.0)) : 0

            print("     SpeedRangeAlert: \(lowerSpeedMps)-\(upperSpeedMps) m/s → \(paceMin)-\(paceMax) min/km")
            return (min: paceMin, max: paceMax)
        }

        // SpeedThresholdAlert contains a single target speed (threshold)
        if let thresholdAlert = alert as? SpeedThresholdAlert {
            // Convert speed (m/s) to pace (min/km)
            let speedMps = thresholdAlert.target.converted(to: .metersPerSecond).value

            // Single threshold = same min and max pace
            let pace = speedMps > 0 ? (1000.0 / (speedMps * 60.0)) : 0

            print("     SpeedThresholdAlert: \(speedMps) m/s → \(pace) min/km")
            return (min: pace, max: pace)
        }

        return nil
    }

    // Legacy segment-based interval detection (kept for reference)
    private func fetchWorkoutIntervalsFromEvents(for workout: HKWorkout) async -> [WorkoutInterval]? {
        guard let events = workout.workoutEvents, !events.isEmpty else {
            print("ℹ️ No workout events (intervals) found")
            return nil
        }

        // Debug: print ALL event types to understand what's available
        let eventTypeCounts = Dictionary(grouping: events, by: { $0.type.rawValue })
        print("📊 Workout event types breakdown:")
        for (typeRaw, eventsOfType) in eventTypeCounts.sorted(by: { $0.key < $1.key }) {
            let typeName: String
            switch HKWorkoutEventType(rawValue: typeRaw) {
            case .pause: typeName = "pause"
            case .resume: typeName = "resume"
            case .lap: typeName = "lap"
            case .marker: typeName = "marker"
            case .motionPaused: typeName = "motionPaused"
            case .motionResumed: typeName = "motionResumed"
            case .segment: typeName = "segment"
            case .pauseOrResumeRequest: typeName = "pauseOrResumeRequest"
            default: typeName = "unknown"
            }
            print("   - \(typeName) (type=\(typeRaw)): \(eventsOfType.count) events")
        }

        // Filter for segment/lap events
        let segmentEvents = events.filter { event in
            event.type == .segment || event.type == .lap
        }

        guard !segmentEvents.isEmpty else {
            print("ℹ️ No segment/lap events found in workout events")
            return nil
        }

        print("✅ Found \(segmentEvents.count) segment/lap events")

        // Debug: print all event types to understand the data
        for (idx, event) in events.enumerated() {
            print("📋 Event \(idx): type=\(event.type.rawValue), start=\(event.dateInterval.start), duration=\(event.dateInterval.duration)s, metadata=\(String(describing: event.metadata))")
        }

        // Filter out overlapping segments (Garmin records km splits as overlapping segments)
        // Real interval workouts have sequential, non-overlapping segments
        let sortedEvents = segmentEvents.sorted { $0.dateInterval.start < $1.dateInterval.start }
        var nonOverlappingEvents: [HKWorkoutEvent] = []
        var lastEndDate: Date?

        for event in sortedEvents {
            let eventStart = event.dateInterval.start
            let eventEnd = event.dateInterval.end

            // Check if this event overlaps with previous events
            if let lastEnd = lastEndDate {
                // Allow 5 second tolerance for slight overlaps
                if eventStart < lastEnd.addingTimeInterval(-5) {
                    print("⚠️ Skipping overlapping segment: start=\(eventStart), lastEnd=\(lastEnd)")
                    continue
                }
            }

            nonOverlappingEvents.append(event)
            lastEndDate = eventEnd
        }

        print("✅ After filtering overlaps: \(nonOverlappingEvents.count) non-overlapping segments")

        // If all segments overlap (like Garmin km splits), return nil
        // Real interval workouts should have at least 2 non-overlapping segments
        guard nonOverlappingEvents.count >= 2 else {
            print("ℹ️ Not enough non-overlapping segments for interval display (likely km splits)")
            return nil
        }

        var intervals: [WorkoutInterval] = []
        var intervalIndex = 1

        for event in nonOverlappingEvents {
            let startDate = event.dateInterval.start
            let endDate = event.dateInterval.end
            let duration = event.dateInterval.duration

            print("🔍 Processing segment \(intervalIndex): start=\(startDate), end=\(endDate), duration=\(duration)s (\(duration/60.0)min)")

            // Determine interval type from metadata
            let intervalType = determineIntervalType(from: event.metadata, duration: duration, index: intervalIndex, totalEvents: segmentEvents.count)

            // Fetch metrics for this interval
            let heartRate = await fetchAverageHeartRate(for: workout, startDate: startDate, endDate: endDate)
            let power = await fetchAveragePower(for: workout, startDate: startDate, endDate: endDate)

            // Calculate distance and pace from metadata or route
            var distance: Double?
            var pace: Double?
            let targetPaceMin: Double? = nil
            let targetPaceMax: Double? = nil

            if let metadata = event.metadata {
                // Try to get distance from metadata
                if let distanceQuantity = metadata[HKMetadataKeyWorkoutBrandName] as? HKQuantity {
                    distance = distanceQuantity.doubleValue(for: .meter())
                }
            }

            // If we have distance, calculate pace
            if let dist = distance, dist > 0, duration > 0 {
                pace = (duration / 60.0) / (dist / 1000.0) // min/km
            }

            let interval = WorkoutInterval(
                index: intervalIndex,
                type: intervalType,
                startDate: startDate,
                endDate: endDate,
                duration: duration,
                distance: distance,
                pace: pace,
                averageHeartRate: heartRate,
                averagePower: power,
                targetPaceMin: targetPaceMin,
                targetPaceMax: targetPaceMax
            )

            intervals.append(interval)
            intervalIndex += 1
        }

        return intervals.isEmpty ? nil : intervals
    }

    private func determineIntervalType(from metadata: [String: Any]?, duration: TimeInterval, index: Int, totalEvents: Int) -> IntervalType {
        // Check metadata for explicit type
        if let metadata = metadata {
            if let typeName = metadata["type"] as? String {
                switch typeName.lowercased() {
                case "warmup", "warm-up", "warm up":
                    return .warmup
                case "work", "interval", "fast":
                    return .work
                case "recovery", "rest", "jog":
                    return .recovery
                case "cooldown", "cool-down", "cool down":
                    return .cooldown
                default:
                    break
                }
            }
        }

        // Heuristic: first segment is often warmup, last is often cooldown
        if index == 1 && duration > 300 { // > 5 minutes
            return .warmup
        }
        if index == totalEvents && duration > 300 { // > 5 minutes
            return .cooldown
        }

        // Alternate between work and recovery for middle segments
        if index > 1 && index < totalEvents {
            return (index % 2 == 0) ? .work : .recovery
        }

        return .unknown
    }

    // MARK: - Heart Rate

    private func fetchHeartRateData(for workout: HKWorkout) async throws -> (
        average: Double?, min: Double?, max: Double?, zones: HeartRateZones?
    ) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil, nil, nil)
        }

        // Extend time window slightly to catch samples recorded near workout boundaries
        let startDate = workout.startDate.addingTimeInterval(-60) // 1 min before
        let endDate = workout.endDate.addingTimeInterval(60) // 1 min after

        print("🔍 Fetching HR for workout: \(workout.startDate) - \(workout.endDate)")

        // Try workout-associated samples first (most accurate)
        let workoutPredicate = HKQuery.predicateForObjects(from: workout)

        let hrFromWorkout: (average: Double?, min: Double?, max: Double?) = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: workoutPredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    print("⚠️ HR workout query error: \(error.localizedDescription)")
                    continuation.resume(returning: (nil, nil, nil))
                    return
                }

                guard let hrSamples = samples as? [HKQuantitySample], !hrSamples.isEmpty else {
                    print("⚠️ No HR samples directly associated with workout")
                    continuation.resume(returning: (nil, nil, nil))
                    return
                }

                let unit = HKUnit.count().unitDivided(by: .minute())
                let values = hrSamples.map { $0.quantity.doubleValue(for: unit) }
                let avg = values.reduce(0, +) / Double(values.count)
                let minVal = values.min()
                let maxVal = values.max()

                print("✅ Found \(hrSamples.count) HR samples from workout association")
                continuation.resume(returning: (avg, minVal, maxVal))
            }

            healthStore.execute(query)
        }

        // If workout association worked, use those results
        if hrFromWorkout.average != nil {
            let zones: HeartRateZones? = hrFromWorkout.max.map { maxHR in
                HeartRateZones(
                    zone1: nil, zone2: nil, zone3: nil, zone4: nil, zone5: nil,
                    maxHeartRate: maxHR
                )
            }
            return (hrFromWorkout.average, hrFromWorkout.min, hrFromWorkout.max, zones)
        }

        // Fallback: time-based query with extended window
        print("🔄 Falling back to time-based HR query...")
        let timePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: [] // No strict options - more flexible matching
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: timePredicate,
                options: [.discreteAverage, .discreteMin, .discreteMax]
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                let average = statistics?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                let min = statistics?.minimumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                let max = statistics?.maximumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

                print("📊 Time-based HR result: avg=\(average ?? -1), min=\(min ?? -1), max=\(max ?? -1)")

                let zones: HeartRateZones? = max.map { maxHR in
                    HeartRateZones(
                        zone1: nil, zone2: nil, zone3: nil, zone4: nil, zone5: nil,
                        maxHeartRate: maxHR
                    )
                }

                continuation.resume(returning: (average, min, max, zones))
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Pace and Speed

    private func fetchPaceData(for workout: HKWorkout) async throws -> (
        average: Double?, min: Double?, max: Double?, maxSpeed: Double?
    ) {
        // Always calculate average pace from total duration and distance
        // This matches the calculation used by Apple Health app
        let avgPace = workout.duration > 0 && workout.totalDistance != nil
            ? (workout.duration / 60.0) / (workout.totalDistance!.doubleValue(for: .meter()) / 1000.0)
            : nil

        guard let speedType = HKQuantityType.quantityType(forIdentifier: .runningSpeed) else {
            return (avgPace, nil, nil, nil)
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: speedType,
                quantitySamplePredicate: predicate,
                options: [.discreteMin, .discreteMax]
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                let minSpeed = statistics?.minimumQuantity()?.doubleValue(for: HKUnit.meter().unitDivided(by: .second()))
                let maxSpeed = statistics?.maximumQuantity()?.doubleValue(for: HKUnit.meter().unitDivided(by: .second()))

                // Convert speed (m/s) to pace (min/km)
                let fastestPace = maxSpeed.map { $0 > 0 ? (1000.0 / $0) / 60.0 : nil } ?? nil
                let slowestPace = minSpeed.map { $0 > 0 ? (1000.0 / $0) / 60.0 : nil } ?? nil

                // Max speed in km/h
                let maxSpeedKmh = maxSpeed.map { $0 * 3.6 }

                // Use calculated average pace from duration/distance
                continuation.resume(returning: (avgPace, fastestPace, slowestPace, maxSpeedKmh))
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Step Count and Cadence

    private func fetchStepCount(for workout: HKWorkout) async -> Int? {
        guard let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        do {
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKStatisticsQuery(
                    quantityType: stepCountType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, error in
                    if let error = error {
                        continuation.resume(throwing: HealthKitError.queryFailed(error))
                        return
                    }

                    let steps = statistics?.sumQuantity()?.doubleValue(for: .count())
                    continuation.resume(returning: steps.map { Int($0) })
                }

                healthStore.execute(query)
            }
        } catch {
            return nil
        }
    }

    private func calculateCadence(steps: Int?, duration: TimeInterval) -> Double? {
        guard let steps = steps, duration > 0 else { return nil }
        let minutes = duration / 60.0
        return Double(steps) / minutes
    }

    // MARK: - Stride Length

    private func fetchStrideLength(for workout: HKWorkout) async throws -> Double? {
        guard let strideLengthType = HKQuantityType.quantityType(forIdentifier: .runningStrideLength) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: strideLengthType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                let strideLength = statistics?.averageQuantity()?.doubleValue(for: .meter())
                continuation.resume(returning: strideLength)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Running Power

    private func fetchRunningPower(for workout: HKWorkout) async throws -> Double? {
        guard let powerType = HKQuantityType.quantityType(forIdentifier: .runningPower) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: powerType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                let power = statistics?.averageQuantity()?.doubleValue(for: .watt())
                continuation.resume(returning: power)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Elevation

    private func fetchElevation(for workout: HKWorkout) async throws -> (ascent: Double?, descent: Double?) {
        // Elevation data is not directly queryable from HealthKit as separate metrics
        // It's usually embedded in the route data
        return (nil, nil)
    }

    private func calculateElevationFromRoute(_ routePoints: [RoutePoint]) -> (ascent: Double?, descent: Double?) {
        guard routePoints.count > 1 else { return (nil, nil) }

        var totalAscent = 0.0
        var totalDescent = 0.0

        for i in 1..<routePoints.count {
            if let alt1 = routePoints[i - 1].altitude, let alt2 = routePoints[i].altitude {
                let diff = alt2 - alt1
                if diff > 0 {
                    totalAscent += diff
                } else if diff < 0 {
                    totalDescent += abs(diff)
                }
            }
        }

        return (
            totalAscent > 0 ? totalAscent : nil,
            totalDescent > 0 ? totalDescent : nil
        )
    }

    // MARK: - Route

    private func fetchRoute(for workout: HKWorkout) async throws -> [RoutePoint]? {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)

        // First, find the route
        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                let routes = (samples as? [HKWorkoutRoute]) ?? []
                continuation.resume(returning: routes)
            }

            healthStore.execute(query)
        }

        guard let route = routes.first else {
            return nil
        }

        // Then, fetch the location data from the route
        return try await withCheckedThrowingContinuation { continuation in
            var routePoints: [RoutePoint] = []

            let routeQuery = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                if let locations = locations {
                    let points = locations.map { location in
                        RoutePoint(
                            coordinate: location.coordinate,
                            altitude: location.altitude,
                            timestamp: location.timestamp,
                            horizontalAccuracy: location.horizontalAccuracy,
                            verticalAccuracy: location.verticalAccuracy,
                            speed: location.speed >= 0 ? location.speed : nil
                        )
                    }
                    routePoints.append(contentsOf: points)
                }

                if done {
                    continuation.resume(returning: routePoints.isEmpty ? nil : routePoints)
                }
            }

            healthStore.execute(routeQuery)
        }
    }

    // MARK: - VO2 Max

    private func fetchVO2Max(around date: Date) async throws -> Double? {
        guard let vo2MaxType = HKQuantityType.quantityType(forIdentifier: .vo2Max) else {
            return nil
        }

        // Query VO2Max within a week of the workout
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: date) ?? date
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: vo2MaxType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                let vo2Max = statistics?.averageQuantity()?.doubleValue(
                    for: HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute()))
                )
                continuation.resume(returning: vo2Max)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Advanced Running Metrics

    private func fetchAdvancedRunningMetrics(for workout: HKWorkout) async throws -> (
        groundContactTime: Double?,
        groundContactTimeBalance: Double?,
        verticalOscillation: Double?,
        efficiency: Double?
    ) {
        // These metrics are only available on Apple Watch Series 7+
        async let gct = fetchAverageQuantity(
            for: .runningGroundContactTime,
            workout: workout,
            unit: .secondUnit(with: .milli)
        )
        async let vo = fetchAverageQuantity(
            for: .runningVerticalOscillation,
            workout: workout,
            unit: .meterUnit(with: .centi)
        )

        let (groundContactTime, verticalOscillation) = try await (gct, vo)

        return (groundContactTime, nil, verticalOscillation, nil)
    }

    // MARK: - Mobility Metrics

    private func fetchMobilityMetrics(for workout: HKWorkout) async -> (
        walkingSteadiness: Double?,
        walkingAsymmetry: Double?,
        doubleSupportPercentage: Double?,
        walkingSpeed: Double?,
        stairAscentSpeed: Double?,
        stairDescentSpeed: Double?
    ) {
        // These metrics are available on Apple Watch Series 4+
        // Note: These are measured throughout the day, not during workouts
        // We fetch the most recent value around the workout date

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: workout.startDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        async let steadiness = fetchLatestQuantityInRange(
            for: .appleWalkingSteadiness,
            start: startOfDay,
            end: endOfDay,
            unit: .percent()
        )
        async let asymmetry = fetchLatestQuantityInRange(
            for: .walkingAsymmetryPercentage,
            start: startOfDay,
            end: endOfDay,
            unit: .percent()
        )
        async let doubleSupport = fetchLatestQuantityInRange(
            for: .walkingDoubleSupportPercentage,
            start: startOfDay,
            end: endOfDay,
            unit: .percent()
        )
        async let walkSpeed = fetchLatestQuantityInRange(
            for: .walkingSpeed,
            start: startOfDay,
            end: endOfDay,
            unit: .meter().unitDivided(by: .second())
        )
        async let ascentSpeed = fetchLatestQuantityInRange(
            for: .stairAscentSpeed,
            start: startOfDay,
            end: endOfDay,
            unit: .meter().unitDivided(by: .second())
        )
        async let descentSpeed = fetchLatestQuantityInRange(
            for: .stairDescentSpeed,
            start: startOfDay,
            end: endOfDay,
            unit: .meter().unitDivided(by: .second())
        )

        let (steadinessVal, asymmetryVal, doubleSupportVal, walkSpeedVal, ascentSpeedVal, descentSpeedVal) = await (
            steadiness, asymmetry, doubleSupport, walkSpeed, ascentSpeed, descentSpeed
        )

        // Convert values to appropriate units
        let steadinessPercent = steadinessVal.map { $0 * 100 }
        let asymmetryPercent = asymmetryVal.map { $0 * 100 }
        let doubleSupportPercent = doubleSupportVal.map { $0 * 100 }
        let walkSpeedKmh = walkSpeedVal.map { $0 * 3.6 } // m/s to km/h
        let ascentSpeedKmh = ascentSpeedVal.map { $0 * 3.6 }
        let descentSpeedKmh = descentSpeedVal.map { $0 * 3.6 }

        return (
            walkingSteadiness: steadinessPercent,
            walkingAsymmetry: asymmetryPercent,
            doubleSupportPercentage: doubleSupportPercent,
            walkingSpeed: walkSpeedKmh,
            stairAscentSpeed: ascentSpeedKmh,
            stairDescentSpeed: descentSpeedKmh
        )
    }

    // Fetch latest quantity in a date range (for daily metrics)
    private func fetchLatestQuantityInRange(
        for identifier: HKQuantityTypeIdentifier,
        start: Date,
        end: Date,
        unit: HKUnit
    ) async -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        do {
            return try await withCheckedThrowingContinuation { continuation in
                let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

                let query = HKSampleQuery(
                    sampleType: quantityType,
                    predicate: predicate,
                    limit: 1,
                    sortDescriptors: [sortDescriptor]
                ) { _, samples, error in
                    if let error = error {
                        continuation.resume(throwing: HealthKitError.queryFailed(error))
                        return
                    }

                    if let sample = samples?.first as? HKQuantitySample {
                        let value = sample.quantity.doubleValue(for: unit)
                        continuation.resume(returning: value)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }

                healthStore.execute(query)
            }
        } catch {
            return nil
        }
    }

    private func fetchAverageQuantity(
        for identifier: HKQuantityTypeIdentifier,
        workout: HKWorkout,
        unit: HKUnit
    ) async throws -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                let value = statistics?.averageQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Splits Calculation

    private func calculateSplits(for workout: HKWorkout, routePoints: [RoutePoint]?) async throws -> [Split]? {
        guard let distance = workout.totalDistance?.doubleValue(for: .meter()), distance > 0 else {
            return nil
        }

        // If we have route data, calculate accurate splits
        if let routePoints = routePoints, routePoints.count > 1 {
            return await calculateSplitsFromRoute(routePoints: routePoints, totalDuration: workout.duration, workout: workout)
        }

        // Otherwise, calculate approximate splits (for indoor workouts without GPS)
        let kilometers = Int(distance / 1000.0)
        guard kilometers > 0 else { return nil }

        let averagePacePerKm = (workout.duration / 60.0) / (distance / 1000.0)
        let timePerKm = averagePacePerKm * 60.0 // seconds per km

        // Build splits with HR data for each km
        var splits: [Split] = []
        for km in 1...kilometers {
            // Calculate time range for this km
            let splitStartTime = workout.startDate.addingTimeInterval(Double(km - 1) * timePerKm)
            let splitEndTime = workout.startDate.addingTimeInterval(Double(km) * timePerKm)

            // Fetch average HR for this split time range
            let heartRate = await fetchAverageHeartRate(for: workout, startDate: splitStartTime, endDate: splitEndTime)
            let power = await fetchAveragePower(for: workout, startDate: splitStartTime, endDate: splitEndTime)

            splits.append(Split(
                kilometer: km,
                distance: 1000.0,
                time: timePerKm,
                pace: averagePacePerKm,
                averageHeartRate: heartRate,
                averagePower: power,
                elevationGain: nil,
                elevationLoss: nil
            ))
        }

        return splits
    }

    private func calculateSplitsFromRoute(routePoints: [RoutePoint], totalDuration: TimeInterval, workout: HKWorkout) async -> [Split] {
        var splits: [Split] = []
        var currentKm = 1
        var kmStartIndex = 0
        var totalDistance = 0.0

        for i in 1..<routePoints.count {
            let point1 = routePoints[i - 1]
            let point2 = routePoints[i]

            let location1 = CLLocation(latitude: point1.coordinate.latitude, longitude: point1.coordinate.longitude)
            let location2 = CLLocation(latitude: point2.coordinate.latitude, longitude: point2.coordinate.longitude)

            totalDistance += location2.distance(from: location1)

            // Check if we've completed a kilometer
            if totalDistance >= Double(currentKm) * 1000.0 {
                let kmEndIndex = i
                let splitPoints = Array(routePoints[kmStartIndex...kmEndIndex])

                let splitDuration = splitPoints.last!.timestamp.timeIntervalSince(splitPoints.first!.timestamp)
                let splitDistance = Double(currentKm) * 1000.0 - Double(currentKm - 1) * 1000.0
                let pace = (splitDuration / 60.0) / (splitDistance / 1000.0)

                // Calculate elevation
                let elevationGain = calculateElevationGain(for: splitPoints)
                let elevationLoss = calculateElevationLoss(for: splitPoints)

                // Get HR and Power for this split time range
                let startDate = splitPoints.first!.timestamp
                let endDate = splitPoints.last!.timestamp

                let heartRate = await fetchAverageHeartRate(for: workout, startDate: startDate, endDate: endDate)
                let power = await fetchAveragePower(for: workout, startDate: startDate, endDate: endDate)

                let split = Split(
                    kilometer: currentKm,
                    distance: splitDistance,
                    time: splitDuration,
                    pace: pace,
                    averageHeartRate: heartRate,
                    averagePower: power,
                    elevationGain: elevationGain,
                    elevationLoss: elevationLoss
                )

                splits.append(split)

                currentKm += 1
                kmStartIndex = i
            }
        }

        // Add final partial split if there's remaining distance
        if kmStartIndex < routePoints.count - 1 {
            let lastSplitPoints = Array(routePoints[kmStartIndex..<routePoints.count])

            // Calculate actual distance for this partial split
            var partialDistance = 0.0
            for i in 1..<lastSplitPoints.count {
                let loc1 = CLLocation(latitude: lastSplitPoints[i-1].coordinate.latitude,
                                     longitude: lastSplitPoints[i-1].coordinate.longitude)
                let loc2 = CLLocation(latitude: lastSplitPoints[i].coordinate.latitude,
                                     longitude: lastSplitPoints[i].coordinate.longitude)
                partialDistance += loc2.distance(from: loc1)
            }

            // Only create split if we have meaningful distance (> 10 meters)
            if partialDistance > 10 {
                let splitDuration = lastSplitPoints.last!.timestamp.timeIntervalSince(lastSplitPoints.first!.timestamp)
                let pace = splitDuration > 0 ? (splitDuration / 60.0) / (partialDistance / 1000.0) : 0

                // Calculate elevation
                let elevationGain = calculateElevationGain(for: lastSplitPoints)
                let elevationLoss = calculateElevationLoss(for: lastSplitPoints)

                // Get HR and Power for this split time range
                let startDate = lastSplitPoints.first!.timestamp
                let endDate = lastSplitPoints.last!.timestamp

                let heartRate = await fetchAverageHeartRate(for: workout, startDate: startDate, endDate: endDate)
                let power = await fetchAveragePower(for: workout, startDate: startDate, endDate: endDate)

                let split = Split(
                    kilometer: currentKm,
                    distance: partialDistance,
                    time: splitDuration,
                    pace: pace,
                    averageHeartRate: heartRate,
                    averagePower: power,
                    elevationGain: elevationGain,
                    elevationLoss: elevationLoss
                )

                splits.append(split)
            }
        }

        return splits
    }

    private func calculateElevationGain(for points: [RoutePoint]) -> Double? {
        guard points.count > 1 else { return nil }

        var gain = 0.0
        for i in 1..<points.count {
            if let alt1 = points[i - 1].altitude, let alt2 = points[i].altitude {
                let diff = alt2 - alt1
                if diff > 0 {
                    gain += diff
                }
            }
        }

        return gain > 0 ? gain : nil
    }

    private func calculateElevationLoss(for points: [RoutePoint]) -> Double? {
        guard points.count > 1 else { return nil }

        var loss = 0.0
        for i in 1..<points.count {
            if let alt1 = points[i - 1].altitude, let alt2 = points[i].altitude {
                let diff = alt2 - alt1
                if diff < 0 {
                    loss += abs(diff)
                }
            }
        }

        return loss > 0 ? loss : nil
    }

    // MARK: - Moving Time

    private func calculateMovingTime(for workout: HKWorkout) -> TimeInterval? {
        // This would require analyzing speed data to determine when the user was stationary
        // For now, return total duration
        return workout.duration
    }

    // MARK: - Split-specific metrics

    private func fetchAverageHeartRate(for workout: HKWorkout, startDate: Date, endDate: Date) async -> Double? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }

                let avgHeartRate = statistics?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: avgHeartRate)
            }

            healthStore.execute(query)
        }
    }

    private func fetchAveragePower(for workout: HKWorkout, startDate: Date, endDate: Date) async -> Double? {
        guard let powerType = HKQuantityType.quantityType(forIdentifier: .runningPower) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: powerType,
                quantitySamplePredicate: predicate,
                options: .discreteAverage
            ) { _, statistics, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }

                let avgPower = statistics?.averageQuantity()?.doubleValue(for: .watt())
                continuation.resume(returning: avgPower)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - First and Last Sample Values

    private func fetchFirstLastHeartRate(for workout: HKWorkout) async -> (first: Double?, last: Double?) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil)
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if error != nil || samples == nil {
                    continuation.resume(returning: (nil, nil))
                    return
                }

                guard let hrSamples = samples as? [HKQuantitySample], !hrSamples.isEmpty else {
                    continuation.resume(returning: (nil, nil))
                    return
                }

                let unit = HKUnit.count().unitDivided(by: .minute())
                let firstHR = hrSamples.first?.quantity.doubleValue(for: unit)
                let lastHR = hrSamples.last?.quantity.doubleValue(for: unit)

                continuation.resume(returning: (firstHR, lastHR))
            }

            healthStore.execute(query)
        }
    }

    private func fetchFirstLastPower(for workout: HKWorkout) async -> (first: Double?, last: Double?) {
        guard let powerType = HKQuantityType.quantityType(forIdentifier: .runningPower) else {
            return (nil, nil)
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: powerType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if error != nil || samples == nil {
                    continuation.resume(returning: (nil, nil))
                    return
                }

                guard let powerSamples = samples as? [HKQuantitySample], !powerSamples.isEmpty else {
                    continuation.resume(returning: (nil, nil))
                    return
                }

                let firstPower = powerSamples.first?.quantity.doubleValue(for: .watt())
                let lastPower = powerSamples.last?.quantity.doubleValue(for: .watt())

                continuation.resume(returning: (firstPower, lastPower))
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Weather Data

    private func extractWeatherData(from workout: HKWorkout) async -> (temperature: Double?, humidity: Double?) {
        // Weather data can be stored in workout metadata
        let temperature = workout.metadata?[HKMetadataKeyWeatherTemperature] as? Double
        let humidity = workout.metadata?[HKMetadataKeyWeatherHumidity] as? Double
        return (temperature, humidity)
    }

    // MARK: - Recovery Metrics

    /// Fetch HRV statistics during sleep period
    /// Returns average, min, and max HRV values during the night
    private func fetchNightHRVStatistics(for sleepData: SleepData?) async -> (average: Double?, min: Double?, max: Double?) {
        guard let sleep = sleepData else {
            return (nil, nil, nil)
        }

        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return (nil, nil, nil)
        }

        // Query HRV samples during sleep period
        let predicate = HKQuery.predicateForSamples(
            withStart: sleep.sleepStart,
            end: sleep.sleepEnd,
            options: .strictStartDate
        )

        do {
            return try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: hrvType,
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if error != nil {
                        continuation.resume(returning: (nil, nil, nil))
                        return
                    }

                    guard let hrvSamples = samples as? [HKQuantitySample], !hrvSamples.isEmpty else {
                        continuation.resume(returning: (nil, nil, nil))
                        return
                    }

                    // Extract HRV values in milliseconds
                    let hrvValues = hrvSamples.map { sample in
                        sample.quantity.doubleValue(for: .secondUnit(with: .milli))
                    }

                    // Calculate statistics
                    let average = hrvValues.reduce(0.0, +) / Double(hrvValues.count)
                    let min = hrvValues.min()
                    let max = hrvValues.max()

                    continuation.resume(returning: (average, min, max))
                }

                self.healthStore.execute(query)
            }
        } catch {
            return (nil, nil, nil)
        }
    }

    func fetchRecoveryMetrics(for date: Date = Date()) async throws -> RecoveryMetrics {
        // Fetch metrics for the given day
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // First, fetch sleep data as we need it for HRV statistics
        let sleep = await fetchSleepDataSafe(for: startOfDay)

        // Load or compute personal baseline
        let baseline = await loadOrComputeBaseline()

        // Now fetch all other metrics in parallel, including HRV statistics based on sleep period
        async let restingHR = fetchLatestQuantitySafe(
            for: .restingHeartRate,
            before: endOfDay,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let hrvStats = fetchNightHRVStatistics(for: sleep)
        async let walkingHR = fetchLatestQuantitySafe(
            for: .walkingHeartRateAverage,
            before: endOfDay,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let respiratoryRate = fetchLatestQuantitySafe(
            for: .respiratoryRate,
            before: endOfDay,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let oxygenSaturation = fetchLatestQuantitySafe(
            for: .oxygenSaturation,
            before: endOfDay,
            unit: .percent()
        )

        let (rhrResult, hrvResult, whrResult, respRateResult, spO2Result) = await (
            restingHR, hrvStats, walkingHR, respiratoryRate, oxygenSaturation
        )

        return RecoveryMetrics(
            date: date,
            restingHeartRate: rhrResult.value,
            hrvAverage: hrvResult.average,
            hrvMin: hrvResult.min,
            hrvMax: hrvResult.max,
            walkingHeartRate: whrResult.value,
            sleepData: sleep,
            respiratoryRate: respRateResult.value,
            oxygenSaturation: spO2Result.value.map { $0 * 100 }, // Convert to percentage
            baseline: baseline
        )
    }

    private func fetchSleepDataSafe(for date: Date) async -> SleepData? {
        do {
            return try await fetchSleepData(for: date)
        } catch {
            return nil
        }
    }

    private func fetchLatestQuantity(
        for identifier: HKQuantityTypeIdentifier,
        before date: Date,
        unit: HKUnit
    ) async throws -> (value: Double?, date: Date?) {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return (nil, nil)
        }

        // Use wider search window for body metrics that are measured infrequently
        let daysBack: Int
        switch identifier {
        case .bodyMass, .bodyFatPercentage, .leanBodyMass, .bodyTemperature:
            daysBack = -365 // 1 year for body metrics
        case .oxygenSaturation:
            daysBack = -30 // 30 days for SpO2
        default:
            daysBack = -7 // 7 days for other metrics
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .day, value: daysBack, to: date),
            end: date,
            options: .strictEndDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                if let sample = samples?.first as? HKQuantitySample {
                    let value = sample.quantity.doubleValue(for: unit)
                    continuation.resume(returning: (value, sample.endDate))
                } else {
                    continuation.resume(returning: (nil, nil))
                }
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Sleep Data

    func fetchSleepData(for date: Date) async throws -> SleepData? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        // Query sleep data with a wide window to capture complete sleep sessions
        // Search from 30 hours before to 18 hours after the start of day
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)

        // Wide search window to ensure we capture full sleep sessions
        let searchStart = calendar.date(byAdding: .hour, value: -30, to: startOfDay)!
        let searchEnd = calendar.date(byAdding: .hour, value: 18, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(
            withStart: searchStart,
            end: searchEnd,
            options: .strictStartDate
        )

        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                let sleepSamples = (samples as? [HKCategorySample]) ?? []
                continuation.resume(returning: sleepSamples)
            }

            healthStore.execute(query)
        }

        guard !samples.isEmpty else { return nil }

        // Group samples into continuous sleep sessions
        let sleepSessions = groupSleepSessions(samples)

        // Find the main sleep session that ends on the morning of the target date
        // Look for sessions ending between 4 AM and 2 PM on the target date
        let morningStart = calendar.date(byAdding: .hour, value: 4, to: startOfDay)!
        let afternoonEnd = calendar.date(byAdding: .hour, value: 14, to: startOfDay)!

        let mainSession = sleepSessions.first { session in
            let sessionEnd = session.last!.endDate
            return sessionEnd >= morningStart && sessionEnd <= afternoonEnd
        }

        // If no session found in morning window, take the session that overlaps most with the target date
        let targetSession = mainSession ?? sleepSessions.max { session1, session2 in
            let overlap1 = calculateOverlap(session: session1, with: startOfDay, calendar: calendar)
            let overlap2 = calculateOverlap(session: session2, with: startOfDay, calendar: calendar)
            return overlap1 < overlap2
        }

        guard let session = targetSession, !session.isEmpty else { return nil }

        // Calculate sleep metrics from the complete session
        var totalSleep: TimeInterval = 0
        var timeInBed: TimeInterval = 0
        var deepSleep: TimeInterval = 0
        var coreSleep: TimeInterval = 0
        var remSleep: TimeInterval = 0
        var awake: TimeInterval = 0

        for sample in session {
            let duration = sample.endDate.timeIntervalSince(sample.startDate)

            if #available(iOS 16.0, *) {
                switch sample.value {
                case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                     HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                     HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                     HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                    totalSleep += duration
                default:
                    break
                }

                switch sample.value {
                case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                    deepSleep += duration
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                    coreSleep += duration
                case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                    remSleep += duration
                case HKCategoryValueSleepAnalysis.awake.rawValue:
                    awake += duration
                case HKCategoryValueSleepAnalysis.inBed.rawValue:
                    timeInBed += duration
                default:
                    break
                }
            } else {
                // iOS 15 and earlier
                switch sample.value {
                case HKCategoryValueSleepAnalysis.asleep.rawValue:
                    totalSleep += duration
                case HKCategoryValueSleepAnalysis.inBed.rawValue:
                    timeInBed += duration
                case HKCategoryValueSleepAnalysis.awake.rawValue:
                    awake += duration
                default:
                    break
                }
            }
        }

        // If timeInBed wasn't recorded, use total sleep + awake time
        if timeInBed == 0 {
            timeInBed = totalSleep + awake
        }

        // Get session start and end times
        let sessionStart = session.first!.startDate
        let sessionEnd = session.last!.endDate

        // Calculate naps: all other sessions during the day (midnight to midnight), excluding main sleep
        let napDuration = calculateNapDuration(
            allSessions: sleepSessions,
            mainSession: session,
            date: date,
            calendar: calendar
        )

        return SleepData(
            date: date,
            sleepStart: sessionStart,
            sleepEnd: sessionEnd,
            totalSleepDuration: totalSleep,
            timeInBed: timeInBed,
            deepSleepDuration: deepSleep > 0 ? deepSleep : nil,
            coreSleepDuration: coreSleep > 0 ? coreSleep : nil,
            remSleepDuration: remSleep > 0 ? remSleep : nil,
            awakeDuration: awake > 0 ? awake : nil,
            napDuration: napDuration > 0 ? napDuration : nil
        )
    }

    // MARK: - Health Profile

    func fetchHealthProfile(for date: Date = Date()) async throws -> HealthProfile {
        // Fetch user characteristics
        let age = try? healthStore.dateOfBirthComponents().year.map { Calendar.current.component(.year, from: Date()) - $0 }
        let biologicalSex = try? healthStore.biologicalSex().biologicalSex

        // Fetch all metrics but don't fail if some are unavailable
        async let bodyMass = fetchLatestQuantitySafe(for: .bodyMass, before: date, unit: .gramUnit(with: .kilo))
        async let bodyFat = fetchLatestQuantitySafe(for: .bodyFatPercentage, before: date, unit: .percent())
        async let leanMass = fetchLatestQuantitySafe(for: .leanBodyMass, before: date, unit: .gramUnit(with: .kilo))

        // Fetch vital signs
        async let spO2 = fetchLatestQuantitySafe(for: .oxygenSaturation, before: date, unit: .percent())
        async let temp = fetchLatestQuantitySafe(for: .bodyTemperature, before: date, unit: .degreeCelsius())
        async let respRate = fetchLatestQuantitySafe(for: .respiratoryRate, before: date, unit: HKUnit.count().unitDivided(by: .minute()))

        // Fetch daily activity
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        async let exerciseTime = fetchSumQuantitySafe(
            for: .appleExerciseTime,
            start: startOfDay,
            end: endOfDay,
            unit: .minute()
        )
        async let standTime = fetchSumQuantitySafe(
            for: .appleStandTime,
            start: startOfDay,
            end: endOfDay,
            unit: .minute()
        )
        async let flights = fetchSumQuantitySafe(
            for: .flightsClimbed,
            start: startOfDay,
            end: endOfDay,
            unit: .count()
        )

        // Fetch cross-training (last 7 days)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: date)!
        async let cyclingDist = fetchSumQuantitySafe(
            for: .distanceCycling,
            start: sevenDaysAgo,
            end: date,
            unit: .meter()
        )
        async let swimmingDist = fetchSumQuantitySafe(
            for: .distanceSwimming,
            start: sevenDaysAgo,
            end: date,
            unit: .meter()
        )

        let (massResult, fatResult, leanResult, oxygenResult, tempResult, respRateResult, exercise, stand, flightsClimbed, cycling, swimming) = await (
            bodyMass, bodyFat, leanMass, spO2, temp, respRate, exerciseTime, standTime, flights, cyclingDist, swimmingDist
        )

        return HealthProfile(
            date: date,
            age: age,
            biologicalSex: biologicalSex,
            bodyMass: massResult.value,
            bodyMassDate: massResult.date,
            bodyFatPercentage: fatResult.value.map { $0 * 100 }, // Convert to percentage
            bodyFatDate: fatResult.date,
            leanBodyMass: leanResult.value,
            leanBodyMassDate: leanResult.date,
            oxygenSaturation: oxygenResult.value.map { $0 * 100 }, // Convert to percentage
            oxygenSaturationDate: oxygenResult.date,
            bodyTemperature: tempResult.value,
            bodyTemperatureDate: tempResult.date,
            respiratoryRate: respRateResult.value,
            respiratoryRateDate: respRateResult.date,
            exerciseTime: exercise,
            standTime: stand,
            flightsClimbed: flightsClimbed.map { Int($0) },
            cyclingDistance: cycling,
            swimmingDistance: swimming
        )
    }

    // Safe versions that don't throw
    private func fetchLatestQuantitySafe(
        for identifier: HKQuantityTypeIdentifier,
        before date: Date,
        unit: HKUnit
    ) async -> (value: Double?, date: Date?) {
        do {
            return try await fetchLatestQuantity(for: identifier, before: date, unit: unit)
        } catch {
            return (nil, nil)
        }
    }

    private func fetchSumQuantitySafe(
        for identifier: HKQuantityTypeIdentifier,
        start: Date,
        end: Date,
        unit: HKUnit
    ) async -> Double? {
        do {
            return try await fetchSumQuantity(for: identifier, start: start, end: end, unit: unit)
        } catch {
            return nil
        }
    }

    private func fetchSumQuantity(
        for identifier: HKQuantityTypeIdentifier,
        start: Date,
        end: Date,
        unit: HKUnit
    ) async throws -> Double? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                let sum = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: sum)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Sleep Session Grouping

    private func groupSleepSessions(_ samples: [HKCategorySample]) -> [[HKCategorySample]] {
        guard !samples.isEmpty else { return [] }

        var sessions: [[HKCategorySample]] = []
        var currentSession: [HKCategorySample] = [samples[0]]

        // Group samples into sessions if they are within 2 hours of each other
        let maxGapBetweenSamples: TimeInterval = 2 * 3600 // 2 hours

        for i in 1..<samples.count {
            let previousSample = samples[i - 1]
            let currentSample = samples[i]

            let gap = currentSample.startDate.timeIntervalSince(previousSample.endDate)

            if gap <= maxGapBetweenSamples {
                // Same session - add to current
                currentSession.append(currentSample)
            } else {
                // New session - save current and start new one
                sessions.append(currentSession)
                currentSession = [currentSample]
            }
        }

        // Don't forget the last session
        if !currentSession.isEmpty {
            sessions.append(currentSession)
        }

        return sessions
    }

    private func calculateOverlap(session: [HKCategorySample], with targetDate: Date, calendar: Calendar) -> TimeInterval {
        guard !session.isEmpty else { return 0 }

        let sessionStart = session.first!.startDate
        let sessionEnd = session.last!.endDate
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: targetDate)!

        // Calculate overlap between session and target day
        let overlapStart = max(sessionStart, targetDate)
        let overlapEnd = min(sessionEnd, dayEnd)

        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }

    private func calculateNapDuration(
        allSessions: [[HKCategorySample]],
        mainSession: [HKCategorySample],
        date: Date,
        calendar: Calendar
    ) -> TimeInterval {
        // Define the day boundaries (midnight to midnight)
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        // Get main sleep session boundaries
        let mainSleepStart = mainSession.first!.startDate
        let mainSleepEnd = mainSession.last!.endDate

        var totalNapDuration: TimeInterval = 0

        // Process all sessions except the main sleep session
        for session in allSessions {
            // Skip the main session
            if session.first?.startDate == mainSession.first?.startDate &&
               session.last?.endDate == mainSession.last?.endDate {
                continue
            }

            let sessionStart = session.first!.startDate
            let sessionEnd = session.last!.endDate

            // Calculate overlap with the day (midnight to midnight)
            let dayOverlapStart = max(sessionStart, startOfDay)
            let dayOverlapEnd = min(sessionEnd, endOfDay)

            // Skip if no overlap with the day
            guard dayOverlapEnd > dayOverlapStart else { continue }

            // Calculate overlap with main sleep session
            let sleepOverlapStart = max(dayOverlapStart, mainSleepStart)
            let sleepOverlapEnd = min(dayOverlapEnd, mainSleepEnd)

            // If there's overlap with main sleep, we need to exclude it
            if sleepOverlapEnd > sleepOverlapStart {
                // Session overlaps with both day and main sleep
                // Calculate the parts that don't overlap with main sleep

                // Part before main sleep
                if dayOverlapStart < sleepOverlapStart {
                    totalNapDuration += calculateSleepTime(in: session, from: dayOverlapStart, to: sleepOverlapStart)
                }

                // Part after main sleep
                if dayOverlapEnd > sleepOverlapEnd {
                    totalNapDuration += calculateSleepTime(in: session, from: sleepOverlapEnd, to: dayOverlapEnd)
                }
            } else {
                // No overlap with main sleep, count the entire duration
                totalNapDuration += calculateSleepTime(in: session, from: dayOverlapStart, to: dayOverlapEnd)
            }
        }

        return totalNapDuration
    }

    private func calculateSleepTime(in session: [HKCategorySample], from start: Date, to end: Date) -> TimeInterval {
        var totalSleep: TimeInterval = 0

        for sample in session {
            let sampleStart = sample.startDate
            let sampleEnd = sample.endDate

            // Calculate overlap with our time range
            let overlapStart = max(sampleStart, start)
            let overlapEnd = min(sampleEnd, end)

            guard overlapEnd > overlapStart else { continue }

            // Only count actual sleep, not "in bed" or "awake"
            if #available(iOS 16.0, *) {
                switch sample.value {
                case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                     HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                     HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                     HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                    totalSleep += overlapEnd.timeIntervalSince(overlapStart)
                default:
                    break
                }
            } else {
                // iOS 15 and earlier
                if sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue {
                    totalSleep += overlapEnd.timeIntervalSince(overlapStart)
                }
            }
        }

        return totalSleep
    }

    // MARK: - Essential Metrics for Historical Indexation

    /// Fetch essential metrics for a workout optimized for bulk historical analysis
    /// Returns key metrics: HR, cadence, VO2Max, elevation
    func fetchEssentialMetrics(for workoutModel: WorkoutModel) async throws -> (
        heartRate: (avg: Double?, min: Double?, max: Double?)?,
        cadence: Int?,
        vo2Max: Double?,
        elevation: Double?
    ) {
        // Find the original HKWorkout
        guard let workout = try await findWorkout(with: workoutModel.id) else {
            return (nil, nil, nil, nil)
        }

        // Fetch metrics in parallel for efficiency
        async let heartRateData = fetchHeartRateData(for: workout)
        async let stepCountData = fetchStepCount(for: workout)
        async let vo2MaxData = fetchVO2Max(around: workoutModel.startDate)
        async let elevationData = fetchElevation(for: workout)

        let (hr, steps, vo2Max, elevation) = try await (
            heartRateData, stepCountData, vo2MaxData, elevationData
        )

        // Calculate cadence from steps
        let cadence = calculateCadence(steps: steps, duration: workout.duration)

        return (
            heartRate: (avg: hr.average, min: hr.min, max: hr.max),
            cadence: cadence.map { Int($0.rounded()) },
            vo2Max: vo2Max,
            elevation: elevation.ascent
        )
    }

    // MARK: - Personal Baseline Computation

    /// Fetch historical data and compute personal baseline
    /// Uses rolling 14-day window for averages
    func computePersonalBaseline(days: Int = 14) async throws -> PersonalBaseline {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate)!

        // Fetch all historical data points in parallel
        async let rhrHistory = fetchQuantityHistory(
            for: .restingHeartRate,
            start: startDate,
            end: endDate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let hrvHistory = fetchQuantityHistory(
            for: .heartRateVariabilitySDNN,
            start: startDate,
            end: endDate,
            unit: .secondUnit(with: .milli)
        )
        async let walkingHRHistory = fetchQuantityHistory(
            for: .walkingHeartRateAverage,
            start: startDate,
            end: endDate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let respRateHistory = fetchQuantityHistory(
            for: .respiratoryRate,
            start: startDate,
            end: endDate,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let spO2History = fetchQuantityHistory(
            for: .oxygenSaturation,
            start: startDate,
            end: endDate,
            unit: .percent()
        )
        async let sleepHistory = fetchSleepHistory(start: startDate, end: endDate)

        let (rhr, hrv, whr, resp, spo2, sleep) = await (
            rhrHistory, hrvHistory, walkingHRHistory, respRateHistory, spO2History, sleepHistory
        )

        // Compute statistics
        let rhrStats = computeStatistics(rhr)
        let hrvStats = computeStatistics(hrv)
        let whrStats = computeStatistics(whr)
        let respStats = computeStatistics(resp)
        let spO2Stats = computeStatistics(spo2.map { $0 * 100 }) // Convert to percentage
        let sleepStats = computeSleepStatistics(sleep)

        let dataPointCount = max(rhr.count, hrv.count, sleep.count)

        return PersonalBaseline(
            id: UUID(),
            computedAt: Date(),
            dataPointCount: dataPointCount,
            restingHeartRateAverage: rhrStats.average,
            restingHeartRateStdDev: rhrStats.stdDev,
            hrvAverage: hrvStats.average,
            hrvStdDev: hrvStats.stdDev,
            walkingHeartRateAverage: whrStats.average,
            walkingHeartRateStdDev: whrStats.stdDev,
            respiratoryRateAverage: respStats.average,
            respiratoryRateStdDev: respStats.stdDev,
            oxygenSaturationAverage: spO2Stats.average,
            oxygenSaturationStdDev: spO2Stats.stdDev,
            sleepDurationAverage: sleepStats.durationAverage,
            sleepEfficiencyAverage: sleepStats.efficiencyAverage,
            deepSleepPercentageAverage: sleepStats.deepPercentAverage,
            remSleepPercentageAverage: sleepStats.remPercentAverage
        )
    }

    /// Load existing baseline or compute new one if needed
    func loadOrComputeBaseline() async -> PersonalBaseline? {
        let storage = PersonalBaselineStorage.shared

        if !storage.needsRefresh(), let existing = storage.load() {
            return existing
        }

        // Compute new baseline
        do {
            let newBaseline = try await computePersonalBaseline()
            storage.save(newBaseline)
            return newBaseline
        } catch {
            return storage.load() // Return stale baseline if computation fails
        }
    }

    /// Fetch all quantity samples in a date range
    private func fetchQuantityHistory(
        for identifier: HKQuantityTypeIdentifier,
        start: Date,
        end: Date,
        unit: HKUnit
    ) async -> [Double] {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?.map {
                    $0.quantity.doubleValue(for: unit)
                } ?? []
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    /// Fetch sleep data for multiple days
    private func fetchSleepHistory(start: Date, end: Date) async -> [SleepData] {
        var sleepDataList: [SleepData] = []
        let calendar = Calendar.current
        var currentDate = start

        while currentDate < end {
            if let sleepData = await fetchSleepDataSafe(for: currentDate) {
                sleepDataList.append(sleepData)
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return sleepDataList
    }

    /// Compute mean and standard deviation
    private func computeStatistics(_ values: [Double]) -> (average: Double?, stdDev: Double?) {
        guard !values.isEmpty else { return (nil, nil) }

        let mean = values.reduce(0, +) / Double(values.count)

        guard values.count > 1 else { return (mean, nil) }

        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count - 1)
        let stdDev = sqrt(variance)

        return (mean, stdDev)
    }

    /// Compute sleep-specific statistics
    private func computeSleepStatistics(_ sleepList: [SleepData]) -> (
        durationAverage: TimeInterval?,
        efficiencyAverage: Double?,
        deepPercentAverage: Double?,
        remPercentAverage: Double?
    ) {
        guard !sleepList.isEmpty else {
            return (nil, nil, nil, nil)
        }

        let durations = sleepList.map { $0.totalSleepDuration }
        let efficiencies = sleepList.map { $0.sleepEfficiency }

        let deepPercents = sleepList.compactMap { sleep -> Double? in
            guard let deep = sleep.deepSleepDuration, sleep.totalSleepDuration > 0 else { return nil }
            return (deep / sleep.totalSleepDuration) * 100
        }

        let remPercents = sleepList.compactMap { sleep -> Double? in
            guard let rem = sleep.remSleepDuration, sleep.totalSleepDuration > 0 else { return nil }
            return (rem / sleep.totalSleepDuration) * 100
        }

        return (
            durations.reduce(0, +) / Double(durations.count),
            efficiencies.reduce(0, +) / Double(efficiencies.count),
            deepPercents.isEmpty ? nil : deepPercents.reduce(0, +) / Double(deepPercents.count),
            remPercents.isEmpty ? nil : remPercents.reduce(0, +) / Double(remPercents.count)
        )
    }

    // MARK: - Save Workout to HealthKit (FIT Import)

    /// Save a parsed FIT workout to HealthKit using HKWorkoutBuilder
    /// Returns the created HKWorkout on success, nil on failure
    nonisolated func saveWorkoutToHealthKit(from parsed: ParsedSuuntoWorkout) async throws -> HKWorkout {
        let healthStore = self.healthStore
        let activityType = workoutActivityType(from: parsed.activityType)
        let isIndoor = parsed.routeCoordinates.isEmpty

        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        config.locationType = isIndoor ? .indoor : .outdoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: nil)

        try await builder.beginCollection(at: parsed.startDate)

        // Build all quantity samples
        var samples: [HKQuantitySample] = []

        // Distance
        if parsed.distance > 0 {
            let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
            let distanceQuantity = HKQuantity(unit: .meter(), doubleValue: parsed.distance)
            let distanceSample = HKQuantitySample(
                type: distanceType,
                quantity: distanceQuantity,
                start: parsed.startDate,
                end: parsed.endDate
            )
            samples.append(distanceSample)
        }

        // Calories
        if parsed.calories > 0 {
            let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
            let caloriesQuantity = HKQuantity(unit: .kilocalorie(), doubleValue: parsed.calories)
            let caloriesSample = HKQuantitySample(
                type: caloriesType,
                quantity: caloriesQuantity,
                start: parsed.startDate,
                end: parsed.endDate
            )
            samples.append(caloriesSample)
        }

        // Heart rate samples
        let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        for hrSample in parsed.heartRateSamples {
            let quantity = HKQuantity(unit: bpmUnit, doubleValue: hrSample.bpm)
            let sample = HKQuantitySample(
                type: hrType,
                quantity: quantity,
                start: hrSample.date,
                end: hrSample.date
            )
            samples.append(sample)
        }

        // Power samples
        let powerType = HKQuantityType.quantityType(forIdentifier: .runningPower)!
        for powerSample in parsed.powerSamples {
            let quantity = HKQuantity(unit: .watt(), doubleValue: powerSample.watts)
            let sample = HKQuantitySample(
                type: powerType,
                quantity: quantity,
                start: powerSample.date,
                end: powerSample.date
            )
            samples.append(sample)
        }

        // Cadence → step count per interval
        if parsed.cadenceSamples.count >= 2 {
            let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
            for i in 1..<parsed.cadenceSamples.count {
                let prev = parsed.cadenceSamples[i - 1]
                let curr = parsed.cadenceSamples[i]
                let intervalMinutes = curr.date.timeIntervalSince(prev.date) / 60.0
                guard intervalMinutes > 0 else { continue }
                let steps = prev.spm * intervalMinutes
                let quantity = HKQuantity(unit: .count(), doubleValue: steps)
                let sample = HKQuantitySample(
                    type: stepType,
                    quantity: quantity,
                    start: prev.date,
                    end: curr.date
                )
                samples.append(sample)
            }
        }

        // Average speed
        if let avgSpeed = parsed.averageSpeed, avgSpeed > 0 {
            let speedType = HKQuantityType.quantityType(forIdentifier: .runningSpeed)!
            let speedUnit = HKUnit.meter().unitDivided(by: .second())
            let quantity = HKQuantity(unit: speedUnit, doubleValue: avgSpeed)
            let sample = HKQuantitySample(
                type: speedType,
                quantity: quantity,
                start: parsed.startDate,
                end: parsed.endDate
            )
            samples.append(sample)
        }

        // Average ground contact time
        if let gct = parsed.averageGroundContactTime, gct > 0 {
            let gctType = HKQuantityType.quantityType(forIdentifier: .runningGroundContactTime)!
            let msUnit = HKUnit.secondUnit(with: .milli)
            let quantity = HKQuantity(unit: msUnit, doubleValue: gct)
            let sample = HKQuantitySample(
                type: gctType,
                quantity: quantity,
                start: parsed.startDate,
                end: parsed.endDate
            )
            samples.append(sample)
        }

        // Average vertical oscillation
        if let vo = parsed.averageVerticalOscillation, vo > 0 {
            let voType = HKQuantityType.quantityType(forIdentifier: .runningVerticalOscillation)!
            let cmUnit = HKUnit.meterUnit(with: .centi)
            let quantity = HKQuantity(unit: cmUnit, doubleValue: vo)
            let sample = HKQuantitySample(
                type: voType,
                quantity: quantity,
                start: parsed.startDate,
                end: parsed.endDate
            )
            samples.append(sample)
        }

        // Average stride length
        if let stride = parsed.averageStrideLength, stride > 0 {
            let strideType = HKQuantityType.quantityType(forIdentifier: .runningStrideLength)!
            let quantity = HKQuantity(unit: .meter(), doubleValue: stride)
            let sample = HKQuantitySample(
                type: strideType,
                quantity: quantity,
                start: parsed.startDate,
                end: parsed.endDate
            )
            samples.append(sample)
        }

        // Add all samples in one batch
        if !samples.isEmpty {
            try await builder.addSamples(samples)
        }

        // Metadata
        var metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: isIndoor,
        ]
        let externalUUID = "\(parsed.startDate.timeIntervalSince1970)-\(parsed.duration)"
        metadata[HKMetadataKeyExternalUUID] = externalUUID
        if !parsed.deviceName.isEmpty {
            metadata[HKMetadataKeyDeviceName] = parsed.deviceName
        }

        try await builder.addMetadata(metadata)

        try await builder.endCollection(at: parsed.endDate)

        guard let workout = try await builder.finishWorkout() else {
            throw HealthKitError.dataNotAvailable
        }

        // Attach GPS route if available
        if !parsed.routeCoordinates.isEmpty {
            let locations = buildCLLocations(from: parsed)
            if !locations.isEmpty {
                let routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
                try await routeBuilder.insertRouteData(locations)
                try await routeBuilder.finishRoute(with: workout, metadata: nil)
            }
        }

        print("✅ Saved workout to HealthKit: \(workout.uuid)")
        return workout
    }

    // MARK: - Helpers for HealthKit Write

    private nonisolated func workoutActivityType(from activityString: String) -> HKWorkoutActivityType {
        let lower = activityString.lowercased()
        if lower.contains("run") { return .running }
        if lower.contains("trail") { return .running }
        if lower.contains("cycl") || lower.contains("bik") { return .cycling }
        if lower.contains("swim") { return .swimming }
        if lower.contains("walk") || lower.contains("hik") { return .walking }
        if lower.contains("cross") { return .crossTraining }
        return .running
    }

    private nonisolated func buildCLLocations(from parsed: ParsedSuuntoWorkout) -> [CLLocation] {
        let coords = parsed.routeCoordinates
        guard !coords.isEmpty else { return [] }

        let altitudes = parsed.altitudeSamples
        let totalDuration = parsed.endDate.timeIntervalSince(parsed.startDate)
        let count = coords.count

        return coords.enumerated().map { index, coord in
            let fraction = count > 1 ? Double(index) / Double(count - 1) : 0
            let timestamp = parsed.startDate.addingTimeInterval(totalDuration * fraction)

            // Find closest altitude sample or interpolate
            let altitude: CLLocationDistance
            if index < altitudes.count {
                altitude = altitudes[index].meters
            } else if !altitudes.isEmpty {
                let altIndex = min(Int(fraction * Double(altitudes.count - 1)), altitudes.count - 1)
                altitude = altitudes[altIndex].meters
            } else {
                altitude = 0
            }

            return CLLocation(
                coordinate: coord,
                altitude: altitude,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: timestamp
            )
        }
    }
}
