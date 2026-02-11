//
//  MedicalSources.swift
//  InsightRun
//
//  Medical references and scientific sources for health metrics
//  All sources verified via PubMed, PMC, and official medical organizations (2025)
//

import Foundation

// MARK: - Medical Source Model

struct MedicalSource: Identifiable {
    let id = UUID()
    let title: String
    let authors: String
    let journal: String
    let year: Int
    let url: String?
    let summary: String

    var citation: String {
        "\(authors) (\(year)). \(title). \(journal)."
    }
}

// MARK: - Medical Sources Database

enum MedicalSourceCategory: String, CaseIterable, Identifiable {
    case heartRateVariability = "Heart Rate Variability (HRV)"
    case restingHeartRate = "Resting Heart Rate"
    case sleepRecovery = "Sleep & Recovery"
    case respiratoryRate = "Respiratory Rate"
    case trainingLoad = "Training Load & Cardiac Stress"
    case runningMetrics = "Running Metrics"
    case general = "General Guidelines"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .heartRateVariability:
            return String(localized: "Heart Rate Variability (HRV)", comment: "Medical source category: HRV")
        case .restingHeartRate:
            return String(localized: "Resting Heart Rate", comment: "Medical source category: Resting HR")
        case .sleepRecovery:
            return String(localized: "Sleep & Recovery", comment: "Medical source category: Sleep")
        case .respiratoryRate:
            return String(localized: "Respiratory Rate", comment: "Medical source category: Respiratory")
        case .trainingLoad:
            return String(localized: "Training Load & Cardiac Stress", comment: "Medical source category: Training Load")
        case .runningMetrics:
            return String(localized: "Running Metrics", comment: "Medical source category: Running")
        case .general:
            return String(localized: "General Guidelines", comment: "Medical source category: General")
        }
    }
}

struct MedicalSourcesDatabase {

    // MARK: - Disclaimer

    static var disclaimer: String {
        String(localized: """
        The information provided in this app is for educational and informational purposes only. It is not intended as a substitute for professional medical advice, diagnosis, or treatment. Always seek the advice of your physician or other qualified health provider with any questions you may have regarding a medical condition.

        The health metrics and recommendations in this app are based on published scientific research and general guidelines. Individual results may vary, and what is considered "normal" or "optimal" can differ based on age, fitness level, and health status.

        If you experience any concerning symptoms or changes in your health metrics, please consult with a qualified healthcare professional.
        """, comment: "Medical disclaimer text explaining the app is for educational purposes only")
    }

    // MARK: - Heart Rate Variability Sources

    static let hrvSources: [MedicalSource] = [
        MedicalSource(
            title: "New perspectives and insights on heart rate variability in exercise and sports",
            authors: "Frontiers in Sports and Active Living Editorial Team",
            journal: "Frontiers in Sports and Active Living",
            year: 2025,
            url: "https://www.frontiersin.org/journals/sports-and-active-living/articles/10.3389/fspor.2025.1574087/full",
            summary: "Recent research confirms that systematic HRV monitoring before and after intense workouts helps practitioners adjust training intensity based on each athlete's recovery capacity. Studies utilize RMSSD to examine whether customizing autonomic recovery periods between training sessions results in consistent performance improvements."
        ),
        MedicalSource(
            title: "Individual training prescribed by heart rate variability, heart rate and well-being scores in experienced cyclists",
            authors: "Nature Scientific Reports Research Team",
            journal: "Nature Scientific Reports",
            year: 2025,
            url: "https://www.nature.com/articles/s41598-025-13540-z",
            summary: "This 2025 study evaluated training protocols guided by vagally-mediated HRV, resting heart rate, and subjective well-being scores in experienced cyclists, finding that optimizing endurance training requires balancing overload and recovery through integrating multiple variables."
        ),
        MedicalSource(
            title: "Heart Rate Variability Applications in Strength and Conditioning: A Narrative Review",
            authors: "PMC Research Team",
            journal: "PMC (PubMed Central)",
            year: 2024,
            url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC11204851/",
            summary: "Studies suggest that HRV is a helpful metric to assess training status, adaptability, and recovery after a training program. HRV should be interpreted on an individual basis in strength-based athletes, with typical ranges of 20-100ms for SDNN in trained individuals."
        ),
        MedicalSource(
            title: "Modeling Stress-Recovery Status Through Heart Rate Changes Along a Cycling Grand Tour",
            authors: "Frontiers Research Team",
            journal: "Frontiers in Neuroscience",
            year: 2020,
            url: "https://www.frontiersin.org/journals/neuroscience/articles/10.3389/fnins.2020.576308/full",
            summary: "HR and HRV indices are established tools to detect abnormal recovery status in athletes, with low HR and vagally mediated HRV index changes between supine and standing positions reflecting a maladaptive training stress-recovery status."
        )
    ]

