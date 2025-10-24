//
//  HealthKitManager.swift
//  HealthApp
//
//  Service layer for interacting with HealthKit
//

import Foundation
import HealthKit
import CoreLocation
import Combine

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

        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
    }

    /// Check if we can access HealthKit data by attempting a simple query
    /// This is more reliable than checking authorizationStatus for read permissions
    func checkDataAccess() async -> Bool {
        do {
            _ = try await fetchRunningWorkouts()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Fetch Running Workouts

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

    // MARK: - Fetch Workout Details

    func fetchWorkoutMetrics(for workoutModel: WorkoutModel) async throws -> WorkoutMetrics {
        // Find the original HKWorkout
        guard let workout = try await findWorkout(with: workoutModel.id) else {
            throw HealthKitError.dataNotAvailable
        }

        // Fetch all metrics in parallel
        async let heartRateData = fetchHeartRateData(for: workout)
        async let paceData = fetchPaceData(for: workout)
        async let stepCountData = fetchStepCount(for: workout)
        async let strideLengthData = fetchStrideLength(for: workout)
        async let powerData = fetchRunningPower(for: workout)
        async let elevationData = fetchElevation(for: workout)
        async let routeData = fetchRoute(for: workout)
        async let vo2MaxData = fetchVO2Max(around: workoutModel.startDate)
        async let advancedMetrics = fetchAdvancedRunningMetrics(for: workout)
        async let mobilityMetrics = fetchMobilityMetrics(for: workout)
        async let weatherData = extractWeatherData(from: workout)

        let steps = await stepCountData
        let weather = await weatherData
        let mobility = await mobilityMetrics
        let (hr, pace, stride, power, elevation, route, vo2Max, advanced) = try await (
            heartRateData, paceData, strideLengthData, powerData,
            elevationData, routeData, vo2MaxData, advancedMetrics
        )

        // Calculate cadence from steps
        let cadence = calculateCadence(steps: steps, duration: workout.duration)

        // Calculate elevation from route if not available
        let finalElevation: (ascent: Double?, descent: Double?)
        if elevation.ascent == nil && elevation.descent == nil, let route = route {
            finalElevation = calculateElevationFromRoute(route)
        } else {
            finalElevation = elevation
        }

        // Calculate splits
        let splits = try await calculateSplits(for: workout, routePoints: route)

        return WorkoutMetrics(
            workout: workoutModel,
            averageHeartRate: hr.average,
            minHeartRate: hr.min,
            maxHeartRate: hr.max,
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
            totalElevationAscent: finalElevation.ascent,
            totalElevationDescent: finalElevation.descent,
            splits: splits,
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

    // MARK: - Helper: Find Workout by UUID

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

    // MARK: - Heart Rate

    private func fetchHeartRateData(for workout: HKWorkout) async throws -> (
        average: Double?, min: Double?, max: Double?, zones: HeartRateZones?
    ) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return (nil, nil, nil, nil)
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: heartRateType,
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMin, .discreteMax]
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error))
                    return
                }

                let average = statistics?.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                let min = statistics?.minimumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                let max = statistics?.maximumQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

                // Calculate zones if we have max HR
                let zones: HeartRateZones? = max.map { maxHR in
                    // Simplified zone calculation - ideally use user's actual max HR
                    HeartRateZones(
                        zone1: nil, // Would need detailed sample analysis
                        zone2: nil,
                        zone3: nil,
                        zone4: nil,
                        zone5: nil,
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

        // Otherwise, calculate approximate splits
        let kilometers = Int(distance / 1000.0)
        guard kilometers > 0 else { return nil }

        let averagePacePerKm = (workout.duration / 60.0) / (distance / 1000.0)

        return (1...kilometers).map { km in
            Split(
                kilometer: km,
                distance: 1000.0,
                time: averagePacePerKm * 60.0,
                pace: averagePacePerKm,
                averageHeartRate: nil,
                averagePower: nil,
                elevationGain: nil,
                elevationLoss: nil
            )
        }
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

    // MARK: - Weather Data

    private func extractWeatherData(from workout: HKWorkout) async -> (temperature: Double?, humidity: Double?) {
        // Weather data can be stored in workout metadata
        let temperature = workout.metadata?[HKMetadataKeyWeatherTemperature] as? Double
        let humidity = workout.metadata?[HKMetadataKeyWeatherHumidity] as? Double
        return (temperature, humidity)
    }

    // MARK: - Recovery Metrics

    func fetchRecoveryMetrics(for date: Date = Date()) async throws -> RecoveryMetrics {
        // Fetch metrics for the given day
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        async let restingHR = fetchLatestQuantitySafe(
            for: .restingHeartRate,
            before: endOfDay,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        async let hrv = fetchLatestQuantitySafe(
            for: .heartRateVariabilitySDNN,
            before: endOfDay,
            unit: .secondUnit(with: .milli)
        )
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
        async let sleepData = fetchSleepDataSafe(for: startOfDay)

        let (rhrResult, hrvResult, whrResult, respRateResult, sleep) = await (restingHR, hrv, walkingHR, respiratoryRate, sleepData)

        return RecoveryMetrics(
            date: date,
            restingHeartRate: rhrResult.value,
            hrv: hrvResult.value,
            walkingHeartRate: whrResult.value,
            sleepData: sleep,
            respiratoryRate: respRateResult.value
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
}
