# Workout and coaching follow-up — 16 September 2026

This follow-up covers the 2.0.10 changes after the Statistics and Dashboard audits. The earlier audit documents describe their original validation snapshots, including the already submitted 2.0.9.

## Corrected

- Apple Health data takes precedence over duplicate Strava activities. Native workout metadata and validated kilometer events survive the unified cache.
- Workout detail shows split duration and pace separately, including partial segments. Metric sheets show the displayed value and preserve decimal ranges. Daily walking and stair measurements are excluded from running detail.
- VO₂ context uses the latest eligible sample within the preceding seven days; the description states that it may not be measured during this workout.
- Similar workouts are earlier, completed sessions in the same environment within 30% of the reference distance. Volume, duration and calories alone are not labeled as progress.
- Coach text is left aligned and the confidence block is removed. Complete comparison analyses are cached against their inputs; failed responses retain a retry action.
- Recent coaching history is chronological, weekly comparisons use equivalent elapsed periods, and a zero prior volume does not produce a fabricated percentage. Smart suggestions use an age-based estimated HR reference and one bounded upstream attempt.
- Quota accounting errors no longer replace successful responses. IP/user counters are attempted independently; explicit KV 429 write rejections receive bounded retries. Premium model accounting also preserves an already generated answer.

## Validation

227 iOS unit and analysis tests passed. Physical-device UI checks covered workout metric sheets, similar-workout navigation, split durations and completed coaching. Dashboard/Statistics device navigation and four simulator UI scenarios were validated earlier in this release. Backend tests, TypeScript, Biome and Worker dry-run validation passed. Swift-format reported no errors and existing style warnings.

The quota incident affected three requests after route processing. Its original storage error code was not available in retained logs, so a specific KV rate limit or platform outage cannot be asserted. PostHog generation events in the inspected window reported no model errors. This is not proof that all client responses arrived in full.

## Limits

KV counters remain eventually consistent and non-atomic. Clinical thresholds are estimates, not diagnoses. Device checks cover the observed data and flows, not every permission, network or device combination. Private HealthKit data and screenshots are kept outside the repository.

Apple approved 2.0.9; the owner requested keeping it pending manual release. Apple currently rejects creation of the 2.0.10 App Store version in that state.
