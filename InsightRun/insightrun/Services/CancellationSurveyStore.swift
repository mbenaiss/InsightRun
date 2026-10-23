import Foundation

enum CancellationReason: String, CaseIterable, Identifiable {
    case tooExpensive = "too_expensive"
    case notUsefulEnough = "not_useful_enough"
    case justTryingIt = "just_trying_it"
    case missingFeature = "missing_feature"
    case technicalIssue = "technical_issue"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tooExpensive:
            String(localized: "cancellation_survey.reason.too_expensive", defaultValue: "It's too expensive")
        case .notUsefulEnough:
            String(localized: "cancellation_survey.reason.not_useful_enough", defaultValue: "It's not useful enough for me")
        case .justTryingIt:
            String(localized: "cancellation_survey.reason.just_trying_it", defaultValue: "I was just trying it out")
        case .missingFeature:
            String(localized: "cancellation_survey.reason.missing_feature", defaultValue: "A feature I need is missing")
        case .technicalIssue:
            String(localized: "cancellation_survey.reason.technical_issue", defaultValue: "I ran into a bug or a problem")
        case .other:
            String(localized: "cancellation_survey.reason.other", defaultValue: "Another reason")
        }
    }

    var symbol: String {
        switch self {
        case .tooExpensive: "tag"
        case .notUsefulEnough: "hand.thumbsdown"
        case .justTryingIt: "sparkles"
        case .missingFeature: "puzzlepiece.extension"
        case .technicalIssue: "exclamationmark.triangle"
        case .other: "ellipsis.circle"
        }
    }
}

struct CancellationSurveyRequest: Identifiable, Equatable {
    let productId: String
    let isTrial: Bool
    let unsubscribeDetectedAt: Date

    var id: Date { unsubscribeDetectedAt }
}

struct CancellationSurveyStore {
    static let maximumAge: TimeInterval = 7 * 24 * 3600

    private let defaults: UserDefaults
    private let askedKey = "com.insightrun.cancellationSurvey.askedUnsubscribeDates"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func request(
        productId: String,
        isTrial: Bool,
        willRenew: Bool,
        unsubscribeDetectedAt: Date?,
        now: Date = Date()
    ) -> CancellationSurveyRequest? {
        guard !willRenew, let unsubscribeDetectedAt,
              now.timeIntervalSince(unsubscribeDetectedAt) <= Self.maximumAge,
              !askedDates.contains(unsubscribeDetectedAt.timeIntervalSince1970) else { return nil }
        return CancellationSurveyRequest(productId: productId, isTrial: isTrial, unsubscribeDetectedAt: unsubscribeDetectedAt)
    }

    func markAsked(_ request: CancellationSurveyRequest) {
        defaults.set(askedDates + [request.unsubscribeDetectedAt.timeIntervalSince1970], forKey: askedKey)
    }

    private var askedDates: [TimeInterval] {
        defaults.array(forKey: askedKey) as? [TimeInterval] ?? []
    }
}
