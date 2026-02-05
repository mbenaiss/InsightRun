import type {
  ChatDataPayload,
  HealthProfileData,
  PersonalBaselineData,
  RecentWorkoutsData,
  RecoveryData,
  WorkoutData,
} from './types'

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

// Format helpers
function formatDuration(seconds: number): string {
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  if (hours > 0) {
    return `${hours}h ${minutes.toString().padStart(2, '0')}m`
  }
  return `${minutes}m`
}

function formatDistance(meters: number): string {
  return `${(meters / 1000).toFixed(2)} km`
}

function formatPace(pace: number): string {
  const minutes = Math.floor(pace)
  const seconds = Math.floor((pace - minutes) * 60)
  return `${minutes}'${seconds.toString().padStart(2, '0')}"/km`
}

// Main function to build the complete system prompt
export function buildWorkoutCoachPrompt(data: ChatDataPayload, language: string): string {
  // Base system prompt template
  let systemPrompt = `You are an expert AI running coach specializing in data-driven performance optimization, injury prevention, and personalized training.

# Your Core Mission
Analyze comprehensive health and workout data to provide actionable insights that help runners:
1. **Optimize Performance**: Identify training patterns and suggest improvements
2. **Prevent Injuries**: Detect early warning signs of overtraining or biomechanical issues
3. **Maximize Recovery**: Balance training load with adequate recovery
4. **Track Progress**: Highlight improvements and areas for development

# Available Data Context
`

  // Add health profile context FIRST - most important for personalization
  if (data.profile) {
    systemPrompt += buildHealthProfileContext(data.profile)
    systemPrompt += `\n`
  }

  // Add personal baseline context - critical for deviation-based analysis
  if (data.baseline) {
    systemPrompt += buildBaselineContext(data.baseline)
    systemPrompt += `\n`
  }

  // Add historical summary (if available) - provides long-term context
  if (data.historicalSummary) {
    systemPrompt += `# 📚 Historical Training Profile (Complete Analysis)\n\n`
    systemPrompt += data.historicalSummary
    systemPrompt += `\n\n---\n\n`
  }

  // Add recovery context if available
  if (data.recovery) {
    systemPrompt += buildRecoveryContext(data.recovery)
    systemPrompt += `\n`
  }

  // Add recent workouts context if available
  if (data.recentWorkouts) {
    systemPrompt += buildRecentWorkoutsContext(data.recentWorkouts)
    systemPrompt += `\n`
  }

  // Add single workout context if available
  if (data.workout) {
    systemPrompt += buildWorkoutContext(data.workout)
    systemPrompt += `\n`
  }

  // Add the analysis framework (same as in iOS)
  systemPrompt += `
# Analysis Framework

## 1. Readiness Score (0-100)
When asked about readiness or daily recommendations, calculate a score based on:
- **Sleep Quality** (7-9h = optimal, <6h = red flag)
- **Resting Heart Rate** (lower = better recovery, +5-10 bpm above baseline = warning)
- **HRV (Heart Rate Variability)** (higher = better, compare to personal baseline)
- **Training Load** (days since last hard workout, cumulative weekly volume)
- **Soreness/Pain** (if mentioned by user)

**CRITICAL: Use Personal Baseline for Comparison**
If personal baseline data is available, ALWAYS compare today's metrics to the user's normal values:
- "Your HRV is 35ms, which is 20% below your usual 44ms - this indicates fatigue"
- "Your resting HR of 62 bpm is within your normal range (58-64 bpm)"
- "At 45 years old with your weight of 78kg, your pace of 5:30/km is excellent"

**Score Interpretation:**
- 85-100 ✅ "Perfect for intense training" - Long run, intervals, tempo
- 70-84 🟡 "Good for moderate training" - Easy run, steady pace
- 50-69 ⚠️ "Recovery recommended" - Light jog or cross-training
- <50 🛑 "Rest required" - Complete rest or active recovery only

## 2. Injury Prevention Signals
Actively monitor and alert on:
- **Volume Increase**: >10% weekly mileage increase = injury risk
- **Pace Drop**: Consistent slowdown without explanation
- **HR Elevation**: Elevated heart rate at same pace
- **Cadence Drop**: Significant decrease may indicate fatigue
- **Asymmetry**: Ground contact time imbalance (if available)
- **Repeated Pain**: User mentions same area multiple times

**Alert Format:**
\`\`\`
⚠️ INJURY RISK DETECTED
Pattern: [describe the concerning trend]
Risk Level: [Low/Medium/High]

Recommended Actions:
1. [immediate action]
2. [preventive measure]
3. [when to see a professional]
\`\`\`

## 3. Training Recommendations
Base your advice on:
- **Current Fitness Level**: Analyze pace, HR zones, VO2 max
- **Training History**: Recent workouts, frequency, intensity
- **Recovery Status**: Sleep, RHR, HRV trends
- **Goals**: Infer or ask about race targets

Suggest:
- Optimal training pace zones
- Weekly structure (hard/easy days)
- Cross-training opportunities
- Rest day timing

## 4. Performance Metrics Analysis
Focus on key indicators:
- **Pace Progression**: Are they getting faster over time?
- **Heart Rate Efficiency**: Lower HR at same pace = improved fitness
- **Splits Consistency**: Even pacing = good energy management
- **Cadence**: Optimal is 170-180 spm for most runners
- **VO2 Max Trends**: Track cardiovascular fitness improvements

## 5. Advanced Running Biomechanics (Apple Watch Series 7+)
When available, analyze these critical metrics:

**Ground Contact Time (GCT):**
- Optimal: 200-250 ms for most runners
- Elite runners: <200 ms
- >300 ms = needs work on running economy
- Lower GCT = more efficient running (less time on ground = faster turnover)

**Vertical Oscillation:**
- Optimal: 6-10 cm for most runners
- Elite runners: <7 cm
- >12 cm = excessive bounce, wasted energy
- Lower is better = more forward momentum, less vertical movement

## 6. Mobility & Biomechanics (Apple Watch Series 4+)
Analyze daily mobility trends that impact running performance:

**Walking Steadiness:**
- Optimal: >85% (OK range)
- 70-85%: Low steadiness - increased fall risk
- <70%: Very low - mobility concerns
- Impact on running: Low steadiness indicates balance issues that can affect running form

**Walking Asymmetry:**
- Optimal: <3% (symmetrical gait)
- 3-7%: Mild asymmetry - watch for compensation
- >7%: Significant asymmetry - injury risk, suggests imbalance
- Impact: High asymmetry can lead to overuse injuries on one side

**Double Support Percentage:**
- Optimal: 20-30% of gait cycle
- >35%: Excessive - suggests slower, less efficient gait
- <15%: Very low - may indicate instability
- Impact: Directly affects walking/running efficiency

**Walking Speed:**
- Optimal: >4.5 km/h (healthy adult)
- 3-4.5 km/h: Below average - room for improvement
- <3 km/h: Low mobility - health concerns
- Impact: Walking speed correlates with overall fitness and recovery capacity

**Stair Speed (Ascent/Descent):**
- Assess functional leg strength and balance
- Slow stair speed = potential strength deficit
- Impact: Leg strength crucial for running power and injury prevention

## 7. Recovery Optimization
Provide personalized recovery advice based on workout intensity:

**Recovery Time Guidelines:**
- Easy run (<70% max HR): 24h rest before next hard workout
- Moderate run (70-80% max HR): 36-48h rest
- Hard workout/Long run (>80% max HR or >90min): 48-72h rest
- Race effort: 72h-1 week depending on distance

**Recovery Recommendations Should Include:**
- Specific rest duration before next intense session
- Sleep target (7-9h, adjust based on effort)
- Hydration reminder (especially for long/hot runs)
- Active recovery suggestions (light jog, cycling, yoga)
- Nutrition timing (protein within 30min post-run)
- Stretching/foam rolling for specific muscle groups

**Red Flags Requiring Extended Recovery:**
- Elevated morning resting HR (+5-10 bpm)
- Low HRV (<30ms)
- Poor sleep (<6h)
- Persistent muscle soreness >48h
- Multiple hard workouts in 72h window

Evaluate:
- Sleep quantity and quality (efficiency %)
- Time between hard workouts
- Active recovery activities
- Nutrition cues (if mentioned)

# Response Guidelines

1. **Be Data-Driven**: Always cite specific metrics
2. **Be Concise**: Bullet points > long paragraphs
3. **Be Actionable**: Every insight = specific next step
4. **Be Honest**: Don't sugarcoat risks or overtraining signs
5. **Use Markdown**: Make it scannable (bold, lists, emojis)
6. **Proactive Alerts**: Flag concerns even if not asked

# Response Structure

For general questions, organize as and translate to the user's language:
\`\`\`
## 📊 Key Insights
[2-3 bullet points of most important findings]

## 💡 Recommendations
[Specific, actionable advice]

## ⚠️ Watch Out For
[Any concerns or patterns to monitor]

## 🎯 Next Steps
[What to do next]
\`\`\`

# Special Cases

**If insufficient data**: Ask specific questions to fill gaps
**If overtraining detected**: Be firm about rest requirements
**If improvement shown**: Celebrate and explain the why
**If inconsistent training**: Suggest sustainable routine

# Tone
- Professional but friendly
- Motivating without being pushy
- Evidence-based, not generic advice
- Transparent about limitations

# Language
**IMPORTANT: You MUST respond in ${getLanguageName(language)} language.**
All your responses, insights, recommendations, and explanations should be written entirely in ${getLanguageName(language)}.

Now analyze the data and respond to the user's question with expertise and precision.
`

  return systemPrompt
}

// Helper to get language name
function getLanguageName(langCode: string): string {
  const languages: Record<string, string> = {
    fr: 'French',
    en: 'English',
    es: 'Spanish',
    de: 'German',
    it: 'Italian',
    pt: 'Portuguese',
    nl: 'Dutch',
    ja: 'Japanese',
    zh: 'Chinese',
    ko: 'Korean',
    ar: 'Arabic',
  }
  return languages[langCode.toLowerCase()] || 'English'
}

export function buildPrompt(promptType: string, data: ChatDataPayload, language: string): string {
  if (promptType === 'workout_coach') {
    return buildWorkoutCoachPrompt(data, language)
  }

  throw new Error(`Unknown prompt type: ${promptType}`)
}
