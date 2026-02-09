import type {
  ChatDataPayload,
  HealthProfileData,
  PersonalBaselineData,
  RecentWorkoutsData,
  RecoveryData,
  WorkoutData,
} from './types'
import { formatDistance, formatDuration, formatPace, getLanguageName } from './utils'

// Build workout context from data
function buildWorkoutContext(workout: WorkoutData): string {
  let context = `Single Workout Analysis:\n`
  context += `Date: ${workout.date}\n`
  context += `Duration: ${formatDuration(workout.duration)}\n`
  context += `Distance: ${formatDistance(workout.distance)}\n`

  if (workout.calories) {
    context += `Calories: ${Math.round(workout.calories)} kcal\n`
  }

  if (workout.pace) {
    context += `Average Pace: ${formatPace(workout.pace)}\n`
  }

  if (workout.speed) {
    context += `Average Speed: ${workout.speed.toFixed(1)} km/h\n`
  }

  if (workout.heartRate) {
    context += `\nDetailed Metrics:\n`
    if (workout.heartRate.avg) {
      context += `- Heart Rate: Avg ${Math.round(workout.heartRate.avg)} bpm`
      if (workout.heartRate.min && workout.heartRate.max) {
        context += ` (Range: ${Math.round(workout.heartRate.min)}-${Math.round(workout.heartRate.max)} bpm)`
      }
      context += `\n`
    }
  }

  if (workout.minPace) {
    context += `- Best Pace: ${formatPace(workout.minPace)}\n`
  }

  if (workout.cadence) {
    context += `- Cadence: ${Math.round(workout.cadence)} spm\n`
  }

  if (workout.strideLength) {
    context += `- Stride Length: ${workout.strideLength.toFixed(2)} m\n`
  }

  if (workout.runningPower) {
    context += `- Running Power: ${Math.round(workout.runningPower)} W\n`
  }

  if (workout.vo2Max) {
    context += `- VO2 Max: ${workout.vo2Max.toFixed(1)} ml/kg/min\n`
  }

  if (workout.elevationGain) {
    context += `- Elevation Gain: ${Math.round(workout.elevationGain)} m\n`
  }

  if (workout.groundContactTime) {
    context += `- Ground Contact Time: ${Math.round(workout.groundContactTime)} ms\n`
  }

  if (workout.verticalOscillation) {
    context += `- Vertical Oscillation: ${workout.verticalOscillation.toFixed(1)} cm\n`
  }

  if (workout.mobility) {
    const m = workout.mobility
    if (
      m.walkingSteadiness ||
      m.walkingAsymmetry ||
      m.doubleSupportPercentage ||
      m.walkingSpeed ||
      m.stairAscentSpeed ||
      m.stairDescentSpeed
    ) {
      context += `\nMobility & Biomechanics:\n`
      if (m.walkingSteadiness)
        context += `- Walking Steadiness: ${m.walkingSteadiness.toFixed(1)}%\n`
      if (m.walkingAsymmetry) context += `- Walking Asymmetry: ${m.walkingAsymmetry.toFixed(1)}%\n`
      if (m.doubleSupportPercentage)
        context += `- Double Support: ${m.doubleSupportPercentage.toFixed(1)}%\n`
      if (m.walkingSpeed) context += `- Walking Speed: ${m.walkingSpeed.toFixed(1)} km/h\n`
      if (m.stairAscentSpeed)
        context += `- Stair Ascent Speed: ${m.stairAscentSpeed.toFixed(1)} km/h\n`
      if (m.stairDescentSpeed)
        context += `- Stair Descent Speed: ${m.stairDescentSpeed.toFixed(1)} km/h\n`
    }
  }

  if (workout.splits && workout.splits.length > 0) {
    context += `\nSplits (per km):\n`
    for (const split of workout.splits.slice(0, 10)) {
      context += `  km ${split.kilometer}: ${split.pace} (${split.time})\n`
    }
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

// Build recent workouts context
function buildRecentWorkoutsContext(recent: RecentWorkoutsData): string {
  let context = `# 📅 Recent Training History (Last ${recent.workouts.length} runs)\n\n`

  context += `**Weekly Summary:**\n`
  context += `- Total Volume: ${(recent.totalDistance / 1000).toFixed(1)} km\n`
  context += `- Total Time: ${formatDuration(recent.totalDuration)}\n`
  context += `- Frequency: ${recent.workouts.length} runs/week\n`
  context += `- Average Pace: ${formatPace(recent.avgPace)}\n`

  if (recent.weeklyVolumeChange !== undefined) {
    if (recent.weeklyVolumeChange > 10) {
      context += `\n⚠️ **Training Load Alert**: Volume increased by ${recent.weeklyVolumeChange.toFixed(1)}% - high injury risk!\n`
    } else if (recent.weeklyVolumeChange > 0) {
      context += `\n✅ Volume increased by ${recent.weeklyVolumeChange.toFixed(1)}% (safe progression)\n`
    }
  }

  if (recent.daysSinceLastWorkout !== undefined) {
    context += `\n**Time Since Last Run**: ${recent.daysSinceLastWorkout} day(s) ago`
    if (recent.daysSinceLastWorkout > 3) {
      context += ` ⚠️ (extended break)\n`
    } else {
      context += `\n`
    }
  }

  context += `\n**Complete Workout Detail (All ${recent.workouts.length} runs):**\n`
  for (let i = 0; i < recent.workouts.length; i++) {
    const w = recent.workouts[i]
    context += `\n${i + 1}. **${w.date}**\n`

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

    // Energy
    if (w.calories) {
      context += `   Calories: ${Math.round(w.calories)} kcal\n`
    }

    // Heart rate
    if (w.heartRate && (w.heartRate.avg || w.heartRate.min || w.heartRate.max)) {
      context += `   Heart Rate: Avg ${w.heartRate.avg ? Math.round(w.heartRate.avg) : 'N/A'} bpm`
      if (w.heartRate.min && w.heartRate.max) {
        context += ` (Range: ${Math.round(w.heartRate.min)}-${Math.round(w.heartRate.max)} bpm)`
      }
      context += `\n`
    }

    // Running technique metrics
    if (w.cadence || w.strideLength || w.runningPower) {
      context += `   Running Technique:`
      if (w.cadence) context += ` Cadence ${Math.round(w.cadence)} spm |`
      if (w.strideLength) context += ` Stride ${w.strideLength.toFixed(2)}m |`
      if (w.runningPower) context += ` Power ${Math.round(w.runningPower)}W`
      context += `\n`
    }

    // Biomechanics
    if (w.groundContactTime || w.verticalOscillation) {
      context += `   Biomechanics:`
      if (w.groundContactTime) context += ` GCT ${Math.round(w.groundContactTime)}ms |`
      if (w.verticalOscillation) context += ` Vert Osc ${w.verticalOscillation.toFixed(1)}cm`
      context += `\n`
    }

    // VO2 Max
    if (w.vo2Max) {
      context += `   VO2 Max: ${w.vo2Max.toFixed(1)} ml/kg/min\n`
    }

    // Elevation
    if (w.elevationGain) {
      context += `   Elevation Gain: ${Math.round(w.elevationGain)} m\n`
    }

    // Mobility metrics
    if (w.mobility && Object.values(w.mobility).some((v) => v !== undefined)) {
      context += `   Mobility & Balance:\n`
      if (w.mobility.walkingSteadiness)
        context += `      - Walking Steadiness: ${w.mobility.walkingSteadiness.toFixed(1)}%\n`
      if (w.mobility.walkingAsymmetry)
        context += `      - Walking Asymmetry: ${w.mobility.walkingAsymmetry.toFixed(1)}%\n`
      if (w.mobility.doubleSupportPercentage)
        context += `      - Double Support: ${w.mobility.doubleSupportPercentage.toFixed(1)}%\n`
      if (w.mobility.walkingSpeed)
        context += `      - Walking Speed: ${w.mobility.walkingSpeed.toFixed(1)} km/h\n`
      if (w.mobility.stairAscentSpeed)
        context += `      - Stair Ascent: ${w.mobility.stairAscentSpeed.toFixed(1)} km/h\n`
      if (w.mobility.stairDescentSpeed)
        context += `      - Stair Descent: ${w.mobility.stairDescentSpeed.toFixed(1)} km/h\n`
    }

    // Splits
    if (w.splits && w.splits.length > 0) {
      context += `   Splits (per km): `
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
    context += `\n💡 No cross-training detected - consider adding cycling/swimming for balanced fitness\n`
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

  let systemPrompt = `You are an expert AI running coach specializing in data-driven performance optimization, injury prevention, and personalized training.

**LANGUAGE: You MUST respond entirely in ${langName}.**

**DATA INTEGRITY: Only reference metrics explicitly provided below. Never invent, assume, or extrapolate data that is not present.**

# Core Mission
Analyze health and workout data to provide actionable insights:
1. Optimize performance through training pattern analysis
2. Prevent injuries by detecting overtraining and biomechanical issues
3. Maximize recovery by balancing training load
4. Track progress and highlight improvements

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

## Readiness Assessment (0-100)
When asked about readiness, calculate a score based on:
- Sleep (7-9h optimal, <6h red flag)
- Resting HR (compare to baseline, +5-10 bpm = warning)
- HRV (compare to baseline, higher = better recovery)
- Training load (days since last hard workout, weekly volume)

If personal baseline is available, ALWAYS compare to the user's normal values.

Score interpretation: 85-100 = intense training OK | 70-84 = moderate training | 50-69 = recovery day | <50 = rest required

## Injury Prevention
Monitor and proactively alert on:
- Volume increase >10%/week
- Pace drop at same effort
- Elevated HR at same pace
- Cadence drop or gait asymmetry
- User-reported recurring pain

## Performance Analysis
- Pace progression over time
- HR efficiency (lower HR at same pace = improvement)
- Splits consistency
- Cadence (optimal 170-180 spm)
- VO2 Max trends

## Biomechanics (when data available)
- Ground Contact Time: 200-250ms optimal, <200ms elite, >300ms needs work
- Vertical Oscillation: 6-10cm optimal, <7cm elite, >12cm excessive
- Walking Steadiness: >85% optimal, <70% concern
- Walking Asymmetry: <3% optimal, >7% injury risk
- Double Support: 20-30% optimal

## Recovery Guidelines
- Easy run (<70% max HR): 24h before next hard session
- Moderate (70-80% max HR): 36-48h
- Hard/Long (>80% max HR or >90min): 48-72h
- Race effort: 72h to 1 week

Red flags: elevated morning RHR (+5-10 bpm), HRV <30ms, sleep <6h, soreness >48h

# Response Guidelines
- Be data-driven: cite specific metrics from the provided data
- Be concise: bullet points over paragraphs
- Be actionable: every insight must include a concrete next step
- Be honest: don't sugarcoat overtraining risks
- Use markdown for readability
- Proactively flag concerns even if not asked
- Adapt response structure to the question (don't force a rigid template for simple questions)

For comprehensive analysis, organize with sections: Key Insights, Recommendations, Concerns, Next Steps.

# Tone
Professional but friendly. Motivating without being pushy. Evidence-based, not generic.

**REMINDER: Respond entirely in ${langName}.**
`

  return systemPrompt
}

export function buildPrompt(promptType: string, data: ChatDataPayload, language: string): string {
  if (promptType === 'workout_coach') {
    return buildWorkoutCoachPrompt(data, language)
  }

  throw new Error(`Unknown prompt type: ${promptType}`)
}
