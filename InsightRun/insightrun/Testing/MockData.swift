//
//  MockData.swift
//  InsightRun
//
//  Comprehensive mock data for demo mode and previews
//

import CoreLocation
import Foundation
import HealthKit

enum MockData {

    // MARK: - Helpers

    private static let calendar = Calendar.current
    private static let now = Date()

    private static var isFrench: Bool { AppLanguage.current == "fr" }

    private static func localized(_ en: String, _ fr: String) -> String {
        isFrench ? fr : en
    }

    private static func date(daysAgo: Int, hour: Int = 7, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private static func daysAgo(_ date: Date) -> Int {
        max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0)
    }

    // Deterministic noise in -1...1 so every launch renders the same screens.
    private static func wave(_ seed: Int, _ salt: Double = 1.37) -> Double {
        sin(Double(seed) * salt + salt)
    }

    // MARK: - Sample Workouts

    enum RunKind {
        case easy, intervals, tempo, long, recovery, race
    }

    private struct RunSpec {
        let daysAgo: Int
        let hour: Int
        let minute: Int
        let kind: RunKind
        let distanceKm: Double
        let pace: Double
        let heartRate: Double
        let isIndoor: Bool
        let name: String
    }

    private static let historyDays = 150

    private static let runSpecs: [RunSpec] = (0..<historyDays).compactMap { daysAgo in
        let weekday = calendar.component(.weekday, from: date(daysAgo: daysAgo))
        let week = daysAgo / 7
        let fatigue = Double(daysAgo) / Double(historyDays)
        let noise = wave(daysAgo)

        if weekday == 1, (33...39).contains(daysAgo) {
            return RunSpec(
                daysAgo: daysAgo, hour: 9, minute: 0, kind: .race, distanceKm: 21.1, pace: 4.73,
                heartRate: 171, isIndoor: false,
                name: localized("Boulogne Half Marathon", "Semi-marathon de Boulogne"))
        }
        if weekday == 1, (82...88).contains(daysAgo) {
            return RunSpec(
                daysAgo: daysAgo, hour: 9, minute: 30, kind: .race, distanceKm: 10, pace: 4.68,
                heartRate: 176, isIndoor: false,
                name: localized("Vincennes 10K", "10 km de Vincennes"))
        }
        // A quiet holiday week keeps the history believable.
        if week == 6 || week == 7, weekday != 1 { return nil }

        switch weekday {
        case 2:
            return RunSpec(
                daysAgo: daysAgo, hour: 7, minute: 0, kind: .easy, distanceKm: 8 + noise * 0.8,
                pace: 5.78 + 0.3 * fatigue + noise * 0.05, heartRate: 143 - 5 * (1 - fatigue) + noise * 2,
                isIndoor: false, name: localized("Easy run", "Footing"))
        case 4:
            let hour = daysAgo == 0 ? 7 : 18
            if week % 2 == 0 {
                return RunSpec(
                    daysAgo: daysAgo, hour: hour, minute: 30, kind: .intervals, distanceKm: 9 + noise * 0.4,
                    pace: 4.62 + 0.16 * fatigue, heartRate: 166 - 3 * (1 - fatigue) + noise * 2,
                    isIndoor: false, name: localized("Intervals 6 × 800 m", "Fractionné 6 × 800 m"))
            }
            return RunSpec(
                daysAgo: daysAgo, hour: hour, minute: 30, kind: .tempo, distanceKm: 10 + noise * 0.5,
                pace: 5.02 + 0.22 * fatigue, heartRate: 162 - 4 * (1 - fatigue) + noise * 2,
                isIndoor: false, name: localized("Tempo run", "Allure seuil"))
        case 5 where week % 2 == 1:
            return RunSpec(
                daysAgo: daysAgo, hour: 19, minute: 0, kind: .recovery, distanceKm: 6 + noise * 0.5,
                pace: 6.15 + 0.15 * fatigue, heartRate: 133 + noise * 2, isIndoor: week % 4 == 1,
                name: localized("Recovery run", "Footing de récupération"))
        case 7 where week % 3 != 2:
            return RunSpec(
                daysAgo: daysAgo, hour: 8, minute: 30, kind: .easy, distanceKm: 10 + noise,
                pace: 5.72 + 0.28 * fatigue + noise * 0.05, heartRate: 146 - 4 * (1 - fatigue) + noise * 2,
                isIndoor: false, name: localized("Saturday run", "Sortie du samedi"))
        case 1:
            return RunSpec(
                daysAgo: daysAgo, hour: 9, minute: 0, kind: .long, distanceKm: 13 + 7 * (1 - fatigue) + noise * 0.6,
                pace: 5.62 + 0.25 * fatigue, heartRate: 150 - 4 * (1 - fatigue) + noise * 2,
                isIndoor: false, name: localized("Long run", "Sortie longue"))
        default:
            return nil
        }
    }

    static let sampleWorkouts: [WorkoutModel] = runSpecs.enumerated().map { index, spec in
        let duration = (spec.distanceKm * spec.pace * 60).rounded()
        let start = date(daysAgo: spec.daysAgo, hour: spec.hour, minute: spec.minute)
        let maxOffset: Double = switch spec.kind {
        case .intervals: 21
        case .race: 13
        case .tempo: 12
        case .long: 14
        case .easy, .recovery: 10
        }
        return WorkoutModel(
            id: UUID(uuidString: String(format: "D3A0C0DE-0000-4000-8000-%012d", index))!,
            workoutType: .running,
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            duration: duration,
            distance: (spec.distanceKm * 1000).rounded(),
            totalEnergyBurned: (spec.distanceKm * 64).rounded(),
            sourceName: "Apple Watch",
            sourceVersion: "26.0",
            metadata: ["display_name": spec.name, "demo_kind": "\(spec.kind)"],
            averageHeartRate: spec.heartRate.rounded(),
            maxHeartRate: (spec.heartRate + maxOffset).rounded(),
            elevationGain: spec.isIndoor ? nil : (spec.distanceKm * 5 + wave(index, 2.1) * 12).rounded(),
            hasRoute: !spec.isIndoor,
            isIndoor: spec.isIndoor
        )
    }

