import type {
  ChatDataPayload,
  HealthProfileData,
  PersonalBaselineData,
  RecentWorkoutsData,
  RecoveryData,
  WorkoutData,
} from './types'
import { formatDistance, formatDuration, formatPace, getLanguageName } from './utils'

// Parse pace string "M'SS\"" to seconds for calculations
function parsePaceToSeconds(paceStr: string): number | null {
  const match = paceStr.match(/(\d+)'(\d+)"?/)
  if (!match) return null
  return parseInt(match[1]) * 60 + parseInt(match[2])
}

// Analyze splits for pacing strategy and consistency
function analyzeSplits(splits: Array<{ kilometer: number; pace: string; time: string }>): string {
  if (splits.length < 2) return ''

  const paceSeconds = splits
    .map((s) => parsePaceToSeconds(s.pace))
    .filter((p): p is number => p !== null)
  if (paceSeconds.length < 2) return ''

  // Pace consistency (coefficient of variation)
  const avgPaceSec = paceSeconds.reduce((a, b) => a + b, 0) / paceSeconds.length
  const variance =
    paceSeconds.reduce((sum, p) => sum + (p - avgPaceSec) ** 2, 0) / paceSeconds.length
  const cv = (Math.sqrt(variance) / avgPaceSec) * 100

  // Negative/positive split detection
  const midpoint = Math.floor(paceSeconds.length / 2)
  const firstHalfAvg = paceSeconds.slice(0, midpoint).reduce((a, b) => a + b, 0) / midpoint
  const secondHalfAvg =
    paceSeconds.slice(midpoint).reduce((a, b) => a + b, 0) / (paceSeconds.length - midpoint)
  const splitDiff = secondHalfAvg - firstHalfAvg

  // Fastest and slowest splits
  const fastest = Math.min(...paceSeconds)
  const slowest = Math.max(...paceSeconds)
  const fastestKm = splits[paceSeconds.indexOf(fastest)]?.kilometer
  const slowestKm = splits[paceSeconds.indexOf(slowest)]?.kilometer

  let analysis = `\nDerived Split Analysis:\n`
  analysis += `- Pace Consistency (CV): ${cv.toFixed(1)}%`
  if (cv < 3) analysis += ` → Excellent pacing`
  else if (cv < 6) analysis += ` → Good pacing`
  else if (cv < 10) analysis += ` → Moderate variation`
  else analysis += ` → High variation (investigate cause)`
  analysis += `\n`

  if (splitDiff < -3) {
    analysis += `- Pacing Strategy: Negative split (${Math.abs(splitDiff).toFixed(0)}s/km faster in 2nd half) → Great execution\n`
  } else if (splitDiff > 5) {
    analysis += `- Pacing Strategy: Positive split (${splitDiff.toFixed(0)}s/km slower in 2nd half) → Possible fatigue or too fast start\n`
  } else {
    analysis += `- Pacing Strategy: Even splits → Well-controlled effort\n`
  }

  analysis += `- Fastest: km ${fastestKm} | Slowest: km ${slowestKm} (spread: ${slowest - fastest}s)\n`

  // Detect fade pattern (last 2 kms significantly slower)
  if (paceSeconds.length >= 4) {
    const lastTwo = paceSeconds.slice(-2)
    const lastTwoAvg = lastTwo.reduce((a, b) => a + b, 0) / 2
    const fadeAmount = lastTwoAvg - avgPaceSec
    if (fadeAmount > 8) {
      analysis += `- ⚠️ Late fade detected: last 2 km avg ${fadeAmount.toFixed(0)}s/km slower than overall → Possible energy depletion or pacing issue\n`
    }
  }

  return analysis
}

// Estimate workout intensity from available data
function estimateIntensity(workout: WorkoutData): string {
  let intensity = ''

  if (workout.heartRate?.avg && workout.heartRate?.max) {
    const hrReserveEstimate = (workout.heartRate.avg / workout.heartRate.max) * 100
    intensity += `- Estimated Intensity: ${hrReserveEstimate.toFixed(0)}% of max HR`
    if (hrReserveEstimate < 70) intensity += ` → Easy/Recovery zone`
    else if (hrReserveEstimate < 80) intensity += ` → Aerobic/Endurance zone`
    else if (hrReserveEstimate < 88) intensity += ` → Tempo/Threshold zone`
    else intensity += ` → High intensity/VO2max zone`
    intensity += `\n`
  }

  // Running economy indicator: power vs pace
  if (workout.runningPower && workout.pace) {
    const powerPerPace = workout.runningPower / (1 / workout.pace)
    intensity += `- Power Efficiency: ${powerPerPace.toFixed(1)} W·min/km (lower = more efficient)\n`
  }

  // Cadence-stride relationship
  if (workout.cadence && workout.strideLength && workout.pace) {
    const speedMps = (workout.cadence * workout.strideLength) / 60
    intensity += `- Cadence×Stride Speed: ${(speedMps * 3.6).toFixed(1)} km/h\n`
  }

  return intensity
}

// Build workout context from data
function buildWorkoutContext(workout: WorkoutData): string {
  let context = `# 🏃 Single Workout Analysis\n\n`
  context += `**Date:** ${workout.date}\n`
  context += `**Duration:** ${formatDuration(workout.duration)}\n`
  context += `**Distance:** ${formatDistance(workout.distance)}\n`

  if (workout.calories) {
    context += `**Calories:** ${Math.round(workout.calories)} kcal\n`
  }

  if (workout.pace) {
    context += `**Average Pace:** ${formatPace(workout.pace)}\n`
  }

  if (workout.speed) {
    context += `**Average Speed:** ${workout.speed.toFixed(1)} km/h\n`
  }

  // Heart rate
  if (workout.heartRate) {
    context += `\n## Heart Rate\n`
    if (workout.heartRate.avg) {
      context += `- Average: ${Math.round(workout.heartRate.avg)} bpm`
      if (workout.heartRate.min && workout.heartRate.max) {
        context += ` | Min: ${Math.round(workout.heartRate.min)} | Max: ${Math.round(workout.heartRate.max)}`
        const hrRange = workout.heartRate.max - workout.heartRate.min
        context += ` | Range: ${Math.round(hrRange)} bpm`
      }
      context += `\n`
    }
  }

  // Performance metrics
  const perfMetrics: string[] = []
  if (workout.minPace) perfMetrics.push(`Best Pace: ${formatPace(workout.minPace)}`)
  if (workout.cadence) perfMetrics.push(`Cadence: ${Math.round(workout.cadence)} spm`)
  if (workout.strideLength) perfMetrics.push(`Stride: ${workout.strideLength.toFixed(2)} m`)
  if (workout.runningPower) perfMetrics.push(`Power: ${Math.round(workout.runningPower)} W`)
  if (workout.vo2Max) perfMetrics.push(`VO2 Max: ${workout.vo2Max.toFixed(1)} ml/kg/min`)
  if (workout.elevationGain)
    perfMetrics.push(`Elevation Gain: ${Math.round(workout.elevationGain)} m`)

  if (perfMetrics.length > 0) {
    context += `\n## Performance Metrics\n`
    for (const m of perfMetrics) {
      context += `- ${m}\n`
    }
  }

  // Biomechanics
  const bioMetrics: string[] = []
  if (workout.groundContactTime)
    bioMetrics.push(`Ground Contact Time: ${Math.round(workout.groundContactTime)} ms`)
  if (workout.verticalOscillation)
    bioMetrics.push(`Vertical Oscillation: ${workout.verticalOscillation.toFixed(1)} cm`)
  if (workout.mobility) {
    const m = workout.mobility
    if (m.walkingSteadiness)
      bioMetrics.push(`Walking Steadiness: ${m.walkingSteadiness.toFixed(1)}%`)
    if (m.walkingAsymmetry) bioMetrics.push(`Walking Asymmetry: ${m.walkingAsymmetry.toFixed(1)}%`)
    if (m.doubleSupportPercentage)
      bioMetrics.push(`Double Support: ${m.doubleSupportPercentage.toFixed(1)}%`)
    if (m.walkingSpeed) bioMetrics.push(`Walking Speed: ${m.walkingSpeed.toFixed(1)} km/h`)
    if (m.stairAscentSpeed) bioMetrics.push(`Stair Ascent: ${m.stairAscentSpeed.toFixed(1)} km/h`)
    if (m.stairDescentSpeed)
      bioMetrics.push(`Stair Descent: ${m.stairDescentSpeed.toFixed(1)} km/h`)
  }

  if (bioMetrics.length > 0) {
    context += `\n## Biomechanics & Mobility\n`
    for (const m of bioMetrics) {
      context += `- ${m}\n`
    }
  }

  // Splits
  if (workout.splits && workout.splits.length > 0) {
    context += `\n## Splits (per km)\n`
    for (const split of workout.splits.slice(0, 10)) {
      context += `  km ${split.kilometer}: ${split.pace} (${split.time})\n`
    }
    // Add derived split analysis
    context += analyzeSplits(workout.splits)
  }

  // Derived intensity analysis
  const intensity = estimateIntensity(workout)
  if (intensity) {
    context += `\n## Derived Analysis\n`
    context += intensity
  }

  return context
}

// Build recovery context from data
function buildRecoveryContext(recovery: RecoveryData): string {
  let context = `# 🏃 Recovery Status\n\n`

  if (recovery.restingHeartRate) {
    context += `- Resting HR: ${Math.round(recovery.restingHeartRate)} bpm\n`
  }

  if (recovery.hrv) {
    context += `- HRV: ${Math.round(recovery.hrv)} ms (SDNN)\n`
  }

  if (recovery.sleepData) {
    const hours = recovery.sleepData.totalDuration / 3600
    context += `- Sleep: ${hours.toFixed(1)}h (efficiency: ${Math.round(recovery.sleepData.efficiency)}%)\n`
    if (recovery.sleepData.deepDuration && recovery.sleepData.remDuration) {
      const deepHours = recovery.sleepData.deepDuration / 3600
      const remHours = recovery.sleepData.remDuration / 3600
      context += `  - Deep: ${deepHours.toFixed(1)}h, REM: ${remHours.toFixed(1)}h\n`
    }
  }

  if (recovery.walkingHeartRate) {
    context += `- Walking HR: ${Math.round(recovery.walkingHeartRate)} bpm\n`
  }

  if (recovery.respiratoryRate) {
    context += `- Respiratory Rate: ${Math.round(recovery.respiratoryRate)} breaths/min\n`
  }

  return context
}

// Classify workout intensity based on available data
function classifyWorkoutIntensity(w: WorkoutData): string {
  if (w.heartRate?.avg && w.heartRate?.max) {
    const pctMax = (w.heartRate.avg / w.heartRate.max) * 100
    if (pctMax < 70) return 'Easy'
    if (pctMax < 80) return 'Moderate'
    if (pctMax < 88) return 'Tempo'
    return 'Hard'
  }
  return ''
}

// Build recent workouts context
function buildRecentWorkoutsContext(recent: RecentWorkoutsData): string {
  let context = `# 📅 Recent Training History (Last ${recent.workouts.length} runs)\n\n`

  context += `**Weekly Summary:**\n`
  context += `- Total Volume: ${(recent.totalDistance / 1000).toFixed(1)} km\n`
  context += `- Total Time: ${formatDuration(recent.totalDuration)}\n`
  context += `- Frequency: ${recent.workouts.length} runs\n`
  context += `- Average Pace: ${formatPace(recent.avgPace)}\n`

  if (recent.weeklyVolumeChange !== undefined) {
    if (recent.weeklyVolumeChange > 10) {
      context += `- ⚠️ **Training Load Alert**: Volume increased by ${recent.weeklyVolumeChange.toFixed(1)}% - high injury risk!\n`
    } else if (recent.weeklyVolumeChange > 0) {
      context += `- ✅ Volume change: +${recent.weeklyVolumeChange.toFixed(1)}% (safe progression)\n`
    }
  }

  if (recent.daysSinceLastWorkout !== undefined) {
    context += `- Time Since Last Run: ${recent.daysSinceLastWorkout} day(s) ago`
    if (recent.daysSinceLastWorkout > 3) {
      context += ` ⚠️ (extended break)`
    }
    context += `\n`
  }

  // Derived cross-workout analysis
  const workoutsWithHR = recent.workouts.filter((w) => w.heartRate?.avg)
  const workoutsWithPace = recent.workouts.filter((w) => w.pace)
  const workoutsWithCadence = recent.workouts.filter((w) => w.cadence)

  if (workoutsWithHR.length >= 2 || workoutsWithPace.length >= 2) {
    context += `\n**Derived Training Patterns:**\n`

    // Intensity distribution
    if (workoutsWithHR.length >= 2) {
      const intensities = recent.workouts.map(classifyWorkoutIntensity).filter(Boolean)
      if (intensities.length > 0) {
        const counts: Record<string, number> = {}
        for (const i of intensities) counts[i] = (counts[i] || 0) + 1
        const distribution = Object.entries(counts)
          .map(([k, v]) => `${k}: ${v}`)
          .join(', ')
        context += `- Intensity Distribution: ${distribution}\n`
        const easyCount = counts['Easy'] || 0
        const hardCount = (counts['Tempo'] || 0) + (counts['Hard'] || 0)
        if (intensities.length >= 3 && hardCount > easyCount) {
          context += `  ⚠️ More hard sessions than easy → Risk of overtraining\n`
        }
      }
    }

    // Pace trend (first workout vs last workout)
    if (workoutsWithPace.length >= 3) {
      const paces = workoutsWithPace.map((w) => w.pace!)
      const firstThird = paces.slice(0, Math.ceil(paces.length / 3))
      const lastThird = paces.slice(-Math.ceil(paces.length / 3))
      const firstAvg = firstThird.reduce((a, b) => a + b, 0) / firstThird.length
      const lastAvg = lastThird.reduce((a, b) => a + b, 0) / lastThird.length
      const diff = lastAvg - firstAvg
      if (Math.abs(diff) > 0.05) {
        context += `- Pace Trend: ${diff < 0 ? '📈 Improving' : '📉 Slowing'} (${Math.abs(diff * 60).toFixed(0)}s/km shift)\n`
      } else {
        context += `- Pace Trend: Stable\n`
      }
    }

    // HR efficiency trend (HR at similar pace)
    if (workoutsWithHR.length >= 3 && workoutsWithPace.length >= 3) {
      const hrPaceRatios = recent.workouts
        .filter((w) => w.heartRate?.avg && w.pace)
        .map((w) => w.heartRate!.avg! / w.pace!)
      if (hrPaceRatios.length >= 3) {
        const firstRatio = hrPaceRatios[0]
        const lastRatio = hrPaceRatios[hrPaceRatios.length - 1]
        const ratioDiff = lastRatio - firstRatio
        if (Math.abs(ratioDiff) > 1) {
          context += `- HR Efficiency: ${ratioDiff < 0 ? '📈 Improving (lower HR at same pace)' : '📉 Declining (higher HR at same pace)'}\n`
        }
      }
    }

    // Cadence consistency across workouts
    if (workoutsWithCadence.length >= 2) {
      const cadences = workoutsWithCadence.map((w) => w.cadence!)
      const avgCadence = cadences.reduce((a, b) => a + b, 0) / cadences.length
      const cadenceVariance =
        cadences.reduce((sum, c) => sum + (c - avgCadence) ** 2, 0) / cadences.length
      const cadenceCV = (Math.sqrt(cadenceVariance) / avgCadence) * 100
      context += `- Avg Cadence: ${Math.round(avgCadence)} spm (consistency: ${cadenceCV < 3 ? 'excellent' : cadenceCV < 6 ? 'good' : 'variable'})\n`
    }

    // Distance distribution
    const distances = recent.workouts.map((w) => w.distance / 1000)
    const shortRuns = distances.filter((d) => d < 5).length
    const mediumRuns = distances.filter((d) => d >= 5 && d < 10).length
    const longRuns = distances.filter((d) => d >= 10).length
    if (distances.length >= 3) {
      context += `- Distance Mix: Short(<5km): ${shortRuns}, Medium(5-10km): ${mediumRuns}, Long(10km+): ${longRuns}\n`
    }
  }

  context += `\n**Complete Workout Detail (All ${recent.workouts.length} runs):**\n`
  for (let i = 0; i < recent.workouts.length; i++) {
    const w = recent.workouts[i]
    const intensity = classifyWorkoutIntensity(w)
    context += `\n${i + 1}. **${w.date}**${intensity ? ` [${intensity}]` : ''}\n`

    // Basic metrics
    context += `   Duration: ${formatDuration(w.duration)} | Distance: ${formatDistance(w.distance)}\n`

    if (w.pace || w.speed) {
      context += `   Pace: ${w.pace ? formatPace(w.pace) : 'N/A'}`
      if (w.speed) context += ` | Speed: ${w.speed.toFixed(1)} km/h`
      context += `\n`
    }

    if (w.minPace) {
      context += `   Best Pace: ${formatPace(w.minPace)}\n`
    }

    if (w.calories) {
      context += `   Calories: ${Math.round(w.calories)} kcal\n`
    }

    if (w.heartRate && (w.heartRate.avg || w.heartRate.min || w.heartRate.max)) {
      context += `   Heart Rate: Avg ${w.heartRate.avg ? Math.round(w.heartRate.avg) : 'N/A'} bpm`
      if (w.heartRate.min && w.heartRate.max) {
        context += ` (${Math.round(w.heartRate.min)}-${Math.round(w.heartRate.max)} bpm)`
      }
      context += `\n`
    }

    if (w.cadence || w.strideLength || w.runningPower) {
      context += `   Technique:`
      if (w.cadence) context += ` Cadence ${Math.round(w.cadence)} spm |`
      if (w.strideLength) context += ` Stride ${w.strideLength.toFixed(2)}m |`
      if (w.runningPower) context += ` Power ${Math.round(w.runningPower)}W`
      context += `\n`
    }

    if (w.groundContactTime || w.verticalOscillation) {
      context += `   Biomechanics:`
      if (w.groundContactTime) context += ` GCT ${Math.round(w.groundContactTime)}ms |`
      if (w.verticalOscillation) context += ` Vert Osc ${w.verticalOscillation.toFixed(1)}cm`
      context += `\n`
    }

    if (w.vo2Max) {
      context += `   VO2 Max: ${w.vo2Max.toFixed(1)} ml/kg/min\n`
    }

    if (w.elevationGain) {
      context += `   Elevation Gain: ${Math.round(w.elevationGain)} m\n`
    }

    if (w.mobility && Object.values(w.mobility).some((v) => v !== undefined)) {
      context += `   Mobility:`
      if (w.mobility.walkingAsymmetry)
        context += ` Asymmetry ${w.mobility.walkingAsymmetry.toFixed(1)}% |`
      if (w.mobility.doubleSupportPercentage)
        context += ` DblSupport ${w.mobility.doubleSupportPercentage.toFixed(1)}% |`
      if (w.mobility.walkingSteadiness)
        context += ` Steadiness ${w.mobility.walkingSteadiness.toFixed(1)}%`
      context += `\n`
    }

    if (w.splits && w.splits.length > 0) {
      context += `   Splits: `
      for (let j = 0; j < w.splits.length; j++) {
        const split = w.splits[j]
        context += `km${split.kilometer}:${split.pace}`
        if (j < w.splits.length - 1) context += ` | `
      }
      context += `\n`
    }
  }

  return context
}

// Build health profile context
function buildHealthProfileContext(profile: HealthProfileData): string {
  let context = `# 👤 Health Profile\n\n`

  if (profile.age) {
    context += `- Age: ${profile.age} years\n`
  }

  if (profile.sex) {
    context += `- Sex: ${profile.sex}\n`
  }

  if (profile.bodyMass) {
    context += `- Weight: ${profile.bodyMass.toFixed(1)} kg\n`
  }

  if (profile.bodyFatPercentage) {
    context += `- Body Fat: ${profile.bodyFatPercentage.toFixed(1)}%\n`
  }

  if (profile.exerciseTime) {
    context += `- Today's Exercise: ${Math.round(profile.exerciseTime)} min\n`
  }

  let hasCrossTraining = false
  if (profile.cyclingDistance && profile.cyclingDistance > 0) {
    context += `- Cycling (7d): ${(profile.cyclingDistance / 1000).toFixed(1)} km\n`
    hasCrossTraining = true
  }
  if (profile.swimmingDistance && profile.swimmingDistance > 0) {
    context += `- Swimming (7d): ${(profile.swimmingDistance / 1000).toFixed(1)} km\n`
    hasCrossTraining = true
  }

  if (!hasCrossTraining) {
    context += `\n💡 No complementary sport detected (cycling, swimming) - suggest adding for balanced fitness\n`
  }

  return context
}

// Build personal baseline context for comparison
function buildBaselineContext(baseline: PersonalBaselineData): string {
  let context = `# 📈 Personal Baseline (Your Normal Values)\n\n`

  context += `**Data Quality:** ${baseline.isReliable ? `✅ Reliable (${baseline.dataPointCount} days)` : `⚠️ Building (${baseline.dataPointCount}/7 days needed)`}\n\n`

  if (baseline.restingHeartRateAverage) {
    context += `- Your Normal Resting HR: ${Math.round(baseline.restingHeartRateAverage)} bpm`
    if (baseline.restingHeartRateStdDev) {
      context += ` (±${baseline.restingHeartRateStdDev.toFixed(1)} bpm)`
    }
    context += `\n`
  }

  if (baseline.hrvAverage) {
    context += `- Your Normal HRV: ${Math.round(baseline.hrvAverage)} ms`
    if (baseline.hrvStdDev) {
      context += ` (±${baseline.hrvStdDev.toFixed(1)} ms)`
    }
    context += `\n`
  }

  if (baseline.sleepDurationAverage) {
    const hours = baseline.sleepDurationAverage / 3600
    context += `- Your Normal Sleep: ${hours.toFixed(1)}h`
    if (baseline.sleepEfficiencyAverage) {
      context += ` (${Math.round(baseline.sleepEfficiencyAverage)}% efficiency)`
    }
    context += `\n`
  }

  if (baseline.respiratoryRateAverage) {
    context += `- Your Normal Respiratory Rate: ${baseline.respiratoryRateAverage.toFixed(1)} breaths/min`
    if (baseline.respiratoryRateStdDev) {
      context += ` (±${baseline.respiratoryRateStdDev.toFixed(1)})`
    }
    context += `\n`
  }

  context += `\n**IMPORTANT:** Always compare today's metrics to these personal baseline values. A deviation of more than 1-2 standard deviations is significant.\n`

  return context
}

// Main function to build the complete system prompt
export function buildWorkoutCoachPrompt(data: ChatDataPayload, language: string): string {
  const langName = getLanguageName(language)

  let systemPrompt = `You are a friendly, accessible running coach who makes data understandable for ALL levels — especially beginners.

**LANGUAGE — ZERO TOLERANCE FOR ENGLISH IN NON-ENGLISH RESPONSES:**
You MUST respond entirely in ${langName}. Every single word must be in ${langName} — no exceptions.
- NEVER use English running jargon: "pacing", "split", "overstriding", "cross-training", "drills", "pace trend", "fade", "cool-down", "warm-up", "easy run", "tempo run", "threshold"
- NEVER use abbreviations: "HR", "HRV", "GCT", "FC", "VO", "CV", "spm", "bpm" alone — always write the full term in ${langName}
- NEVER use English coaching terms: "negative split", "positive split", "even splits", "fartlek", "hill repeats"
- If you catch yourself about to write an English word, STOP and find the ${langName} equivalent

**CRITICAL — DATA INTEGRITY RULES:**
1. ONLY reference metrics that are EXPLICITLY listed in the "Runner Data" section below
2. If a metric (VO2 Max, cadence, power, etc.) does NOT appear in the data, you MUST NOT mention it — not even to say it's missing
3. NEVER invent, estimate, or round numbers that are not in the data
4. If you are unsure whether a value was provided, do NOT include it
5. Violation of these rules produces dangerous medical/training misinformation

# COMMUNICATION STYLE (HIGHEST PRIORITY — READ BEFORE ANYTHING ELSE)

You are talking to a runner who may have ZERO knowledge of running metrics. Your #1 job is to make every number meaningful and understandable.

**For EVERY metric you mention, you MUST:**
1. Use the plain-language name (NOT abbreviations) — e.g. "your cadence (how many steps you take per minute)" NOT "cadence 168 spm"
2. Explain what it means concretely — e.g. "275 ms means your foot stays on the ground a bit too long each stride — you're losing energy"
3. Say if it's good, normal, or needs work — with the ideal range for their level
4. If it needs work, explain the BENEFIT of improving — e.g. "by reducing this, you'll run lighter and with less fatigue"

**NEVER do this:**
- "Cadence 168 spm, GCT 275ms, VO 9.8cm" → meaningless to a beginner
- "CV 4.4%, positive split 29s/km" → jargon without explanation
- "Power efficiency 1536 W·min/km" → nobody understands this
- Use ANY untranslated English term in a non-English response (e.g. "pacing", "cross-training", "overstriding", "drills", "FC")
- Use abbreviations without the full translated name first (e.g. writing "FC" instead of the full term in ${langName})

**ALWAYS do this (examples in the target language):**
- Name the metric simply: "your cadence (steps per minute) is 168 — that's great! The ideal range for your level is 160-170, you're right on target."
- Explain with an image: "your ground contact time (how long your foot touches the ground each stride) is 275 ms — imagine you're 'sticking' to the ground instead of bouncing off it. Running technique exercises will help you become more dynamic."
- Connect the number to the runner's experience: "your average heart rate was 158 beats/min at a pace of 6'16/km — that means your heart was working quite hard at this speed. With training, you'll be able to hold this pace with less effort."
- Translate EVERYTHING: "coefficient of variation" → use the ${langName} equivalent, "overstriding" → use the ${langName} equivalent, "cross-training" → use the ${langName} equivalent

Use analogies and comparisons to make numbers tangible. The runner should finish reading your analysis and think "I understand exactly what I need to improve and why."

# Core Mission
Provide specific, actionable coaching insights by:
1. Analyzing metric correlations (not just individual values)
2. Detecting overtraining signals and injury risks early
3. Identifying concrete areas of improvement with measurable targets
4. Celebrating real progress backed by data

# Runner Data
`

  if (data.profile) {
    systemPrompt += buildHealthProfileContext(data.profile)
    systemPrompt += `\n`
  }

  if (data.baseline) {
    systemPrompt += buildBaselineContext(data.baseline)
    systemPrompt += `\n`
  }

  if (data.historicalSummary) {
    systemPrompt += `# Historical Training Profile\n\n`
    systemPrompt += data.historicalSummary
    systemPrompt += `\n\n---\n\n`
  }

  if (data.recovery) {
    systemPrompt += buildRecoveryContext(data.recovery)
    systemPrompt += `\n`
  }

  if (data.recentWorkouts) {
    systemPrompt += buildRecentWorkoutsContext(data.recentWorkouts)
    systemPrompt += `\n`
  }

  if (data.workout) {
    systemPrompt += buildWorkoutContext(data.workout)
    systemPrompt += `\n`
  }

  systemPrompt += `
# Analysis Framework

## Metric Correlations (ALWAYS analyze these combinations when data is available)

### Running Economy (Pace + HR)
- Compare avg HR to avg pace: lower HR at same pace = better aerobic fitness
- If HR is high but pace is slow → possible fatigue, dehydration, heat, or overtraining
- If HR is low but pace is fast → excellent fitness or well-rested state

### Pacing Analysis (from splits)
- Coefficient of Variation (CV) is pre-computed: <3% excellent, 3-6% good, 6-10% needs work, >10% investigate
- Negative split (faster 2nd half) → strong execution and good energy management
- Positive split with late fade → went out too fast OR energy depletion → recommend fueling strategy or conservative start
- Even splits → disciplined runner, good body awareness

### Cadence-Stride Relationship
- Cadence 170-180 spm is optimal for most runners
- Low cadence (<165) + long stride → overstriding → higher ground contact time → injury risk
- High cadence (>185) + short stride → possibly shuffling → check if pace matches effort
- When both cadence AND stride length are available, their product gives speed — use this to validate reported pace

### Power Analysis (when running power available)
- Power/pace ratio = efficiency indicator (lower = more efficient)
- High power + slow pace → uphill, wind, or poor economy
- Low power + fast pace → downhill, tailwind, or excellent economy
- Compare power across workouts at similar paces to track efficiency trends

### Biomechanics Red Flags (PRIORITIZE these alerts)
- Ground Contact Time >280ms + Walking Asymmetry >5% → HIGH injury risk, recommend gait analysis
- Vertical Oscillation >11cm + Ground Contact Time >270ms → wasted energy, focus on hip extension drills
- Walking Asymmetry >7% → ALWAYS flag this regardless of other metrics
- Ground Contact Time improving over weeks → positive form adaptation

## Reference Ranges (adapt to runner's level based on pace)
Use these ranges to contextualize the runner's values. When citing a range, explain it simply: "for a runner at your level, the ideal range would be between X and Y".

| Metric | What it means | Recreational (>6:00/km) | Intermediate (5:00-6:00) | Advanced (<5:00/km) |
|--------|---------------|------------------------|--------------------------|---------------------|
| Cadence (steps/min) | How many steps per minute | 160-170 | 170-180 | 175-190 |
| Ground Contact Time | How long your foot touches the ground per step | 260-320 ms | 220-260 ms | 190-230 ms |
| Vertical Oscillation | How much you bounce up with each step | 8-12 cm | 6-10 cm | 5-8 cm |
| Stride Length | Length of each step | 0.9-1.1 m | 1.1-1.3 m | 1.2-1.5 m |

## Readiness Assessment (0-100)
When asked about readiness, calculate a score based on:
- Sleep (7-9h optimal, <6h red flag)
- Resting HR (compare to baseline, +5-10 bpm = warning)
- HRV (compare to baseline, higher = better recovery)
- Training load (days since last hard workout, weekly volume)

If personal baseline is available, ALWAYS compare to the user's normal values. A deviation of >1.5 standard deviations from baseline is significant.

Score: 85-100 = intense training OK | 70-84 = moderate training | 50-69 = recovery day | <50 = rest required

## Injury Prevention
Proactively alert on combinations:
- Volume increase >10%/week (when weeklyVolumeChange available)
- Pace drop + elevated HR at same distance → fatigue accumulation
- Cadence drop + asymmetry increase → compensatory pattern → injury risk
- Multiple hard sessions without easy days between → overtraining

## Recovery Guidelines
- Easy run (<70% max HR): 24h recovery
- Moderate (70-80% max HR): 36-48h
- Hard/Long (>80% max HR or >90min): 48-72h
- Race effort: 72h to 1 week

Red flags: elevated RHR (+5-10 bpm vs baseline), HRV <30ms or >2σ below baseline, sleep <6h

# Response Guidelines
- **Lead with the most impactful insight** — not a generic summary
- **Every number needs context** — follow the COMMUNICATION STYLE rules above
- Be concise: bullet points over paragraphs
- Be honest: don't sugarcoat overtraining risks
- Proactively flag concerns even if not asked
- Use markdown formatting
- Adapt structure to the question (don't force rigid templates for simple questions)
- NEVER mention metrics that are not in the data — do NOT fabricate any value
- If data is limited, focus deeply on what IS available

**FINAL REMINDER — READ CAREFULLY:**
1. **LANGUAGE**: Respond 100% in ${langName}. Zero English words allowed in non-English responses. Translate every technical term: "pacing" → ${langName} equivalent, "overstriding" → ${langName} equivalent, "cross-training" → ${langName} equivalent, "drills" → ${langName} equivalent. No abbreviations without the full ${langName} term.
2. **DATA**: ONLY cite metrics from the data above — never fabricate values.
3. **STYLE**: EXPLAIN every metric simply — see COMMUNICATION STYLE section.
`

  return systemPrompt
}

export function buildPrompt(promptType: string, data: ChatDataPayload, language: string): string {
  if (promptType === 'workout_coach') {
    return buildWorkoutCoachPrompt(data, language)
  }

  throw new Error(`Unknown prompt type: ${promptType}`)
}
