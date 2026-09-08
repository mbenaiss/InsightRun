import XCTest

@testable import insightrun

final class AIResponseValidatorTests: XCTestCase {
    private let summary = "Your pace remained stable throughout this workout.\n\n## Next action\n"

    func testCompleteMarkdownAndQuotedRecommendationsAreAccepted() {
        let recommendations = [
            "Run easily for 30 minutes tomorrow.",
            "**Run easily for 30 minutes tomorrow.**",
            "*Run easily for 30 minutes tomorrow.*",
            "_Run easily for 30 minutes tomorrow._",
            "***Run easily for 30 minutes tomorrow.***",
            "\"Run easily for 30 minutes tomorrow.\"",
            "\u{201C}Run easily for 30 minutes tomorrow.\u{201D}",
            "\u{00AB} Courez facilement pendant 30 minutes demain. \u{00BB}",
            "**\u{201C}Run easily for 30 minutes tomorrow.\u{201D}**",
            "[Run easily for 30 minutes tomorrow.](https://example.com/workout)",
        ]

        for recommendation in recommendations {
            XCTAssertTrue(AIResponseValidator.isComplete(summary + recommendation), recommendation)
        }
    }

    func testTruncatedRecommendationsAreRejectedEvenWithMarkdownClosers() {
        let recommendations = [
            "For your next workout, try",
            "**For your next workout, try**",
            "*For your next workout, try*",
            "\u{201C}For your next workout, try\u{201D}",
            "[For your next workout, try](https://example.com/workout)",
            "[Run easily for 30 minutes tomorrow.](https://example.com/work",
        ]

        for recommendation in recommendations {
            XCTAssertFalse(AIResponseValidator.isComplete(summary + recommendation), recommendation)
        }
    }

    func testOnlyTerminalPunctuationCompletesTheVisibleText() {
        for punctuation in [".", "!", "?", "\u{2026}"] {
            XCTAssertTrue(AIResponseValidator.isComplete(summary + "**Run easily tomorrow\(punctuation)**"))
        }
        XCTAssertFalse(AIResponseValidator.isComplete(summary + "Run easily tomorrow"))
    }

    func testEmptyAndBriefVisibleResponsesAreRejected() {
        for response in ["", " \n\t ", "**Done.**", "[Done.](https://example.com/a-very-long-destination-path)"] {
            XCTAssertFalse(AIResponseValidator.isComplete(response), response)
        }
    }
}