    static var sampleOfficialRaces: [OfficialRace] {
        sampleWorkouts.filter { $0.metadata?["demo_kind"] as? String == "race" }.map { workout in
            OfficialRace(
                id: workout.id, identifiers: workout.raceIdentifiers, date: workout.startDate,
                name: workout.raceDisplayName, distance: workout.distance, duration: workout.duration)
        }
    }

    static var sampleWorkoutNames: [WorkoutNameOverride] {
        sampleWorkouts.compactMap { workout in
            guard let name = workout.metadata?["display_name"] as? String else { return nil }
            return WorkoutNameOverride(id: workout.id, identifiers: workout.raceIdentifiers, name: name, updatedAt: workout.endDate)
        }
    }

    private static func kind(of workout: WorkoutModel) -> RunKind {
        switch workout.metadata?["demo_kind"] as? String {
        case "intervals": .intervals
        case "tempo": .tempo
        case "long": .long
        case "recovery": .recovery
        case "race": .race
        default: .easy
        }
    }

    static var activationWorkout: WorkoutModel {
        WorkoutModel(
            id: UUID(),
            workoutType: .running,
            startDate: date(daysAgo: 1, hour: 7, minute: 30),
            endDate: date(daysAgo: 1, hour: 8, minute: 18),
            duration: 2880,
            distance: 10000,
            totalEnergyBurned: 620,
            sourceName: "Insight Run Sample",
            sourceVersion: nil,
            metadata: ["is_sample": true],
            averageHeartRate: 172,
            maxHeartRate: 188,
            elevationGain: 42,
            hasRoute: false,
            isIndoor: false
        )
    }

    // MARK: - Sample Sleep Data

    static let sampleSleepData: SleepData = sampleSleep(daysAgo: 0)

    // Minutes of sleep and minutes awake in bed, one entry per night going back from last night.
    private static let sleepNights: [(sleep: Int, awake: Int)] = [
        (465, 45), (402, 38), (441, 95), (376, 30), (452, 42), (428, 88), (489, 35),
        (398, 70), (447, 40), (352, 44), (471, 36), (430, 52), (415, 105), (458, 41),
    ]

    private static func sampleSleep(daysAgo: Int) -> SleepData {
        let nightDate = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        let night = sleepNights[daysAgo % sleepNights.count]
        let totalSleep = TimeInterval(night.sleep * 60)
        let awake = TimeInterval(night.awake * 60)
        let sleepEnd = calendar.date(bySettingHour: 6, minute: 45, second: 0, of: nightDate)!
        let sleepStart = sleepEnd.addingTimeInterval(-(totalSleep + awake))

        return SleepData(
            date: nightDate,
            sleepStart: sleepStart,
            sleepEnd: sleepEnd,
            totalSleepDuration: totalSleep,
            timeInBed: totalSleep + awake,
            deepSleepDuration: totalSleep * 0.19,
            coreSleepDuration: totalSleep * 0.55,
            remSleepDuration: totalSleep * 0.26,
            awakeDuration: awake,
            napDuration: nil
        )
    }

    static func sampleSleepHistory(start: Date, end: Date) -> [SleepData] {
        var nights: [SleepData] = []
        var cursor = end
        while cursor >= start {
            nights.append(sampleSleep(daysAgo: daysAgo(cursor)))
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return nights
    }

    // MARK: - Sample Recovery Metrics

    static let sampleRecoveryMetrics: RecoveryMetrics = recoveryMetrics(for: now)

    static func recoveryMetrics(for date: Date) -> RecoveryMetrics {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MISSING_METRICS_UI_TEST") {
            return RecoveryMetrics(
                date: date, restingHeartRate: 0, hrvAverage: 65,
                respiratoryRate: 0)
        }
        #endif
        let offset = daysAgo(date)
        let today = offset == 0
        let hrv = today ? 65 : (61 + 5 * wave(offset, 0.9) - Double(offset) * 0.08).rounded()
        return RecoveryMetrics(
            date: date,
            restingHeartRate: today ? 52 : (54 + 2 * wave(offset, 1.3) + Double(offset) * 0.03).rounded(),
            hrvAverage: hrv,
            hrvMin: hrv - 23,
            hrvMax: hrv + 23,
            walkingHeartRate: today ? 78 : (80 + 3 * wave(offset, 0.7)).rounded(),
            sleepData: sampleSleep(daysAgo: offset),
            respiratoryRate: today ? 14 : ((14.4 + 0.5 * wave(offset, 1.1)) * 10).rounded() / 10,
            oxygenSaturation: today ? 98 : (97 + wave(offset, 1.9)).rounded(),
            baseline: samplePersonalBaseline,
            rmssd: sampleRMSSD(for: date))
    }

    private static func sampleRMSSD(for date: Date) -> RMSSDTrend {
        let day = calendar.startOfDay(for: date)
        let values: [Double] = [80, 84, 82, 89, 83, 88, 85, 87, 86]
        let nights = values.enumerated().map { offset, value in
            RMSSDTrend.Night(
                date: calendar.date(byAdding: .day, value: offset - 8, to: day)!.ISO8601Format(),
                median: value, sampleCount: 65)
        }
        return RMSSDTrend(
            metric: "RMSSD", context: "asleep", source: "demo", sourceChanged: false,
            latestSampleAt: day.ISO8601Format(), measuredAt: day.ISO8601Format(),
            currentNight: nights.last, baselineMedian: 84.5, baselineNights: 8,
            recentMedian: 86, recentNights: 7, nights: nights)
    }
    // MARK: - Sample Health Profile