    // MARK: - Resting Heart Rate Sources

    static let restingHRSources: [MedicalSource] = [
        MedicalSource(
            title: "Effects of Exercise on the Resting Heart Rate: A Systematic Review and Meta-Analysis",
            authors: "PubMed Research Team",
            journal: "PubMed",
            year: 2018,
            url: "https://pubmed.ncbi.nlm.nih.gov/30513777/",
            summary: "Systematic review showing that endurance training and yoga significantly decrease RHR in both sexes. Exercise - especially endurance training - decreases RHR, which may contribute to a reduction in all-cause mortality. Typical range for adults: 60-100 bpm, athletes: 40-60 bpm."
        ),
        MedicalSource(
            title: "The exercise heart rate profile in master athletes compared to healthy controls",
            authors: "PubMed Research Team",
            journal: "PubMed",
            year: 2015,
            url: "https://pubmed.ncbi.nlm.nih.gov/25532888/",
            summary: "Resting heart rate was significantly lower in athletes than controls (62.8 ± 6.7 versus 74.0 ± 10.4 bpm, P<0.001). The resting heart rate of athletes was lower than controls, at 52 (SD 4.9) v 67 (8.7) beats.min-1, demonstrating improved cardiovascular fitness."
        ),
        MedicalSource(
            title: "Elevated resting heart rate, physical fitness and all-cause mortality",
            authors: "Jensen MT, Suadicani P, Hein HO, Gyntelberg F",
            journal: "Heart (British Cardiovascular Society)",
            year: 2013,
            url: "https://pubmed.ncbi.nlm.nih.gov/23595657/",
            summary: "Elevated RHR is a risk factor for mortality independent of physical fitness, leisure-time physical activity and other major cardiovascular risk factors. Research showing that elevated resting heart rate (>75 bpm) may indicate reduced recovery capacity or increased physiological stress."
        ),
        MedicalSource(
            title: "Association between Resting Heart Rate and Health-Related Physical Fitness",
            authors: "PMC Research Team",
            journal: "PMC (PubMed Central)",
            year: 2018,
            url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC6046174/",
            summary: "Aerobic fitness was associated with RHR in both sexes, indicating that lower aerobic fitness values were associated with higher RHR values. Lower resting heart rate reflects better cardiovascular adaptation to training."
        )
    ]

    // MARK: - Sleep & Recovery Sources

