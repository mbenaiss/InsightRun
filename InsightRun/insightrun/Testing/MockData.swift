//
//  MockData.swift
//  InsightRun
//
//  Comprehensive mock data for demo mode and previews
//

import Foundation
import HealthKit

enum MockData {

    // MARK: - Helpers

    private static let calendar = Calendar.current
    private static let now = Date()

    private static func date(daysAgo: Int, hour: Int = 7, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    // MARK: - Sample Workouts

    static let sampleWorkouts: [WorkoutModel] = [
        // 10K Race - 2 days ago
        WorkoutModel(
            id: UUID(),
            workoutType: .running,
            startDate: date(daysAgo: 2, hour: 9, minute: 0),
            endDate: date(daysAgo: 2, hour: 9, minute: 48),
            duration: 2880,
            distance: 10000,
            totalEnergyBurned: 620,
            sourceName: "Apple Watch",
            sourceVersion: "11.0",
            metadata: nil,
            averageHeartRate: 172,
            maxHeartRate: 188,
            elevationGain: 45,
            hasRoute: true,
            isIndoor: false
        ),
        // Interval Training - 4 days ago
        WorkoutModel(
            id: UUID(),
            workoutType: .running,
            startDate: date(daysAgo: 4, hour: 18, minute: 30),
            endDate: date(daysAgo: 4, hour: 19, minute: 15),
            duration: 2700,
            distance: 8200,
            totalEnergyBurned: 540,
            sourceName: "Apple Watch",
            sourceVersion: "11.0",
            metadata: nil,
            averageHeartRate: 165,
            maxHeartRate: 192,
            elevationGain: 30,
            hasRoute: true,
            isIndoor: false
        ),
        // Long Run - 5 days ago
        WorkoutModel(
            id: UUID(),
            workoutType: .running,
            startDate: date(daysAgo: 5, hour: 7, minute: 0),
            endDate: date(daysAgo: 5, hour: 8, minute: 35),
            duration: 5700,
            distance: 18500,
            totalEnergyBurned: 1120,
            sourceName: "Apple Watch",
            sourceVersion: "11.0",
            metadata: nil,
            averageHeartRate: 148,
            maxHeartRate: 165,
            elevationGain: 85,
            hasRoute: true,
            isIndoor: false
        ),
        // Recovery Run - 6 days ago
        WorkoutModel(
            id: UUID(),
            workoutType: .running,
            startDate: date(daysAgo: 6, hour: 7, minute: 30),
            endDate: date(daysAgo: 6, hour: 8, minute: 0),
            duration: 1800,
            distance: 5000,
            totalEnergyBurned: 280,
            sourceName: "Apple Watch",
            sourceVersion: "11.0",
            metadata: nil,
            averageHeartRate: 132,
            maxHeartRate: 145,
            elevationGain: 15,
            hasRoute: true,
            isIndoor: false
        ),
        // Tempo Run - 8 days ago
        WorkoutModel(
            id: UUID(),
            workoutType: .running,
            startDate: date(daysAgo: 8, hour: 6, minute: 45),
            endDate: date(daysAgo: 8, hour: 7, minute: 25),
            duration: 2400,
            distance: 8000,
            totalEnergyBurned: 480,
            sourceName: "Apple Watch",
            sourceVersion: "11.0",
            metadata: nil,
            averageHeartRate: 162,
            maxHeartRate: 178,
            elevationGain: 35,
            hasRoute: true,
            isIndoor: false
        ),
        // Easy Run - 9 days ago
        WorkoutModel(
            id: UUID(),
            workoutType: .running,
            startDate: date(daysAgo: 9, hour: 12, minute: 15),
            endDate: date(daysAgo: 9, hour: 12, minute: 55),
            duration: 2400,
            distance: 7200,
            totalEnergyBurned: 390,
            sourceName: "Apple Watch",
            sourceVersion: "11.0",
            metadata: nil,
            averageHeartRate: 140,
            maxHeartRate: 155,
            elevationGain: 25,
            hasRoute: true,
            isIndoor: false
        ),
        // Treadmill Run - 11 days ago
        WorkoutModel(
            id: UUID(),
            workoutType: .running,
            startDate: date(daysAgo: 11, hour: 19, minute: 0),
            endDate: date(daysAgo: 11, hour: 19, minute: 35),
            duration: 2100,
            distance: 6500,
            totalEnergyBurned: 350,
            sourceName: "Apple Watch",
            sourceVersion: "11.0",
            metadata: nil,
            averageHeartRate: 145,
            maxHeartRate: 160,
            elevationGain: nil,
            hasRoute: false,
            isIndoor: true
        ),
        // Progressive Run - 13 days ago
        WorkoutModel(
            id: UUID(),
            workoutType: .running,
            startDate: date(daysAgo: 13, hour: 7, minute: 15),
            endDate: date(daysAgo: 13, hour: 8, minute: 5),
            duration: 3000,
            distance: 10500,
            totalEnergyBurned: 560,
            sourceName: "Apple Watch",
            sourceVersion: "11.0",
            metadata: nil,
            averageHeartRate: 155,
            maxHeartRate: 180,
            elevationGain: 50,
            hasRoute: true,
            isIndoor: false
        ),
    ]

    // MARK: - Sample Sleep Data

    static let sampleSleepData: SleepData = sampleSleep(daysAgo: 0)

    private static func sampleSleep(daysAgo: Int) -> SleepData {
        let nightDate = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
        let sleepStart = calendar.date(bySettingHour: 23, minute: 0, second: 0,
                                       of: calendar.date(byAdding: .day, value: -1, to: nightDate)!)!
        let sleepEnd = calendar.date(bySettingHour: 6, minute: 45, second: 0, of: nightDate)!

        let baseTotal: TimeInterval = 7 * 3600 + 45 * 60
        let baseInBed: TimeInterval = 8 * 3600 + 30 * 60
        let variance = TimeInterval((daysAgo * 17) % 60 - 30) * 60

        let totalSleep = baseTotal + variance
        let timeInBed = baseInBed + variance + 600

        return SleepData(
            date: nightDate,
            sleepStart: sleepStart,
            sleepEnd: sleepEnd,
            totalSleepDuration: totalSleep,
            timeInBed: timeInBed,
            deepSleepDuration: 1 * 3600 + 30 * 60 + variance / 4,
            coreSleepDuration: 3 * 3600 + 30 * 60 + variance / 2,
            remSleepDuration: 2 * 3600 + variance / 4,
            awakeDuration: 45 * 60,
            napDuration: nil
        )
    }

    static func sampleSleepHistory(start: Date, end: Date) -> [SleepData] {
        var nights: [SleepData] = []
        var cursor = end
        while cursor >= start {
            let daysAgo = max(0, calendar.dateComponents([.day], from: cursor, to: now).day ?? 0)
            nights.append(sampleSleep(daysAgo: daysAgo))
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return nights
    }

    // MARK: - Sample Recovery Metrics

    static let sampleRecoveryMetrics: RecoveryMetrics = RecoveryMetrics(
        date: now,
        restingHeartRate: 52,
        hrvAverage: 65,
        hrvMin: 42,
        hrvMax: 88,
        walkingHeartRate: 78,
        sleepData: sampleSleepData,
        respiratoryRate: 14,
        oxygenSaturation: 98,
        baseline: samplePersonalBaseline
    )

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

    static let sampleRaceGoal: RaceGoal = RaceGoal(
        raceType: .tenK,
        raceName: "Paris 10K",
        targetDate: calendar.date(byAdding: .weekOfYear, value: 8, to: now)!,
        fitnessLevel: .intermediate,
        createdAt: calendar.date(byAdding: .day, value: -3, to: now)!,
        trainingDaysPerWeek: 4,
        preferredDays: [.monday, .wednesday, .friday, .saturday],
        targetTime: 50 * 60
    )

    // MARK: - Sample Daily Activity Data

    static let sampleDailyActivityData: DailyActivityData = DailyActivityData(
        steps: 8420,
        activeCalories: 512,
        basalCalories: 1684,
        exerciseMinutes: 38,
        activeCaloriesGoal: 600,
        exerciseMinutesGoal: 30
    )

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
    ## Summary
    Strong 10K at 4'47"/km showing excellent aerobic fitness. Heart rate averaged 172 bpm (Zone 4) with high intensity sustained well, and a negative split that reflects good pacing discipline.
    """

    private static let sampleWorkoutAnalysisFR = """
    ## Synthèse
    Excellent 10K à 4'47"/km, très bonne condition aérobie. Fréquence cardiaque moyenne de 172 bpm (Zone 4), haute intensité bien maintenue, et une fin de course plus rapide qui traduit une bonne gestion de l'allure.
    """

    // MARK: - Sample Monthly Coach Insight (Demo Mode)

    static var sampleMonthlyInsight: String {
        AppLanguage.current == "fr"
            ? "Volume en baisse de −21 % vs mars, mais qualité préservée : ton allure moyenne s'est améliorée de 5\"/km. Tu cours moins, mais mieux."
            : "Volume down −21% vs March, but quality preserved: average pace improved by 5\"/km. You ran less, but better."
    }

    // MARK: - Sample Score Analysis (Demo Mode)

    static func sampleScoreAnalysis(for scoreType: ScoreType) -> String {
        let lang = AppLanguage.current
        switch scoreType {
        case .effort:
            return lang == "fr"
                ? "Votre score d'effort est bas aujourd'hui — aucun entraînement enregistré. C'est une bonne journée pour une séance modérée à intense. Votre corps est bien reposé et prêt pour l'effort."
                : "Your effort score is low today — no workout recorded. This is a good day for a moderate to intense session. Your body is well-rested and ready for effort."
        case .sleep:
            return lang == "fr"
                ? "Excellent sommeil ! 7h45 avec 91% d'efficacité et une bonne répartition des phases (profond 19%, léger 45%, REM 26%). Votre récupération nocturne est optimale pour l'entraînement."
                : "Excellent sleep! 7h45 with 91% efficiency and good stage distribution (deep 19%, light 45%, REM 26%). Your overnight recovery is optimal for training."
        case .readiness:
            return lang == "fr"
                ? "Score de préparation de 82% — excellent. Votre VFC (65ms), FC repos (52 bpm) et SpO2 (98%) indiquent une récupération complète. Vous pouvez envisager une séance intense aujourd'hui."
                : "Readiness score of 82% — excellent. Your HRV (65ms), resting HR (52 bpm) and SpO2 (98%) indicate full recovery. You can consider an intense session today."
        case .cardiacLoad:
            return lang == "fr"
                ? "Charge cardiaque de 17, en augmentation. Votre tendance sur 7 jours montre une progression régulière. Maintenez cet équilibre charge/récupération pour optimiser vos adaptations."
                : "Cardiac load of 17, increasing. Your 7-day trend shows steady progression. Maintain this load/recovery balance to optimize your adaptations."
        case .freshness:
            return lang == "fr"
                ? "Score de fraîcheur de 72/100 — vous êtes bien récupéré. Votre charge récente reste sous votre charge chronique, signe d'un bon équilibre. Bon moment pour une séance qualitative."
                : "Freshness score of 72/100 — you're well rested. Recent training load is below your chronic baseline, indicating good balance. Good time for a quality session."
        }
    }

    static func sampleMetricAnalysis(for metricType: MetricType) -> String {
        let lang = AppLanguage.current
        switch metricType {
        case .hrv:
            return lang == "fr"
                ? "VFC de 65ms — dans la plage normale. Indicateur clé de récupération du système nerveux autonome. Valeur stable sur les 7 derniers jours."
                : "HRV of 65ms — within normal range. Key indicator of autonomic nervous system recovery. Stable value over the last 7 days."
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
        case .totalCalories:
            return lang == "fr"
                ? "2 350 kcal brûlées aujourd'hui (1 750 au repos + 600 actives) — dépense énergétique conforme à votre niveau d'activité habituel."
                : "2,350 kcal burned today (1,750 at rest + 600 active) — energy expenditure consistent with your typical activity level."
        }
    }

    // MARK: - Sample Progression Data

    static let sampleProgressionData: [ProgressionDataPoint] = sampleWorkouts.enumerated().map { index, workout in
        ProgressionDataPoint(
            workoutId: workout.id,
            date: workout.startDate,
            averagePace: workout.averagePace,
            minPace: (workout.averagePace ?? 5.0) - Double(index % 3) * 0.2,
            maxSpeed: 14.0 + Double(index % 4) * 0.5,
            averageCadence: 175 + Double(index % 5) * 2,
            strideLength: 1.05 + Double(index % 4) * 0.03,
            runningPower: 250 + Double(index % 6) * 15,
            vo2Max: 50.0 + Double(index % 3) * 1.5,
            groundContactTime: 245 - Double(index % 4) * 5,
            verticalOscillation: 8.0 + Double(index % 3) * 0.3,
            walkingAsymmetry: 3.0 - Double(index % 3) * 0.5,
            doubleSupportPercentage: 28.0 - Double(index % 4) * 0.5,
            walkingSpeed: 5.5 + Double(index % 3) * 0.2,
            stairDescentSpeed: nil
        )
    }

}
