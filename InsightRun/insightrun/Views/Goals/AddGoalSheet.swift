//
//  AddGoalSheet.swift
//  InsightRun
//
//  Multi-step wizard for creating a race goal or logging a past race
//  Past races: step 1 only (direct save). Future races: step 1 → 2 → 3.
//

import SwiftUI

struct AddGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0

    // Step 1 — Race
    @State private var isPastRace = false
    @State private var raceType: RaceType = .halfMarathon
    @State private var customName = ""
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 4, to: Date()) ?? Date()
    @State private var finishTimeHours = 0
    @State private var finishTimeMinutes = 0
    @State private var finishTimeSeconds = 0
    @State private var raceNotes = ""

    // Step 2 — Training profile
    @State private var fitnessLevel: FitnessLevel = .intermediate
    @State private var trainingDaysPerWeek = 4
    @State private var preferredDays: Set<DayOfWeek> = [.monday, .wednesday, .friday, .saturday]
    @State private var hasInjury = false
    @State private var injuryDescription = ""
    @State private var targetTimeHours = 0
    @State private var targetTimeMinutes = 0

    // History analysis
    @State private var historyAnalyzed = false
    @State private var historyRunCount = 0
    @State private var historyAvgPace: Double? // min/km
    @State private var historyWeeklyKm: Double?

    @FocusState private var isNameFieldFocused: Bool

    let onAdd: (RaceGoal) -> Void

    private var isStep1Valid: Bool {
        isPastRace || targetDate > Date()
    }

    private var finishTimeInterval: TimeInterval? {
        let total = finishTimeHours * 3600 + finishTimeMinutes * 60 + finishTimeSeconds
        return total > 0 ? TimeInterval(total) : nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar (only for future races with multiple steps)
                if !isPastRace {
                    progressIndicator
                        .padding(.top, Spacing.md)
                        .padding(.horizontal, Spacing.xl)
                }

                // Steps content
                Group {
                    switch currentStep {
                    case 1:
                        step2ProfileView
                            .transition(.move(edge: .trailing))
                    case 2:
                        step3RecapView
                            .transition(.move(edge: .trailing))
                    default:
                        step1RaceView
                            .transition(.move(edge: .leading))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: currentStep)
                .onChange(of: currentStep) { _, newStep in
                    if newStep == 1 {
                        Task { await analyzeRunningHistory() }
                    }
                }

                // Bottom action (hidden when keyboard is up)
                bottomBar
                    .padding(Spacing.lg)
                    .opacity(isNameFieldFocused ? 0 : 1)
                    .frame(height: isNameFieldFocused ? 0 : nil)
                    .clipped()
            }
            .background(Color.irBackgroundApp)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if currentStep == 0 {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                    } else {
                        Button {
                            withAnimation { currentStep -= 1 }
                        } label: {
                            HStack(spacing: Spacing.xxs) {
                                Image(systemName: "chevron.left")
                                Text(String(localized: "goals.wizard.back", defaultValue: "Back", comment: "Wizard - back button"))
                            }
                            .foregroundStyle(Color.irPrimaryAccent)
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    if !isPastRace {
                        Text(stepTitle)
                            .font(.headline)
                            .foregroundStyle(Color.irTextPrimary)
                    }
                }
            }
        }
    }

    private var stepTitle: String {
        switch currentStep {
        case 0: return String(localized: "goals.wizard.step1Title", defaultValue: "Race", comment: "Wizard step 1 title")
        case 1: return String(localized: "goals.wizard.step2Title", defaultValue: "Training", comment: "Wizard step 2 title")
        case 2: return String(localized: "goals.wizard.step3Title", defaultValue: "Summary", comment: "Wizard step 3 title")
        default: return ""
        }
    }

    // MARK: - Progress

    private var progressIndicator: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<3, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? AnyShapeStyle(Color.irPrimaryAccent.gradient) : AnyShapeStyle(Color.irBorder.opacity(0.3)))
                    .frame(height: 6)
                    .frame(maxWidth: .infinity)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)
            }
        }
    }

    // MARK: - Step 1: Race

    private var step1RaceView: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                // 1. Name
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(String(localized: "goals.form.details", defaultValue: "Race Name", comment: "Goal form - details label"))
                        .font(.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    HStack {
                        Image(systemName: "pencil.line")
                            .foregroundStyle(Color.irTextSecondary)
                        TextField(
                            String(localized: "goals.form.raceName", defaultValue: "Race Name (optional)", comment: "Goal form - race name placeholder"),
                            text: $customName
                        )
                        .focused($isNameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { isNameFieldFocused = false }
                        .autocorrectionDisabled()

                        if !customName.isEmpty {
                            Button {
                                customName = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.irTextSecondary.opacity(0.5))
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .background(Color.irSurface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(isNameFieldFocused ? Color.irPrimaryAccent.opacity(0.5) : Color.irBorder.opacity(0.5), lineWidth: 1)
                    )
                }

                // 2. Race type
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(String(localized: "goals.form.raceType", defaultValue: "Race Type", comment: "Goal form - race type label"))
                        .font(.headline)
                        .foregroundStyle(Color.irTextPrimary)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: Spacing.md),
                        GridItem(.flexible(), spacing: Spacing.md),
                        GridItem(.flexible(), spacing: Spacing.md)
                    ], spacing: Spacing.md) {
                        ForEach(RaceType.allCases) { type in
                            raceTypeCard(type)
                        }
                    }
                }

                // 3. Past race toggle + extras
                VStack(spacing: Spacing.md) {
                    HStack(spacing: Spacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: Radius.md)
                                .fill(Color.irPrimaryAccent.opacity(0.1))
                                .frame(width: 44, height: 44)
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.irPrimaryAccent.gradient)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "goals.form.pastRace", defaultValue: "Past Race", comment: "Goal form - past race toggle"))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.irTextPrimary)
                            Text(String(localized: "goals.form.pastRaceHint", defaultValue: "Log a completed race", comment: "Goal form - past race hint"))
                                .font(.caption)
                                .foregroundStyle(Color.irTextSecondary)
                        }

                        Spacer()

                        Toggle("", isOn: $isPastRace)
                            .labelsHidden()
                            .tint(Color.irPrimaryAccent)
                    }

                    if isPastRace {
                        VStack(spacing: Spacing.md) {
                            HStack {
                                Image(systemName: "stopwatch")
                                    .foregroundStyle(Color.irPrimaryAccent)
                                Text(String(localized: "goals.form.finishTime", defaultValue: "Finish Time", comment: "Goal form - finish time label"))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                Spacer()
                            }

                            HStack(spacing: 0) {
                                timePickerColumn(value: $finishTimeHours, range: 0..<24, label: "h")
                                timePickerColumn(value: $finishTimeMinutes, range: 0..<60, label: "m")
                                timePickerColumn(value: $finishTimeSeconds, range: 0..<60, label: "s")
                            }
                            .frame(height: 100)
                            .background(Color.irSurface.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))

                            TextField(
                                String(localized: "goals.form.notes", defaultValue: "How did it go? (optional)", comment: "Goal form - notes placeholder"),
                                text: $raceNotes,
                                axis: .vertical
                            )
                            .padding(Spacing.md)
                            .background(Color.irSurface)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .stroke(Color.irBorder.opacity(0.5), lineWidth: 1)
                            )
                            .lineLimit(3)
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .cardStyle(padding: Spacing.md)

                // 4. Date
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(Color.irPrimaryAccent.opacity(0.1))
                            .frame(width: 32, height: 32)
                        Image(systemName: "calendar")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.irPrimaryAccent)
                    }

                    Text(isPastRace
                        ? String(localized: "goals.form.dateSection", defaultValue: "Race Date", comment: "Goal form - date section")
                        : String(localized: "goals.form.targetDateSection", defaultValue: "Target Date", comment: "Goal form - target date section")
                    )
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.irTextPrimary)

                    Spacer()

                    if isPastRace {
                        DatePicker("", selection: $targetDate, in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                    } else {
                        DatePicker("", selection: $targetDate, in: Date()..., displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                .padding(Spacing.sm)
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.base)
            .animation(.easeInOut(duration: 0.3), value: isPastRace)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func timePickerColumn(value: Binding<Int>, range: Range<Int>, label: String) -> some View {
        HStack(spacing: 0) {
            Picker("", selection: value) {
                ForEach(range, id: \.self) { i in
                    Text("\(i)").tag(i)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            
            Text(label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.irTextSecondary)
                .padding(.trailing, Spacing.sm)
        }
    }

    private func raceTypeCard(_ type: RaceType) -> some View {
        let isSelected = raceType == type
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { raceType = type }
        } label: {
            VStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(isSelected ? .white.opacity(0.2) : Color.irPrimaryAccent.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: type.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Color.irPrimaryAccent)
                }

                VStack(spacing: 2) {
                    Text(type.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isSelected ? .white : Color.irTextPrimary)

                    Text(String(format: "%.1f km", type.distanceKm))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : Color.irTextSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(isSelected ? AnyShapeStyle(Color.irPrimaryAccent.gradient) : AnyShapeStyle(Color.irCardBackground))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .shadow(color: isSelected ? Color.irPrimaryAccent.opacity(0.3) : Color.irShadow, radius: isSelected ? 8 : 4, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(isSelected ? Color.clear : Color.irBorder.opacity(0.5), lineWidth: 1)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Training Profile

    private var step2ProfileView: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                // History insight banner
                if historyAnalyzed && historyRunCount > 0 {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.subheadline)
                            .foregroundStyle(Color.irPrimaryAccent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "goals.wizard.historyBanner", defaultValue: "Based on your history", comment: "Wizard - history banner"))
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.irPrimaryAccent)

                            let parts = [
                                "\(historyRunCount) " + String(localized: "goals.wizard.runs", defaultValue: "runs", comment: "Wizard - runs count"),
                                historyAvgPace.map { String(format: "%.0f:%02d/km", floor($0), Int(($0 - floor($0)) * 60)) } ?? nil,
                                historyWeeklyKm.map { String(format: "%.0f km/" , $0) + String(localized: "goals.wizard.perWeek", defaultValue: "week", comment: "Wizard - per week") } ?? nil
                            ].compactMap { $0 }

                            Text(parts.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Color.irTextSecondary)
                        }

                        Spacer()
                    }
                    .padding(Spacing.md)
                    .background(Color.irPrimaryAccent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }

                // Fitness level
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.blue.opacity(0.1))
                                .frame(width: 40, height: 40)
                            Image(systemName: "speedometer")
                                .foregroundStyle(Color.blue.gradient)
                        }

                        Text(String(localized: "goals.form.levelSection", defaultValue: "Your Current Level", comment: "Goal form - level section"))
                            .font(.headline)
                            .foregroundStyle(Color.irTextPrimary)
                    }

                    VStack(spacing: Spacing.sm) {
                        Picker("", selection: $fitnessLevel) {
                            ForEach(FitnessLevel.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(fitnessLevelDescription)
                            .font(.caption)
                            .foregroundStyle(Color.irTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, Spacing.sm)
                    }
                    .padding(Spacing.md)
                    .background(Color.irSurface.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }

                // Target finish time
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.1))
                                .frame(width: 40, height: 40)
                            Image(systemName: "stopwatch")
                                .foregroundStyle(Color.purple.gradient)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text(String(localized: "goals.wizard.targetTime", defaultValue: "Target Time", comment: "Wizard - target time"))
                                .font(.headline)
                                .foregroundStyle(Color.irTextPrimary)
                            Text(String(localized: "goals.wizard.targetTimeHint", defaultValue: "Optional — helps the AI set your paces", comment: "Wizard - target time hint"))
                                .font(.caption)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                    }

                    HStack(spacing: 0) {
                        Picker("", selection: $targetTimeHours) {
                            ForEach(0..<13, id: \.self) { h in Text("\(h)h").tag(h) }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity, maxHeight: 100)
                        .clipped()

                        Picker("", selection: $targetTimeMinutes) {
                            ForEach(0..<60, id: \.self) { m in Text("\(m)m").tag(m) }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity, maxHeight: 100)
                        .clipped()
                    }
                    .background(Color.irSurface.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }

                // Training days
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.1))
                                .frame(width: 40, height: 40)
                            Image(systemName: "calendar.badge.clock")
                                .foregroundStyle(Color.orange.gradient)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text(String(localized: "goals.wizard.trainingDays", defaultValue: "Availability", comment: "Wizard - training days"))
                                .font(.headline)
                            Text(String(localized: "goals.wizard.trainingDaysHint", defaultValue: "Which days can you train?", comment: "Wizard - training days hint"))
                                .font(.caption)
                                .foregroundStyle(Color.irTextSecondary)
                        }
                    }

                    HStack(spacing: Spacing.xs) {
                        ForEach([DayOfWeek.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday], id: \.self) { day in
                            DayToggleButton(day: day, isSelected: preferredDays.contains(day)) {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                                    if preferredDays.contains(day) { preferredDays.remove(day) }
                                    else { preferredDays.insert(day) }
                                    trainingDaysPerWeek = preferredDays.count
                                }
                            }
                        }
                    }
                }

                // Injury / constraint
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.irWarning.opacity(0.1))
                                .frame(width: 40, height: 40)
                            Image(systemName: "bandage")
                                .foregroundStyle(Color.irWarning.gradient)
                        }

                        Text(String(localized: "goals.wizard.injury", defaultValue: "Injuries or Constraints", comment: "Wizard - injury toggle"))
                            .font(.headline)

                        Spacer()

                        Toggle("", isOn: $hasInjury)
                            .labelsHidden()
                            .tint(Color.irPrimaryAccent)
                    }

                    if hasInjury {
                        TextField(
                            String(localized: "goals.wizard.injuryPlaceholder", defaultValue: "e.g. Knee pain, limited time on Tuesdays...", comment: "Wizard - injury placeholder"),
                            text: $injuryDescription,
                            axis: .vertical
                        )
                        .padding(Spacing.md)
                        .background(Color.irSurface)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md)
                                .stroke(Color.irBorder.opacity(0.5), lineWidth: 1)
                        )
                        .lineLimit(2)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.base)
        }
    }

    // MARK: - Step 3: Recap

    private var step3RecapView: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                // Race summary header
                VStack(spacing: Spacing.md) {
                    ZStack {
                        Circle()
                            .fill(Color.irPrimaryAccent.gradient)
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.irPrimaryAccent.opacity(0.3), radius: 10, y: 5)

                        Image(systemName: raceType.icon)
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 4) {
                        Text(customName.isEmpty ? raceType.displayName : customName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.irTextPrimary)

                        Text(raceType.displayName + " • " + String(format: "%.1f km", raceType.distanceKm))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }
                .padding(.vertical, Spacing.md)

                // Details Grid
                VStack(spacing: Spacing.md) {
                    HStack(spacing: Spacing.md) {
                        recapSmallCard(icon: "calendar", label: String(localized: "goals.recap.date", defaultValue: "Date", comment: "Recap - date"), value: targetDate.formatted(date: .abbreviated, time: .omitted))
                        recapSmallCard(icon: "timer", label: String(localized: "goals.recap.remaining", defaultValue: "Remaining", comment: "Recap - remaining"), value: "\(daysUntilRace) " + String(localized: "goals.card.days", defaultValue: "days", comment: ""))
                    }

                    HStack(spacing: Spacing.md) {
                        recapSmallCard(icon: "speedometer", label: String(localized: "goals.recap.level", defaultValue: "Level", comment: "Recap - level"), value: fitnessLevel.displayName)
                        recapSmallCard(icon: "calendar.badge.clock", label: String(localized: "goals.recap.frequency", defaultValue: "Frequency", comment: "Recap - frequency"), value: "\(preferredDays.count)x / " + String(localized: "goals.wizard.perWeek", defaultValue: "week", comment: ""))
                    }

                    if targetTimeHours > 0 || targetTimeMinutes > 0 {
                        HStack(spacing: Spacing.md) {
                            recapSmallCard(icon: "stopwatch", label: String(localized: "goals.wizard.targetTime", defaultValue: "Target Time", comment: "Recap - target time"), value: targetTimeHours > 0 ? "\(targetTimeHours)h\(String(format: "%02d", targetTimeMinutes))" : "\(targetTimeMinutes)min")
                            Spacer()
                        }
                    }
                }

                // Days selection summary
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text(String(localized: "goals.recap.selectedDays", defaultValue: "Selected Training Days", comment: "Recap - selected days"))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.irTextSecondary)
                        .textCase(.uppercase)
                    
                    HStack(spacing: Spacing.xs) {
                        ForEach([DayOfWeek.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday], id: \.self) { day in
                            Text(day.shortName)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(preferredDays.contains(day) ? .white : Color.irTextSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(preferredDays.contains(day) ? Color.irPrimaryAccent.gradient : Color.irSurface.gradient)
                                .clipShape(RoundedRectangle(cornerRadius: Radius.xs))
                        }
                    }
                }
                .padding(Spacing.md)
                .background(Color.irCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .shadow(color: Color.irShadow, radius: 5, y: 2)

                if hasInjury && !injuryDescription.isEmpty {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.irWarning)
                        Text(injuryDescription)
                            .font(.caption)
                            .foregroundStyle(Color.irTextPrimary)
                        Spacer()
                    }
                    .padding()
                    .background(Color.irWarning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.base)
        }
    }

    private func recapSmallCard(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(Color.irPrimaryAccent)
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.irTextSecondary)
                    .textCase(.uppercase)
            }
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(Color.irTextPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .shadow(color: Color.irShadow, radius: 5, y: 2)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        Group {
            if isPastRace {
                primaryButton(
                    title: String(localized: "goals.form.save", defaultValue: "Save", comment: "Save button"),
                    icon: "checkmark"
                ) {
                    saveGoal()
                }
                .disabled(!isStep1Valid)
            } else if currentStep < 2 {
                primaryButton(
                    title: String(localized: "goals.wizard.next", defaultValue: "Next", comment: "Wizard - next button"),
                    icon: "arrow.right"
                ) {
                    withAnimation { currentStep += 1 }
                }
                .disabled(currentStep == 0 && !isStep1Valid)
            } else {
                primaryButton(
                    title: String(localized: "goals.wizard.create", defaultValue: "Create Goal", comment: "Wizard - create button"),
                    icon: "checkmark"
                ) {
                    saveGoal()
                }
            }
        }
    }

    private func primaryButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Text(title)
                Image(systemName: icon)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(Color.irPrimaryAccent.gradient)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .shadow(color: Color.irPrimaryAccent.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }

    // MARK: - Save

    private func saveGoal() {
        let targetTimeSeconds: TimeInterval? = {
            let total = targetTimeHours * 3600 + targetTimeMinutes * 60
            return total > 0 ? TimeInterval(total) : nil
        }()

        let goal = RaceGoal(
            raceType: raceType,
            raceName: customName.isEmpty ? nil : customName,
            targetDate: targetDate,
            fitnessLevel: fitnessLevel,
            isPastRace: isPastRace,
            finishTime: finishTimeInterval,
            notes: raceNotes.isEmpty ? nil : raceNotes,
            trainingDaysPerWeek: trainingDaysPerWeek,
            preferredDays: Array(preferredDays),
            injury: hasInjury && !injuryDescription.isEmpty ? injuryDescription : nil,
            targetTime: targetTimeSeconds
        )
        onAdd(goal)
        dismiss()
    }

    // MARK: - History Analysis

    private func analyzeRunningHistory() async {
        guard !historyAnalyzed else { return }

        do {
            let threeMonthsAgo = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
            let workouts = try await HealthKitManager.shared.fetchRunningWorkouts(from: threeMonthsAgo, to: Date())

            let runs = workouts.filter { $0.distance != nil && $0.distance! > 0 }
            historyRunCount = runs.count

            if !runs.isEmpty {
                // Average pace (min/km)
                let paces = runs.compactMap { w -> Double? in
                    guard let dist = w.distance, dist > 0 else { return nil }
                    return (w.duration / 60.0) / (dist / 1000.0) // min/km
                }
                historyAvgPace = paces.isEmpty ? nil : paces.reduce(0, +) / Double(paces.count)

                // Weekly volume
                let totalKm = runs.compactMap { $0.distance }.reduce(0, +) / 1000.0
                let weeks = max(1, Calendar.current.dateComponents([.weekOfYear], from: threeMonthsAgo, to: Date()).weekOfYear ?? 1)
                historyWeeklyKm = totalKm / Double(weeks)

                // Auto-set fitness level based on history
                let weeklyKm = historyWeeklyKm ?? 0
                let avgPace = historyAvgPace ?? 7.0

                if weeklyKm >= 40 || avgPace < 5.0 || historyRunCount >= 36 {
                    fitnessLevel = .advanced
                } else if weeklyKm >= 15 || avgPace < 6.0 || historyRunCount >= 12 {
                    fitnessLevel = .intermediate
                } else {
                    fitnessLevel = .beginner
                }
            }

            historyAnalyzed = true
        } catch {
            historyAnalyzed = true
        }
    }

    // MARK: - Helpers

    private var daysUntilRace: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 0)
    }

    private var fitnessLevelDescription: String {
        switch fitnessLevel {
        case .beginner:
            return String(localized: "goals.form.levelBeginner", defaultValue: "New to running or less than 6 months of regular training", comment: "Fitness level - beginner")
        case .intermediate:
            return String(localized: "goals.form.levelIntermediate", defaultValue: "1-3 years of regular running, comfortable with 30-60 min runs", comment: "Fitness level - intermediate")
        case .advanced:
            return String(localized: "goals.form.levelAdvanced", defaultValue: "3+ years of structured training, racing experience", comment: "Fitness level - advanced")
        }
    }
}

// MARK: - Day Toggle Button

struct DayToggleButton: View {
    let day: DayOfWeek
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(day.shortName)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(isSelected ? .white : Color.irTextPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(isSelected ? AnyShapeStyle(Color.irPrimaryAccent.gradient) : AnyShapeStyle(Color.irSurface.opacity(0.5)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                .shadow(color: isSelected ? Color.irPrimaryAccent.opacity(0.2) : .clear, radius: 4, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(isSelected ? Color.clear : Color.irBorder.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