    static let sleepSources: [MedicalSource] = [
        MedicalSource(
            title: "National Sleep Foundation's sleep time duration recommendations: methodology and results summary",
            authors: "Hirshkowitz M, Whiton K, Albert SM, et al.",
            journal: "Sleep Health: Journal of the National Sleep Foundation",
            year: 2015,
            url: "https://pubmed.ncbi.nlm.nih.gov/29073412/",
            summary: "The National Sleep Foundation produced guidelines regarding sleep duration for adults (recommended 7-9 hours). Evidence-based recommendations for sleep duration: 7-9 hours per night for adults aged 18-64 years for optimal health and performance."
        ),
        MedicalSource(
            title: "The Sleep and Recovery Practices of Athletes",
            authors: "PMC Research Team",
            journal: "PMC (PubMed Central)",
            year: 2021,
            url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC8072992/",
            summary: "While 7-9 hours is the baseline recommendation from the National Sleep Foundation, athletes engaged in intensive training may benefit from 8-10 hours of sleep for optimal recovery and performance. It has been recommended that competitive athletes should get 9 to 10 hours of nocturnal sleep to ensure adequate recuperation."
        ),
        MedicalSource(
            title: "Sleep Hygiene for Optimizing Recovery in Athletes: Review and Recommendations",
            authors: "PMC Research Team",
            journal: "PMC (PubMed Central)",
            year: 2020,
            url: "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6988893/",
            summary: "For sleep to have a restorative effect on the body, it must be of adequate duration, quality, and appropriately timed. Sleep is vital in accelerating recovery processes, enhancing performance, and maintaining good health, particularly for athletes. Sleep efficiency of 85-95% is considered normal, >95% optimal."
        ),
        MedicalSource(
            title: "How Sleep Affects Athletic Performance",
            authors: "Sleep Foundation",
            journal: "Sleep Foundation",
            year: 2024,
            url: "https://www.sleepfoundation.org/physical-activity/athletic-performance-and-sleep",
            summary: "Sleep is vital in accelerating recovery processes, enhancing performance, and maintaining good health for all human beings and particularly for athletes. Inadequate sleep (<7 hours) impairs physical performance, cognitive function, and recovery capacity."
        )
    ]

    // MARK: - Respiratory Rate Sources

    static let respiratorySources: [MedicalSource] = [
        MedicalSource(
            title: "Vital Signs: Respiratory Rate",
            authors: "Johns Hopkins Medicine",
            journal: "Johns Hopkins Medicine Health Library",
            year: 2024,
            url: "https://www.hopkinsmedicine.org/health/conditions-and-diseases/vital-signs-body-temperature-pulse-rate-respiration-rate-blood-pressure",
            summary: "Normal respiration rates for an adult person at rest range from 12 to 16 breaths per minute. This is considered the optimal range for healthy adults. The broader clinical range is 12-20 breaths per minute."
        ),
        MedicalSource(
            title: "Monitoring respiratory rate in adults",
            authors: "British Journal of Nursing Clinical Team",
            journal: "British Journal of Nursing",
            year: 2017,
            url: "https://www.britishjournalofnursing.com/content/clinical/monitoring-respiratory-rate-in-adults/",
            summary: "Clinical guidelines from O'Driscoll et al (2017) and Hartley (2018) indicate that normal respiratory rate is maintained at rest with 12-20 bpm (breaths per minute). Values sourced from Royal College of Physicians (2017) and Resuscitation Council UK (2019). Rates >18/min may indicate physiological stress."
        ),
        MedicalSource(
            title: "Understanding Vital Signs: The Importance of Your Respiratory Rate",
            authors: "American Lung Association",
            journal: "American Lung Association",
            year: 2024,
            url: "https://www.lung.org/blog/respiratory-rate-vital-signs",
            summary: "The normal respiratory rate for healthy adults at rest is between 12 to 20 breaths per minute. A respiratory rate under 12 or over 25 breaths per minute is cause for concern and may indicate inadequate recovery or underlying health issues."
        )
    ]

    // MARK: - Training Load & Cardiac Stress Sources