    static let sampleHealthProfile: HealthProfile = HealthProfile(
        date: now,
        age: 32,
        biologicalSex: .male,
        bodyMass: 75.0,
        bodyMassDate: calendar.date(byAdding: .day, value: -1, to: now),
        bodyFatPercentage: 14.5,
        bodyFatDate: calendar.date(byAdding: .day, value: -3, to: now),
        leanBodyMass: 64.1,
        leanBodyMassDate: calendar.date(byAdding: .day, value: -3, to: now),
        oxygenSaturation: 98,
        oxygenSaturationDate: now,
        bodyTemperature: 36.6,
        bodyTemperatureDate: now,
        respiratoryRate: 14,
        respiratoryRateDate: now,
        exerciseTime: 45,
        standTime: 660,
        flightsClimbed: 8,
        cyclingDistance: 35000,
        swimmingDistance: 2000
    )

    // MARK: - Sample Race Goal

    private static let planStartDate: Date = {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -(mondayOffset + 21), to: today)!
    }()

    static let sampleRaceGoal: RaceGoal = RaceGoal(
        id: UUID(uuidString: "D3A0C0DE-0000-4000-9000-000000000001")!,
        raceType: .tenK,
        raceName: localized("Paris 10K", "10 km de Paris"),
        targetDate: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: calendar.date(byAdding: .day, value: 62, to: planStartDate)!)!,
        fitnessLevel: .intermediate,
        trainingPlan: sampleTrainingPlan,
        createdAt: calendar.date(byAdding: .day, value: -2, to: planStartDate)!,
        trainingDaysPerWeek: 4,
        preferredDays: [.monday, .wednesday, .saturday, .sunday],
        targetTime: 44 * 60,
        planStartDate: planStartDate
    )

    static var sampleGoals: [RaceGoal] {
        let halfMarathon = sampleWorkouts.first { $0.metadata?["demo_kind"] as? String == "race" && ($0.distance ?? 0) > 20_000 }
        return [
            sampleRaceGoal,
            RaceGoal(
                id: UUID(uuidString: "D3A0C0DE-0000-4000-9000-000000000003")!,
                raceType: .halfMarathon,
                raceName: localized("Paris Half Marathon", "Semi-marathon de Paris"),
                targetDate: calendar.date(byAdding: .day, value: 158, to: calendar.startOfDay(for: now))!,
                createdAt: calendar.date(byAdding: .day, value: -10, to: now)!,
                targetTime: 95 * 60),
            RaceGoal(
                id: UUID(uuidString: "D3A0C0DE-0000-4000-9000-000000000004")!,
                raceType: .halfMarathon,
                raceName: halfMarathon?.raceDisplayName ?? localized("Boulogne Half Marathon", "Semi-marathon de Boulogne"),
                targetDate: halfMarathon?.startDate ?? calendar.date(byAdding: .day, value: -35, to: now)!,
                createdAt: calendar.date(byAdding: .day, value: -120, to: now)!,
                isPastRace: true,
                finishTime: halfMarathon?.duration ?? 5988,
                targetTime: 100 * 60),
        ]
    }

    private static func pace(_ minutesPerKm: Double) -> String {
        Formatters.paceClock(minutesPerKm * 60)
    }

    private static func plannedWorkout(_ type: WorkoutType, week: Int) -> PlannedWorkout {
        let progress = Double(week) / 8
        switch type {
        case .intervals:
            let reps = min(8, 5 + week / 2)
            return PlannedWorkout(
                type: .intervals,
                name: localized("\(reps) × 800 m at 10K pace", "\(reps) × 800 m allure 10 km"),
                description: localized(
                    "Short, fast repeats to sharpen your race pace. Jog 400 m easy between each one.",
                    "Répétitions courtes et rapides pour affûter ton allure de course. Trottine 400 m entre chaque."),
                targetDuration: 3000, targetDistance: 9000, targetPace: pace(4.35 - 0.1 * progress),
                steps: [
                    PlannedWorkoutStep(type: .warmup, duration: 900, targetPace: pace(5.9), description: localized("Easy warm-up", "Échauffement tranquille")),
                    PlannedWorkoutStep(type: .interval, distance: 800, targetPace: pace(4.35 - 0.1 * progress), repetitions: reps, description: localized("Fast 800 m", "800 m rapides")),
                    PlannedWorkoutStep(type: .recovery, distance: 400, targetPace: pace(6.4), repetitions: reps, description: localized("Easy jog", "Trot léger")),
                    PlannedWorkoutStep(type: .cooldown, duration: 600, targetPace: pace(6.0), description: localized("Cool-down", "Retour au calme")),
                ],
                intensity: .hard)
        case .tempo:
            return PlannedWorkout(
                type: .tempo,
                name: localized("Tempo 3 × 10 min", "Seuil 3 × 10 min"),
                description: localized(
                    "Comfortably hard blocks to lift your threshold.",
                    "Blocs soutenus mais contrôlés pour relever ton seuil."),
                targetDuration: 3300, targetDistance: 10000, targetPace: pace(4.6 - 0.08 * progress),
                steps: [
                    PlannedWorkoutStep(type: .warmup, duration: 900, targetPace: pace(5.9), description: localized("Easy warm-up", "Échauffement tranquille")),
                    PlannedWorkoutStep(type: .work, duration: 600, targetPace: pace(4.6 - 0.08 * progress), repetitions: 3, description: localized("Tempo block", "Bloc au seuil")),
                    PlannedWorkoutStep(type: .recovery, duration: 120, repetitions: 3, description: localized("Easy jog", "Trot léger")),
                    PlannedWorkoutStep(type: .cooldown, duration: 600, description: localized("Cool-down", "Retour au calme")),
                ],
                intensity: .moderate)
        case .longRun:
            let km = 13 + Double(min(week, 6))
            return PlannedWorkout(
                type: .longRun,
                name: localized("Long run \(Formatters.distance(km: km, fractionDigits: 0))", "Sortie longue \(Formatters.distance(km: km, fractionDigits: 0))"),
                description: localized(
                    "Steady and conversational. Finish the last 2 km a little faster.",
                    "Régulière et en aisance respiratoire. Accélère légèrement sur les 2 derniers km."),
                targetDuration: km * 5.6 * 60, targetDistance: km * 1000, targetPace: pace(5.6),
                intensity: .moderate)
        default:
            return PlannedWorkout(
                type: .easyRun,
                name: localized("Easy run", "Footing"),
                description: localized(
                    "Relaxed aerobic run to absorb the week's work.",
                    "Footing en endurance pour assimiler le travail de la semaine."),
                targetDuration: 2700, targetDistance: 8000, targetPace: pace(5.75),
                intensity: .easy)
        }
    }

    static let sampleTrainingPlan: TrainingPlan = {
        let phases: [TrainingPhase] = [.base, .base, .base, .build, .build, .build, .peak, .peak, .taper]
        let today = calendar.startOfDay(for: now)
        let weeks = phases.enumerated().map { index, phase in
            let quality: WorkoutType = index % 2 == 1 ? .intervals : .tempo
            let schedule: [(DayOfWeek, WorkoutType?)] = [
                (.monday, .easyRun), (.tuesday, nil), (.wednesday, quality), (.thursday, nil),
                (.friday, nil), (.saturday, .easyRun), (.sunday, index == 8 ? nil : .longRun),
            ]
            let days = schedule.enumerated().map { offset, entry in
                let dayDate = calendar.date(byAdding: .day, value: index * 7 + offset, to: planStartDate)!
                let completed = entry.1 != nil && dayDate <= today
                let workoutID = sampleWorkouts.first { calendar.isDate($0.startDate, inSameDayAs: dayDate) }?.id
                return TrainingDay(
                    dayOfWeek: entry.0,
                    workout: entry.1.map { plannedWorkout($0, week: index) },
                    isCompleted: completed,
                    completedWorkoutId: completed ? workoutID?.uuidString : nil)
            }
            return TrainingWeek(
                weekNumber: index + 1, phase: phase, days: days,
                weeklyVolume: [30, 32, 34, 36, 38, 40, 42, 40, 24][index])
        }
        var plan = TrainingPlan(
            id: UUID(uuidString: "D3A0C0DE-0000-4000-9000-000000000002")!,
            name: localized("Paris 10K in 44:00", "10 km de Paris en 44:00"),
            goal: localized("Run 10K under 44 minutes", "Courir 10 km en moins de 44 minutes"),
            level: .intermediate,
            weeks: weeks,
            createdAt: calendar.date(byAdding: .day, value: -2, to: planStartDate)!,
            startDate: planStartDate,
            isActive: true,
            calendarTimeZoneIdentifier: TimeZone.current.identifier)
        plan.lastAdaptationDate = calendar.date(byAdding: .day, value: -2, to: today)
        plan.lastAdaptationWeekIndex = plan.currentWeekIndex
        plan.adaptationAssessment = localized(
            "You completed every session of the last three weeks and your tempo pace dropped by 9 s/km. The plan keeps its build: one more 800 m repeat on Wednesday and a long run of 16 km on Sunday.",
            "Tu as réalisé toutes les séances des trois dernières semaines et ton allure au seuil a gagné 9 s/km. Le plan poursuit sa montée en charge : une répétition de 800 m en plus mercredi et une sortie longue de 16 km dimanche.")
        return plan
    }()

    // MARK: - Sample Daily Activity Data

    static func dailyActivityData(for date: Date) -> DailyActivityData {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MISSING_METRICS_UI_TEST") {
            return DailyActivityData(
                steps: 0, activeCalories: 0, basalCalories: 0,
                exerciseMinutes: 0, activeCaloriesGoal: nil, exerciseMinutesGoal: nil)
        }
        #endif
        let offset = daysAgo(date)
        if offset == 0 {
            return DailyActivityData(
                steps: 9_240, activeCalories: 548, basalCalories: 1684,
                exerciseMinutes: 41, activeCaloriesGoal: 600, exerciseMinutesGoal: 30)
        }
        let ranThatDay = sampleWorkouts.contains { calendar.isDate($0.startDate, inSameDayAs: date) }
        let noise = wave(offset, 2.3)
        return DailyActivityData(
            steps: (ranThatDay ? 13_400 + 1_600 * noise : 7_600 + 1_900 * noise).rounded(),
            activeCalories: (ranThatDay ? 760 + 90 * noise : 410 + 80 * noise).rounded(),
            basalCalories: 1684,
            exerciseMinutes: (ranThatDay ? 62 + 10 * noise : 21 + 8 * noise).rounded(),
            activeCaloriesGoal: 600,
            exerciseMinutesGoal: 30
        )
    }
    // MARK: - Sample Personal Baseline

    static let samplePersonalBaseline: PersonalBaseline = PersonalBaseline(
        id: UUID(),
        computedAt: calendar.date(byAdding: .hour, value: -12, to: now)!,
        dataPointCount: 28,
        restingHeartRateAverage: 53,
        restingHeartRateStdDev: 3.2,
        hrvAverage: 62,
        hrvStdDev: 12.5,
        walkingHeartRateAverage: 80,
        walkingHeartRateStdDev: 5.0,
        respiratoryRateAverage: 14.5,
        respiratoryRateStdDev: 1.2,
        oxygenSaturationAverage: 97.5,
        oxygenSaturationStdDev: 0.8,
        sleepDurationAverage: 7.5 * 3600,
        sleepEfficiencyAverage: 90,
        deepSleepPercentageAverage: 18,
        remSleepPercentageAverage: 24
    )

    // MARK: - Sample Workout AI Analysis

    static var sampleWorkoutAnalysis: String {
        return AppLanguage.current == "fr" ? sampleWorkoutAnalysisFR : sampleWorkoutAnalysisEN
    }

    private static let sampleWorkoutAnalysisEN = """
    You completed this 10 km run at 4:48/km and finished faster than you started, showing that you were able to increase your pace late in the session. Your average heart rate of 172 bpm adds context to that effort, but does not establish its intensity without a personal reference and your perceived effort. On your next comparable run, keep the opening pace controlled and note how the final kilometres feel: this will help you assess whether a faster finish also feels manageable.
    """

    private static let sampleWorkoutAnalysisFR = """
    Sur ce 10 km à 4:48/km, tu as terminé plus vite que tu n'as commencé, ce qui montre que tu as pu augmenter l'allure en fin de séance. La fréquence cardiaque moyenne de 172 battements par minute complète ce constat, mais ne permet pas à elle seule de qualifier l'intensité sans référence personnelle ni ressenti. Lors d'une prochaine sortie comparable, garde un départ contrôlé et note tes sensations sur les derniers kilomètres : tu pourras ainsi vérifier si cette fin plus rapide reste confortable pour toi.
    """

    static func workoutAnalysis(for workout: WorkoutModel) -> String {
        let distance = Formatters.distance(km: (workout.distance ?? 0) / 1000, fractionDigits: 1)
        let averagePace = workout.averagePace.map { Formatters.paceFromMinutesPerKm($0) } ?? "—"
        let heartRate = Int(workout.averageHeartRate ?? 0)
        switch kind(of: workout) {
        case .intervals:
            return localized(
                "Your six 800 m repeats stayed within 4 seconds of each other, and the last one was the fastest: a sign that the pace was well chosen. Heart rate climbed to \(Int(workout.maxHeartRate ?? 0)) bpm on the final repeat and dropped quickly during each jog, which matches the recovery you had going into the session. Keep the same pace next Wednesday and add a seventh repeat only if the last two feel as controlled as today.",
                "Tes six 800 m sont restés à moins de 4 secondes les uns des autres, et le dernier était le plus rapide : l'allure était bien choisie. La fréquence cardiaque est montée à \(Int(workout.maxHeartRate ?? 0)) bpm sur la dernière répétition et redescendait vite pendant chaque récupération, ce qui colle avec ta bonne récupération du jour. Garde la même allure mercredi prochain et n'ajoute un septième 800 m que si les deux derniers restent aussi contrôlés.")
        case .tempo:
            return localized(
                "You held \(averagePace) over \(distance) with a steady heart rate around \(heartRate) bpm, drifting by only 3 bpm between the first and last blocks. That stability at this pace is new compared with last month. Next time, keep the pace and aim to hold the same heart rate over a slightly longer final block.",
                "Tu as tenu \(averagePace) sur \(distance) avec une fréquence cardiaque stable autour de \(heartRate) bpm, qui n'a dérivé que de 3 bpm entre le premier et le dernier bloc. Cette stabilité à cette allure est nouvelle par rapport au mois dernier. La prochaine fois, garde l'allure et vise la même fréquence cardiaque sur un dernier bloc un peu plus long.")
        case .long, .race:
            return localized(
                "You covered \(distance) at \(averagePace) and ran the second half 12 s/km faster than the first, with an average heart rate of \(heartRate) bpm. Your pace stayed even on the climbs and your cadence held above 170 spm until the end, so fatigue did not change your stride. Recover with an easy day tomorrow before your next quality session.",
                "Tu as couvert \(distance) à \(averagePace) et couru la seconde moitié 12 s/km plus vite que la première, avec une fréquence cardiaque moyenne de \(heartRate) bpm. L'allure est restée régulière dans les montées et ta cadence est restée au-dessus de 170 pas/min jusqu'au bout : la fatigue n'a pas modifié ta foulée. Récupère avec une journée facile demain avant ta prochaine séance de qualité.")
        case .easy, .recovery:
            return localized(
                "An easy \(distance) at \(averagePace), with heart rate settled around \(heartRate) bpm: exactly the relaxed effort this session was for. Your heart rate stayed flat from start to finish, a good sign that you are recovered from your last hard session. You can approach the next quality workout as planned.",
                "Un footing de \(distance) à \(averagePace), avec une fréquence cardiaque posée autour de \(heartRate) bpm : exactement l'effort facile attendu. Elle est restée stable du début à la fin, bon signe que tu as récupéré de ta dernière séance difficile. Tu peux aborder la prochaine séance de qualité comme prévu.")
        }
    }

    // MARK: - Sample Monthly Coach Insight (Demo Mode)

    static func monthlyInsight(thisMonth: [WorkoutModel], lastMonth: [WorkoutModel]) -> String {
        let thisDistance = thisMonth.compactMap(\.distance).reduce(0, +) / 1000
        let lastDistance = lastMonth.compactMap(\.distance).reduce(0, +) / 1000
        let change = lastDistance > 0 ? Int(((thisDistance / lastDistance - 1) * 100).rounded()) : 0
        let sign = change >= 0 ? "+" : "−"
        let longest = Formatters.distance(km: (thisMonth.compactMap(\.distance).max() ?? 0) / 1000, fractionDigits: 1)
        return localized(
            "Volume \(sign)\(abs(change))% vs last month with \(thisMonth.count) runs, and your easy runs now sit at a lower heart rate for the same pace. Your longest run reached \(longest) without any sign of fatigue in the following days. Keep one quality session per week and let the long run grow gradually.",
            "Volume \(sign)\(abs(change)) % par rapport au mois dernier avec \(thisMonth.count) sorties, et tes footings se font désormais à une fréquence cardiaque plus basse pour la même allure. Ta sortie la plus longue a atteint \(longest) sans signe de fatigue les jours suivants. Garde une séance de qualité par semaine et laisse la sortie longue progresser doucement.")
    }
    // MARK: - Sample Score Analysis (Demo Mode)

    static func sampleScoreAnalysis(for scoreType: ScoreType, score: Int) -> String {
        let lang = AppLanguage.current
        switch scoreType {
        case .effort:
            return lang == "fr"
                ? "Votre score d'effort est de \(score)/100. Il combine votre progression vers les objectifs de pas, de calories actives et de minutes d’exercice."
                : "Your effort score is \(score)/100. It combines your progress towards steps, active calories and exercise minute goals."
        case .sleep:
            return lang == "fr"
                ? "Excellent sommeil ! 7h45 avec 91% d'efficacité et une bonne répartition des phases (profond 19%, léger 45%, REM 26%). Votre récupération nocturne est optimale pour l'entraînement."
                : "Excellent sleep! 7h45 with 91% efficiency and good stage distribution (deep 19%, light 45%, REM 26%). Your overnight recovery is optimal for training."
        case .readiness:
            return lang == "fr"
                ? "Score de préparation de \(score)% — excellent. Votre VFC (65ms), FC repos (52 bpm) et SpO2 (98%) indiquent une récupération complète. Vous pouvez envisager une séance intense aujourd'hui."
                : "Readiness score of \(score)% — excellent. Your HRV (65ms), resting HR (52 bpm) and SpO2 (98%) indicate full recovery. You can consider an intense session today."
        case .cardiacLoad:
            return lang == "fr"
                ? "Charge cardiaque de \(score)/20. La courbe sur 14 jours permet de suivre l’évolution de votre charge récente par rapport à votre référence personnelle."
                : "Cardiac load of \(score)/20. The 14-day chart shows how your recent load evolves relative to your personal baseline."
        case .freshness:
            return lang == "fr"
                ? "Score de fraîcheur de \(score)/100 — vous êtes bien récupéré. Votre charge récente reste sous votre charge chronique, signe d'un bon équilibre. Bon moment pour une séance qualitative."
                : "Freshness score of \(score)/100 — you're well rested. Recent training load is below your chronic baseline, indicating good balance. Good time for a quality session."
        }
    }

    static func sampleMetricAnalysis(for metricType: MetricType, value: Double) -> String {
        let lang = AppLanguage.current
        switch metricType {
        case .hrv:
            return lang == "fr"
                ? "VFC de 65ms — dans la plage normale. Indicateur clé de récupération du système nerveux autonome. Valeur stable sur les 7 derniers jours."
                : "HRV of 65ms — within normal range. Key indicator of autonomic nervous system recovery. Stable value over the last 7 days."
        case .rmssd:
            return lang == "fr"
                ? "Ta VFC nocturne RMSSD est de \(Formatters.integer(Int(value.rounded()))) ms, proche de ta référence personnelle. Suis son évolution sur plusieurs nuits avec ton sommeil, ta fréquence cardiaque au repos et ton ressenti, sans conclure sur une seule mesure."
                : "Your night-time RMSSD is \(Formatters.integer(Int(value.rounded()))) ms, close to your personal reference. Follow its trend over several nights alongside sleep, resting heart rate and how you feel, without drawing conclusions from one measurement."
        case .restingHeartRate:
            return lang == "fr"
                ? "FC repos de 52 bpm — excellente pour un coureur régulier. Signe d'une bonne adaptation cardiovasculaire à l'entraînement."
                : "Resting HR of 52 bpm — excellent for a regular runner. Sign of good cardiovascular adaptation to training."
        case .respiratoryRate:
            return lang == "fr"
                ? "Fréquence respiratoire de 14 rpm — normale et stable. Aucun signe de stress physiologique ou de surentraînement."
                : "Respiratory rate of 14 rpm — normal and stable. No signs of physiological stress or overtraining."
        case .oxygenSaturation:
            return lang == "fr"
                ? "SpO2 de 98% — excellent. Oxygénation optimale des tissus pour la performance et la récupération."
                : "SpO2 of 98% — excellent. Optimal tissue oxygenation for performance and recovery."
        case .sleepDuration:
            return lang == "fr"
                ? "Durée de sommeil de 7h45 — idéale pour la récupération athlétique. L'objectif de 7-9h est bien atteint."
                : "Sleep duration of 7h45 — ideal for athletic recovery. The 7-9h target is well met."
        case .sleepEfficiency:
            return lang == "fr"
                ? "Efficacité de sommeil de 91% — très bon. Au-dessus du seuil de 85% recommandé pour une récupération optimale."
                : "Sleep efficiency of 91% — very good. Above the 85% threshold recommended for optimal recovery."
        case .recoveryScore:
            return lang == "fr"
                ? "Score de récupération global très positif. Tous vos indicateurs physiologiques sont dans les plages optimales."
                : "Overall recovery score is very positive. All your physiological indicators are within optimal ranges."
        case .steps:
            return lang == "fr"
                ? "Tu as enregistré \(Formatters.integer(Int(value.rounded()))) pas sur cette journée, en marchant et en courant. Ce total décrit ton mouvement quotidien, mais pas à lui seul l'intensité de tes séances ni ta récupération ; observe son évolution avec ton ressenti."
                : "You have recorded \(Formatters.integer(Int(value.rounded()))) steps on this day, from walking and running. This total describes daily movement, but does not establish workout intensity or recovery on its own; follow its trend alongside how you feel."
        case .totalCalories:
            return lang == "fr"
                ? "Dépense totale de \(Formatters.calories(value)). La courbe distingue les calories actives et celles dépensées au repos."
                : "Total expenditure of \(Formatters.calories(value)). The chart separates active calories from energy burned at rest."
        }
    }

    // MARK: - Sample Progression Data

    static let sampleProgressionData: [ProgressionDataPoint] = sampleWorkouts.enumerated().map { index, workout in
        let fitness = 1 - Double(daysAgo(workout.startDate)) / Double(historyDays)
        let noise = wave(index, 1.7)
        return ProgressionDataPoint(
            workoutId: workout.id,
            date: workout.startDate,
            averagePace: workout.averagePace,
            minPace: (workout.averagePace ?? 5.0) - 0.35 - 0.1 * fitness,
            maxSpeed: 14.5 + 1.5 * fitness + noise * 0.3,
            averageCadence: (168 + 8 * fitness + noise * 1.5).rounded(),
            strideLength: 1.02 + 0.08 * fitness + noise * 0.01,
            runningPower: (242 + 22 * fitness + noise * 4).rounded(),
            vo2Max: ((49.2 + 3.4 * fitness + noise * 0.2) * 10).rounded() / 10,
            groundContactTime: (254 - 16 * fitness + noise * 2).rounded(),
            verticalOscillation: 8.6 - 0.6 * fitness + noise * 0.1,
            walkingAsymmetry: 2.4 - 0.8 * fitness,
            doubleSupportPercentage: 28.5 - 1.2 * fitness,
            walkingSpeed: 5.4 + 0.3 * fitness,
            stairDescentSpeed: nil
        )
    }

    // MARK: - Sample Workout Metrics

    static func workoutMetrics(for workout: WorkoutModel) -> WorkoutMetrics {
        let kind = kind(of: workout)
        let distance = workout.distance ?? 0
        let averagePace = workout.averagePace ?? 5.5
        let averageHeartRate = workout.averageHeartRate ?? 150
        let seed = Int(workout.startDate.timeIntervalSince1970 / 86_400)
        let fitness = 1 - Double(daysAgo(workout.startDate)) / Double(historyDays)

        let fullKilometers = Int(distance / 1000)
        let remainder = distance - Double(fullKilometers) * 1000
        let splitCount = fullKilometers + (remainder >= 50 ? 1 : 0)
        let splits: [Split] = (0..<splitCount).map { index in
            let length = index < fullKilometers ? 1000 : remainder
            let progress = splitCount > 1 ? Double(index) / Double(splitCount - 1) : 0
            let splitPace = averagePace * (1.018 - 0.036 * progress) + 0.03 * wave(seed + index, 2.7)
            return Split(
                kilometer: index + 1,
                distance: length,
                time: splitPace * 60 * length / 1000,
                pace: splitPace,
                averageHeartRate: (averageHeartRate - 6 + 12 * progress + 1.5 * wave(seed + index, 1.1)).rounded(),
                averagePower: (268 - (splitPace - 4.6) * 45).rounded(),
                elevationGain: workout.isIndoor ? nil : max(0, (5 + 6 * wave(seed + index, 0.8)).rounded()),
                elevationLoss: workout.isIndoor ? nil : max(0, (5 - 6 * wave(seed + index, 0.8)).rounded()))
        }

        let zoneShares: [Double] = switch kind {
        case .easy: [0.08, 0.62, 0.26, 0.04, 0]
        case .recovery: [0.22, 0.7, 0.08, 0, 0]
        case .intervals: [0.1, 0.24, 0.2, 0.3, 0.16]
        case .tempo: [0.05, 0.15, 0.3, 0.45, 0.05]
        case .long: [0.03, 0.44, 0.43, 0.1, 0]
        case .race: [0, 0.03, 0.12, 0.45, 0.4]
        }
        let zoneBounds: [(Double?, Double?)] = [(nil, 114), (114, 133), (133, 152), (152, 171), (171, nil)]
        let zones = zip(zoneBounds, zoneShares).enumerated().map { index, entry in
            RecordedHeartRateZones.Zone(
                index: index, minimum: entry.0.0, maximum: entry.0.1,
                seconds: (workout.duration * entry.1).rounded())
        }
        let evidence = WorkoutEvidence(
            measuredAt: workout.endDate.ISO8601Format(),
            source: "healthkit",
            device: "Apple Watch Ultra 3",
            softwareVersion: workout.sourceVersion,
            zones: RecordedHeartRateZones(source: "system", zones: zones),
            signals: [
                WorkoutSignalQuality(metric: "heartRate", sampleCount: Int(workout.duration / 5), coverage: 0.99, longestGapSeconds: 6, sourceCount: 1),
                WorkoutSignalQuality(metric: "speed", sampleCount: Int(workout.duration / 2), coverage: 0.98, longestGapSeconds: 4, sourceCount: 1),
            ],
            phases: samplePhases(for: workout, averagePace: averagePace, averageHeartRate: averageHeartRate))

        let cadence = (170 + 6 * fitness + (kind == .intervals || kind == .race ? 6 : 0)).rounded()
        return WorkoutMetrics(
            workout: workout,
            averageHeartRate: averageHeartRate,
            minHeartRate: (averageHeartRate - 38).rounded(),
            maxHeartRate: workout.maxHeartRate,
            firstHeartRate: (averageHeartRate - 30).rounded(),
            lastHeartRate: (averageHeartRate + 6).rounded(),
            averagePace: averagePace,
            minPace: (splits.map(\.pace).min() ?? averagePace) - (kind == .intervals ? 0.45 : 0.08),
            maxPace: splits.map(\.pace).max(),
            averageSpeed: 60 / averagePace,
            maxSpeed: 60 / averagePace * (kind == .intervals ? 1.2 : 1.08),
            totalSteps: Int(cadence * workout.duration / 60),
            averageCadence: cadence,
            strideLength: ((1000 / averagePace) / cadence * 100).rounded() / 100,
            runningPower: (268 - (averagePace - 4.6) * 45).rounded(),
            firstPower: 238,
            lastPower: (268 - (averagePace - 4.6) * 45 + 8).rounded(),
            totalElevationAscent: workout.isIndoor ? nil : splits.compactMap(\.elevationGain).reduce(0, +),
            totalElevationDescent: workout.isIndoor ? nil : splits.compactMap(\.elevationLoss).reduce(0, +),
            splits: splits,
            intervals: kind == .intervals ? sampleIntervals(for: workout) : nil,
            routePoints: workout.isIndoor ? nil : sampleRoute(for: workout, seed: seed),
            groundContactTime: (252 - 14 * fitness).rounded(),
            groundContactTimeBalance: 50.4,
            verticalOscillation: ((8.6 - 0.5 * fitness) * 10).rounded() / 10,
            runningEfficiency: nil,
            walkingSteadiness: nil,
            walkingAsymmetry: nil,
            doubleSupportPercentage: nil,
            walkingSpeed: nil,
            stairAscentSpeed: nil,
            stairDescentSpeed: nil,
            vo2Max: ((49.2 + 3.4 * fitness) * 10).rounded() / 10,
            temperature: workout.isIndoor ? nil : 14,
            humidity: workout.isIndoor ? nil : 68,
            movingTime: workout.duration - 25,
            pausedTime: 25,
            evidence: evidence
        )
    }

    private static func samplePhases(for workout: WorkoutModel, averagePace: Double, averageHeartRate: Double) -> [WorkoutPhase] {
        let third: Double = workout.duration / 3
        let baseSpeed: Double = 1000 / (averagePace * 60)
        return (0..<3).map { index in
            let step = Double(index)
            return WorkoutPhase(
                index: index,
                startOffsetSeconds: third * step,
                durationSeconds: third,
                heartRate: averageHeartRate - 5 + 5 * step,
                speed: baseSpeed * (0.98 + 0.02 * step),
                power: 255 + 6 * step,
                strideLength: 1.08,
                groundContactTime: 244 + 3 * step,
                verticalOscillation: 8.3)
        }
    }

    private static func sampleIntervals(for workout: WorkoutModel) -> [WorkoutInterval] {
        var cursor = workout.startDate
        var result: [WorkoutInterval] = []
        func append(_ type: IntervalType, duration: TimeInterval, distance: Double, heartRate: Double, power: Double, target: (Double, Double)? = nil) {
            let end = cursor.addingTimeInterval(duration)
            result.append(WorkoutInterval(
                index: result.count + 1, type: type, startDate: cursor, endDate: end, duration: duration,
                distance: distance, pace: duration / 60 / (distance / 1000), averageHeartRate: heartRate,
                averagePower: power, targetPaceMin: target?.0, targetPaceMax: target?.1))
            cursor = end
        }
        append(.warmup, duration: 900, distance: 2600, heartRate: 138, power: 225)
        for repeatIndex in 0..<6 {
            append(.work, duration: 208 - Double(repeatIndex), distance: 800, heartRate: 172 + Double(repeatIndex) * 2, power: 312, target: (4.25, 4.4))
            if repeatIndex < 5 {
                append(.recovery, duration: 150, distance: 400, heartRate: 148, power: 205)
            }
        }
        append(.cooldown, duration: max(300, workout.duration - cursor.timeIntervalSince(workout.startDate)), distance: 1400, heartRate: 142, power: 220)
        return result
    }

    private static func sampleRoute(for workout: WorkoutModel, seed: Int) -> [RoutePoint] {
        let center = CLLocationCoordinate2D(latitude: 48.8628, longitude: 2.2455)
        let radius = min(1100, (workout.distance ?? 8000) / (2 * .pi) / 1.3)
        let count = 240
        let speed = (workout.distance ?? 0) / max(1, workout.duration)
        let phase = Double(seed % 7)
        return (0...count).map { index in
            let theta = Double(index) / Double(count) * 2 * .pi
            let r = radius * (1 + 0.18 * sin(3 * theta + phase) + 0.08 * cos(5 * theta))
            let north = r * sin(theta) * 1.3
            let east = r * cos(theta) * 0.85
            return RoutePoint(
                coordinate: CLLocationCoordinate2D(
                    latitude: center.latitude + north / 111_320,
                    longitude: center.longitude + east / (111_320 * cos(center.latitude * .pi / 180))),
                altitude: 38 + 9 * sin(2 * theta + phase),
                timestamp: workout.startDate.addingTimeInterval(workout.duration * Double(index) / Double(count)),
                horizontalAccuracy: 4,
                verticalAccuracy: 3,
                speed: speed)
        }
    }

    // MARK: - Sample Coach Conversation

    static var sampleChatMessages: [ChatMessage] {
        let trend = """
        {"metric":"pace","period":"quarter","trend":"improving","percentageChange":6.8,"insights":[\
        "\(localized("Tempo pace improved by 22 s/km since June", "Allure au seuil améliorée de 22 s/km depuis juin"))",\
        "\(localized("Easy runs now 5 bpm lower at the same pace", "Footings 5 bpm plus bas à allure égale"))",\
        "\(localized("Long run grew from 13 to 19 km", "Sortie longue passée de 13 à 19 km"))"]}
        """
        let workout = """
        {"type":"tempo","duration":50,"targetPace":"4:35","steps":[\
        {"type":"warmup","duration":15,"description":"\(localized("Easy jog, 4 strides at the end", "Footing léger, 4 accélérations à la fin"))"},\
        {"type":"tempo","duration":25,"description":"\(localized("Steady at race-pace effort", "Régulier à l'effort de course"))","targetPace":"4:35"},\
        {"type":"cooldown","duration":10,"description":"\(localized("Relaxed jog", "Trot détendu"))"}]}
        """
        let start = date(daysAgo: 0, hour: 8, minute: 12)
        return [
            ChatMessage(
                role: .user,
                content: localized("Am I on track for my 10K goal?", "Est-ce que je suis sur la bonne voie pour mon 10 km ?"),
                timestamp: start),
            ChatMessage(
                role: .assistant, content: "", timestamp: start.addingTimeInterval(15),
                functionName: "analyze_trend", functionResult: Data(trend.utf8)),
            ChatMessage(
                role: .assistant,
                content: localized(
                    "Yes. Your 800 m repeats this morning averaged 4:21/km, faster than the 4:24/km your 44:00 target needs. Resting heart rate is stable at 52 bpm and HRV is above your baseline, so you are absorbing the load well.",
                    "Oui. Tes 800 m de ce matin étaient en moyenne à 4:21/km, plus vite que les 4:24/km nécessaires pour tes 44:00. Ta FC au repos est stable à 52 bpm et ta VFC au-dessus de ta référence : tu assimiles bien la charge."),
                timestamp: start.addingTimeInterval(20)),
            ChatMessage(
                role: .user,
                content: localized("What should I run on Saturday?", "Que faire samedi ?"),
                timestamp: start.addingTimeInterval(90)),
            ChatMessage(
                role: .assistant, content: "", timestamp: start.addingTimeInterval(105),
                functionName: "generate_workout", functionResult: Data(workout.utf8)),
        ]
    }

    // MARK: - Sample Readiness History

    static let readinessHistory: [Int] = [82, 76, 71, 79, 68, 74, 80, 77, 72, 81, 75, 70, 78, 73]

    static let readinessRecommendation = localized(
        "Your HRV is above your baseline and you slept 7h45 with 91% efficiency. Your legs have had 24 hours since this morning's intervals, so tomorrow suits an easy 45-minute run; keep the effort conversational and save the intensity for Saturday.",
        "Ta VFC est au-dessus de ta référence et tu as dormi 7h45 avec 91 % d'efficacité. Tes jambes récupèrent des fractionnés de ce matin : demain, un footing de 45 minutes en aisance respiratoire est idéal ; garde l'intensité pour samedi.")
}