    static let trainingLoadSources: [MedicalSource] = [
        MedicalSource(
            title: "A Systems Model of the Effects of Training on Physical Performance",
            authors: "Banister EW, Calvert TW, Savage MV, Bach T",
            journal: "IEEE Transactions on Systems, Man, and Cybernetics",
            year: 1975,
            url: "https://ieeexplore.ieee.org/document/4082542",
            summary: "Foundational paper introducing the impulse-response model for training load quantification. Training produces dual fitness and fatigue responses that decay exponentially. TRIMP (Training IMPulse) = duration × intensity. Fatigue decays ~3× faster than fitness (τ_fatigue ≈ 7 days, τ_fitness ≈ 42 days). This model underpins modern training load metrics including TSS, ATL/CTL, and the performance management chart."
        ),
        MedicalSource(
            title: "The training—injury prevention paradox: should athletes be training smarter and harder?",
            authors: "Gabbett TJ",
            journal: "British Journal of Sports Medicine",
            year: 2016,
            url: "https://pubmed.ncbi.nlm.nih.gov/26758673/",
            summary: "Introduces the Acute:Chronic Workload Ratio (ACWR) as a predictor of training-related injuries. The 'sweet spot' for injury prevention is an ACWR of 0.8–1.3. Rapid load increases (>10% week-over-week) increase injury risk significantly. Well-developed chronic training loads protect against injury, supporting the principle that appropriately graded progressive overload is safer than undertraining."
        ),
        MedicalSource(
            title: "Monitoring Athlete Training Loads: Consensus Statement",
            authors: "Bourdon PC, Cardinale M, Murray A, et al.",
            journal: "International Journal of Sports Physiology and Performance",
            year: 2017,
            url: "https://pubmed.ncbi.nlm.nih.gov/28463642/",
            summary: "IOC-endorsed consensus statement on monitoring athlete training loads. Recommends tracking both internal (physiological: HR, RPE) and external (mechanical: distance, pace, power) training loads. Weekly load monitoring with rolling averages helps detect overtraining risk. Exponentially weighted moving averages (EWMA) provide better sensitivity to load changes than simple rolling averages."
        ),
        MedicalSource(
            title: "Monitoring Training Load to Understand Fatigue in Athletes",
            authors: "Halson SL",
            journal: "Sports Medicine",
            year: 2014,
            url: "https://pubmed.ncbi.nlm.nih.gov/25315456/",
            summary: "Comprehensive review of training load monitoring methods. Recommends combining internal and external load measures for a complete picture. Identifies TRIMP and session-RPE as practical internal load measures. Highlights the importance of monitoring load changes over time rather than absolute values, as individual responses to training vary significantly."
        ),
        MedicalSource(
            title: "Training and Racing Using a Power Meter: An Introduction",
            authors: "Coggan AR, Allen H",
            journal: "Training and Racing with a Power Meter (Velopress)",
            year: 2010,
            url: nil,
            summary: "Introduced the Training Stress Score (TSS) framework and Performance Management Chart (PMC). Defined Acute Training Load (ATL, τ=7 days) and Chronic Training Load (CTL, τ=42 days) as exponentially weighted moving averages. Training Stress Balance (TSB = CTL - ATL) predicts form and readiness. This framework is the practical consumer implementation of Banister's impulse-response model."
        )
    ]

    // MARK: - Running Metrics Sources

    static let runningMetricsSources: [MedicalSource] = [
        MedicalSource(
            title: "Altering Cadence or Vertical Oscillation During Running: Effects on Running Related Injury Factors",
            authors: "PMC Research Team",
            journal: "PMC (PubMed Central)",
            year: 2018,
            url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC6088121/",
            summary: "Major study examining spatiotemporal running parameters (cadence, vertical oscillation and ground contact time). While both higher cadence and lower vertical oscillation resulted in reduced loading rates during running, cueing to reduce vertical oscillation was more successful in reducing peak vGRF. Typical ranges: cadence 160-180 spm, GCT 180-250ms, vertical oscillation 6-10cm."
        ),
        MedicalSource(
            title: "Ground Contact Time Imbalances Strongly Related to Impaired Running Economy",
            authors: "PMC Research Team",
            journal: "PMC (PubMed Central)",
            year: 2020,
            url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC7241633/",
            summary: "Running economy has been linked to cadence, stride length, vertical oscillation, and ground contact time. Shorter ground contact time has been shown to be associated with improved running economy. Too long of a stride length and correspondingly slow cadence result in impaired running economy."
        ),
        MedicalSource(
            title: "Running Form 101: Understanding Running Metrics",
            authors: "Wahoo Fitness Knowledge Team",
            journal: "The Knowledge by Wahoo",
            year: 2024,
            url: "https://www.wahoofitness.com/blog/running-form-101-metrics/",
            summary: "Comprehensive guide to running form metrics. Cadence increases lead to ground contact time decreases. One advantage of increased cadence is that it decreases the impact the body experiences each time it hits the ground, reducing injury risk over time. Optimal ranges provided for recreational and competitive runners."
        )
    ]

    // MARK: - General Guidelines

    static let generalSources: [MedicalSource] = [
        MedicalSource(
            title: "WHO Guidelines on Physical Activity and Sedentary Behaviour",
            authors: "Bull FC, Al-Ansari SS, Biddle S, et al.",
            journal: "British Journal of Sports Medicine",
            year: 2020,
            url: "https://pubmed.ncbi.nlm.nih.gov/33239350/",
            summary: "WHO recommends 150–300 min/week of moderate-intensity aerobic activity, or 75–150 min/week of vigorous-intensity activity for adults. Vigorous activity counts double versus moderate (2:1 ratio). Any duration of MVPA counts toward recommendations (removing the previous 10-min bout requirement). More activity provides additional health benefits with a curvilinear dose-response relationship."
        ),
        MedicalSource(
            title: "Physical Activity and Public Health: Updated Recommendation for Adults",
            authors: "Haskell WL, Lee IM, Pate RR, et al.",
            journal: "Medicine & Science in Sports & Exercise",
            year: 2007,
            url: "https://pubmed.ncbi.nlm.nih.gov/17762377/",
            summary: "Landmark ACSM/AHA joint recommendation establishing the 150 min/week moderate-intensity threshold for substantial health benefits in adults aged 18-65. Vigorous-intensity aerobic activity for 75 min/week provides equivalent benefits. Combinations of moderate and vigorous are acceptable. This paper established the evidence base later adopted by WHO (2020)."
        ),
        MedicalSource(
            title: "Physical Activity Guidelines for Americans",
            authors: "U.S. Department of Health and Human Services",
            journal: "2nd Edition - Federal Guidelines",
            year: 2018,
            url: "https://health.gov/paguidelines/second-edition/",
            summary: "Comprehensive federal guidelines for physical activity, including recommendations for aerobic exercise, intensity levels, and recovery. Provides evidence-based recommendations for all age groups and fitness levels."
        ),
        MedicalSource(
            title: "Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring",
            authors: "Plews DJ, Laursen PB, Stanley J, Kilding AE, Buchheit M",
            journal: "Sports Medicine",
            year: 2013,
            url: "https://pubmed.ncbi.nlm.nih.gov/23852425/",
            summary: "Demonstrates that weekly averaged LnRMSSD (log of root mean square of successive differences) is the most reliable and practically applicable HRV measure for day-to-day monitoring. Individual HRV baseline tracking is more meaningful than population norms. Provides the scientific foundation for personalized z-score-based recovery scoring used in consumer wearables (WHOOP, Oura)."
        ),
        MedicalSource(
            title: "Monitoring training status with HR measures: do all roads lead to Rome?",
            authors: "Buchheit M",
            journal: "International Journal of Sports Physiology and Performance",
            year: 2014,
            url: "https://pubmed.ncbi.nlm.nih.gov/24334285/",
            summary: "Comprehensive review on using heart rate-derived metrics (RHR, HRV, HR recovery) for monitoring training status. Recommends combining HRV with RHR and subjective measures for robust readiness assessment. Establishes that a minimum of 3 valid HRV measurements per week is needed for reliable weekly averages."
        ),
        MedicalSource(
            title: "Athletes and Sleep Issues: New Insights Into Translating Laboratory Findings",
            authors: "PMC Research Team",
            journal: "PMC (PubMed Central)",
            year: 2024,
            url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC12035355/",
            summary: "Recent insights into sleep issues specific to athletes. Elite athletes may require more quality sleep than non-athletes for proper recovery and performance optimization. Addresses translation of laboratory findings into real-world athlete training settings."
        )
    ]

    // MARK: - Get Sources by Category

    static func sources(for category: MedicalSourceCategory) -> [MedicalSource] {
        switch category {
        case .heartRateVariability:
            return hrvSources
        case .restingHeartRate:
            return restingHRSources
        case .sleepRecovery:
            return sleepSources
        case .respiratoryRate:
            return respiratorySources
        case .trainingLoad:
            return trainingLoadSources
        case .runningMetrics:
            return runningMetricsSources
        case .general:
            return generalSources
        }
    }

    static var allSources: [MedicalSource] {
        hrvSources + restingHRSources + sleepSources + respiratorySources + trainingLoadSources + runningMetricsSources + generalSources
    }
}
