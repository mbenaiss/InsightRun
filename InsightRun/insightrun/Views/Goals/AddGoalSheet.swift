//
//  AddGoalSheet.swift
//  InsightRun
//
//  Multi-step wizard for creating a race goal — V4 visual language.
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
    @State private var planStartDate = Calendar.current.startOfDay(for: Date())

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

    private var totalSteps: Int { isPastRace ? 1 : 3 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom V4 header (replaces toolbar — design spec)
                createHeader
                    .padding(.horizontal, Spacing.base)
                    .padding(.top, Spacing.sm)

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
                .onChange(of: targetDate) { _, _ in
                    if planStartDate > maxPlanStartDate {
                        planStartDate = maxPlanStartDate
                    }
                }

                bottomBar
                    .padding(.horizontal, Spacing.base)
                    .padding(.bottom, Spacing.base)
                    .opacity(isNameFieldFocused ? 0 : 1)
                    .frame(height: isNameFieldFocused ? 0 : nil)
                    .clipped()
            }
            .background(Color.irBackgroundApp)
            .navigationBarHidden(true)
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

    // MARK: - V4 CreateHeader

    private var createHeader: some View {
        VStack(spacing: 0) {
            HStack {
                if currentStep > 0 {
                    Button {
                        withAnimation { currentStep -= 1 }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .heavy))
                            Text(String(localized: "goals.wizard.back", defaultValue: "Back", comment: "Wizard - back button"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.irTextPrimary)
                        .padding(.leading, 8)
                        .padding(.trailing, 12)
                        .padding(.vertical, 6)
                        .background(Color.irSurface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.irBorder, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        dismiss()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.irSurface)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle().strokeBorder(Color.irBorder, lineWidth: 0.5)
                                )
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Color.irTextPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text(stepTitle)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.irTextPrimary)

                Spacer()

                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.top, 4)

            // Progress segments
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < currentStep + 1 ? Color.irPrimaryAccent : Color.white.opacity(0.10))
                        .frame(height: 4)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Step 1: Race

    private var step1RaceView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                step1DetailsSection
                step1RaceTypeSection
                step1PastRaceCard
                step1TargetDateCard

                if isPastRace {
                    step1PastRaceExtras
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.base)
            .animation(.easeInOut(duration: 0.3), value: isPastRace)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var step1DetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "goals.form.details", defaultValue: "Details", comment: "Goal form - details label"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.irTextPrimary)

            HStack(spacing: 8) {
                Image(systemName: "pencil.line")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                TextField(
                    String(localized: "goals.form.raceName", defaultValue: "Race Name (optional)", comment: "Goal form - race name placeholder"),
                    text: $customName
                )
                .focused($isNameFieldFocused)
                .submitLabel(.done)
                .onSubmit { isNameFieldFocused = false }
                .autocorrectionDisabled()
                .font(.system(size: 14))
                .foregroundStyle(Color.irTextPrimary)

                if !customName.isEmpty {
                    Button {
                        customName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.irTextSecondary.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
            )
        }
    }

    private var step1RaceTypeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "goals.form.raceType", defaultValue: "Race Type", comment: "Goal form - race type label"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.irTextPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(RaceType.allCases) { type in
                    raceTypeTile(type)
                }
            }
        }
    }

    private var step1PastRaceCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.irPrimaryAccent.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.irPrimaryAccent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "goals.form.pastRace", defaultValue: "Past Race", comment: "Goal form - past race toggle"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.irTextPrimary)
                Text(String(localized: "goals.form.pastRaceHint", defaultValue: "Log a completed race to build your history.", comment: "Goal form - past race hint"))
                    .font(.system(size: 11))
                    .lineSpacing(1)
                    .foregroundStyle(Color.irTextSecondary)
            }

            Spacer(minLength: 8)

            v4Toggle(isOn: $isPastRace)
        }
        .padding(14)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var step1TargetDateCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.irPrimaryAccent.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: "calendar")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.irPrimaryAccent)
            }

            Text(isPastRace
                ? String(localized: "goals.form.dateSection", defaultValue: "Race Date", comment: "Goal form - date section")
                : String(localized: "goals.form.targetDateSection", defaultValue: "Target Date", comment: "Goal form - target date section")
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.irTextPrimary)

            Spacer()

            // Date pill — DatePicker overlay with custom mono label
            ZStack {
                Text(targetDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.irTextPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.irSurface)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.irBorder, lineWidth: 0.5))

                if isPastRace {
                    DatePicker("", selection: $targetDate, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .blendMode(.destinationOver)
                } else {
                    DatePicker("", selection: $targetDate, in: Date()..., displayedComponents: .date)
                        .labelsHidden()
                        .blendMode(.destinationOver)
                }
            }
        }
        .padding(14)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var step1PastRaceExtras: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Finish time
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "stopwatch")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.irPrimaryAccent)
                    Text(String(localized: "goals.form.finishTime", defaultValue: "Finish Time", comment: "Goal form - finish time label"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.irTextPrimary)
                }

                HStack(spacing: 0) {
                    timePickerColumn(value: $finishTimeHours, range: 0..<24, label: "h")
                    Rectangle().fill(Color.irBorder).frame(width: 1)
                    timePickerColumn(value: $finishTimeMinutes, range: 0..<60, label: "m")
                    Rectangle().fill(Color.irBorder).frame(width: 1)
                    timePickerColumn(value: $finishTimeSeconds, range: 0..<60, label: "s")
                }
                .frame(height: 110)
                .background(Color.irSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.irBorder, lineWidth: 0.5)
                )
            }

            // Notes
            TextField(
                String(localized: "goals.form.notes", defaultValue: "How did it go? (optional)", comment: "Goal form - notes placeholder"),
                text: $raceNotes,
                axis: .vertical
            )
            .padding(12)
            .background(Color.irSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.irBorder, lineWidth: 0.5)
            )
            .lineLimit(3)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.irTextSecondary)
                .padding(.trailing, 8)
        }
    }

    // V4 TypeTile
    private func raceTypeTile(_ type: RaceType) -> some View {
        let isSelected = raceType == type
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { raceType = type }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected
                              ? AnyShapeStyle(Color.white.opacity(0.25))
                              : AnyShapeStyle(Color.irPrimaryAccent.opacity(0.16)))
                        .frame(width: 32, height: 32)

                    Image(systemName: typeTileIcon(type))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(isSelected ? Color.black : Color.irPrimaryAccent)
                }

                Text(type.displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isSelected ? .black : Color.irTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(String(format: "%.1f km", type.distanceKm))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.6) : Color.irTextSecondary.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .padding(.horizontal, 8)
            .background(isSelected ? AnyShapeStyle(Color.irPrimaryAccent) : AnyShapeStyle(Color.irCardBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? Color.irPrimaryAccent : Color.irBorder,
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: isSelected ? Color.irPrimaryAccent.opacity(0.30) : .clear,
                radius: isSelected ? 8 : 0,
                y: 4
            )
        }
        .buttonStyle(.plain)
    }

    private func typeTileIcon(_ type: RaceType) -> String {
        switch type {
        case .fiveK: return "figure.run"
        case .tenK: return "scope"
        case .halfMarathon: return "bolt.fill"
        case .marathon: return "trophy"
        case .ultra: return "mountain.2.fill"
        }
    }

    // V4 Toggle (44x26)
    private func v4Toggle(isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { isOn.wrappedValue.toggle() }
        } label: {
            ZStack(alignment: isOn.wrappedValue ? .trailing : .leading) {
                Capsule()
                    .fill(isOn.wrappedValue ? Color.irPrimaryAccent : Color.white.opacity(0.10))
                    .frame(width: 44, height: 26)
                    .overlay(Capsule().strokeBorder(Color.irBorder, lineWidth: 0.5))

                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .padding(.horizontal, 2)
            }
            .frame(width: 44, height: 26)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Training Profile

    private var step2ProfileView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if historyAnalyzed && historyRunCount > 0 {
                    step2HistoryBanner
                }
                step2LevelField
                step2TargetTimeField
                step2PlanStartField
                step2DaysField
                step2InjuryField
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.base)
        }
    }

    private var step2HistoryBanner: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.irPrimaryAccent.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.irPrimaryAccent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "goals.wizard.historyBanner", defaultValue: "Based on your history", comment: "Wizard - history banner"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.irPrimaryAccent)

                let parts: [String] = [
                    "\(historyRunCount) " + String(localized: "goals.wizard.runs", defaultValue: "runs", comment: "Wizard - runs count"),
                    historyAvgPace.map { String(format: "%.0f:%02d/km", floor($0), Int(($0 - floor($0)) * 60)) },
                    historyWeeklyKm.map { String(format: "%.0f km/", $0) + String(localized: "goals.wizard.perWeek", defaultValue: "week", comment: "Wizard - per week") }
                ].compactMap { $0 }

                Text(parts.joined(separator: " · "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.irTextSecondary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.irPrimaryAccent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var step2LevelField: some View {
        wizardField(
            icon: "speedometer",
            iconColor: Color.irPrimaryAccent,
            title: String(localized: "goals.form.levelSection", defaultValue: "Your Current Level", comment: "Goal form - level section"),
            subtitle: nil
        ) {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(FitnessLevel.allCases, id: \.self) { level in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { fitnessLevel = level }
                        } label: {
                            Text(level.displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(fitnessLevel == level ? Color.irTextPrimary : Color.irTextSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(fitnessLevel == level ? Color.white.opacity(0.08) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.irSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.irBorder, lineWidth: 0.5))

                Text(fitnessLevelDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
        }
    }

    private var step2TargetTimeField: some View {
        wizardField(
            icon: "clock",
            iconColor: Color.purple,
            title: String(localized: "goals.wizard.targetTime", defaultValue: "Target Time", comment: "Wizard - target time"),
            subtitle: String(localized: "goals.wizard.targetTimeHint", defaultValue: "Optional — helps the AI set your paces", comment: "Wizard - target time hint")
        ) {
            HStack(spacing: 0) {
                Picker("", selection: $targetTimeHours) {
                    ForEach(0..<13, id: \.self) { h in
                        Text("\(h)h").tag(h)
                            .font(.system(.body, design: .rounded))
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity, maxHeight: 110)
                .clipped()

                Rectangle()
                    .fill(Color.irBorder)
                    .frame(width: 1)

                Picker("", selection: $targetTimeMinutes) {
                    ForEach(0..<60, id: \.self) { m in
                        Text("\(m)m").tag(m)
                            .font(.system(.body, design: .rounded))
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity, maxHeight: 110)
                .clipped()
            }
            .padding(10)
            .background(Color.irSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.irBorder, lineWidth: 0.5))
        }
    }

    private var step2PlanStartField: some View {
        wizardField(
            icon: "calendar",
            iconColor: Color.irSuccess,
            title: String(localized: "goals.wizard.planStart", defaultValue: "Plan Start Date", comment: "Wizard - plan start date"),
            subtitle: nil,
            inline: true
        ) {
            ZStack {
                Text(planStartDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.irTextPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.irSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.irBorder, lineWidth: 0.5))

                DatePicker(
                    "",
                    selection: $planStartDate,
                    in: Calendar.current.startOfDay(for: Date())...maxPlanStartDate,
                    displayedComponents: .date
                )
                .labelsHidden()
                .blendMode(.destinationOver)
            }
        }
    }

    private var step2DaysField: some View {
        wizardField(
            icon: "calendar.badge.clock",
            iconColor: Color.irWarning,
            title: String(localized: "goals.wizard.trainingDays", defaultValue: "Training Days", comment: "Wizard - training days"),
            subtitle: String(localized: "goals.wizard.trainingDaysHint", defaultValue: "Tap the days you want to train", comment: "Wizard - training days hint")
        ) {
            HStack(spacing: 6) {
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
    }

    private var step2InjuryField: some View {
        VStack(alignment: .leading, spacing: 10) {
            wizardField(
                icon: "bandage",
                iconColor: Color.irWarning,
                title: String(localized: "goals.wizard.injury", defaultValue: "Injuries or Constraints", comment: "Wizard - injury toggle"),
                subtitle: nil,
                inline: true
            ) {
                v4Toggle(isOn: $hasInjury)
            }

            if hasInjury {
                TextField(
                    String(localized: "goals.wizard.injuryPlaceholder", defaultValue: "e.g. Knee pain, limited time on Tuesdays...", comment: "Wizard - injury placeholder"),
                    text: $injuryDescription,
                    axis: .vertical
                )
                .padding(12)
                .background(Color.irSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.irBorder, lineWidth: 0.5)
                )
                .lineLimit(2)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // V4 wizard field — icon pill + title/subtitle + content
    // `inline` puts the trailing content on the same row as the header (Plan Start, Injury Toggle).
    private func wizardField<Content: View>(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String?,
        inline: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: inline ? 0 : 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.16))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.irTextPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.irTextSecondary)
                    }
                }

                Spacer()

                if inline {
                    content()
                }
            }

            if !inline {
                content()
            }
        }
    }

    // MARK: - Step 3: Recap

    private var step3RecapView: some View {
        ScrollView {
            VStack(spacing: 18) {
                step3Hero
                step3RecapGrid
                step3PlanStartCard
                step3DaysSection
                if targetTimeHours > 0 || targetTimeMinutes > 0 {
                    step3TargetTimeCard
                }
                if hasInjury && !injuryDescription.isEmpty {
                    step3InjuryNote
                }
            }
            .padding(.horizontal, Spacing.base)
            .padding(.vertical, Spacing.base)
        }
    }

    private var step3Hero: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.irPrimaryAccent)
                    .frame(width: 76, height: 76)
                    .shadow(color: Color.irPrimaryAccent.opacity(0.35), radius: 20, y: 12)

                Image(systemName: "figure.run")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(Color.black)
            }

            Text(customName.isEmpty ? raceType.displayName : customName)
                .font(.system(size: 26, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(Color.irTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Text("\(raceType.displayName) · \(String(format: "%.1f km", raceType.distanceKm))")
                .font(.system(size: 13))
                .foregroundStyle(Color.irTextSecondary)
                .padding(.top, 4)
        }
        .padding(.top, 18)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

    private var step3RecapGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 8) {
            recapCell(
                icon: "calendar",
                label: String(localized: "goals.recap.date", defaultValue: "Date", comment: "Recap - date"),
                value: targetDate.formatted(date: .abbreviated, time: .omitted),
                color: Color.irPrimaryAccent,
                monospaced: false
            )
            recapCell(
                icon: "clock",
                label: String(localized: "goals.recap.remaining", defaultValue: "Remaining", comment: "Recap - remaining"),
                value: "\(daysUntilRace) " + String(localized: "goals.card.days", defaultValue: "days", comment: ""),
                color: Color.purple,
                monospaced: true
            )
            recapCell(
                icon: "speedometer",
                label: String(localized: "goals.recap.level", defaultValue: "Level", comment: "Recap - level"),
                value: fitnessLevel.displayName,
                color: Color.irWarning,
                monospaced: false
            )
            recapCell(
                icon: "figure.run",
                label: String(localized: "goals.recap.frequency", defaultValue: "Frequency", comment: "Recap - frequency"),
                value: "\(preferredDays.count)× / " + String(localized: "goals.wizard.perWeek", defaultValue: "week", comment: ""),
                color: Color.irSuccess,
                monospaced: false
            )
        }
    }

    private var step3PlanStartCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.irPrimaryAccent.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: "calendar")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.irPrimaryAccent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "goals.recap.planStart", defaultValue: "Plan Start", comment: "Recap - plan start"))
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                    .textCase(.uppercase)
                Text(planStartDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.irTextPrimary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var step3DaysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "goals.recap.selectedDays", defaultValue: "Selected Training Days", comment: "Recap - selected days"))
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            HStack(spacing: 6) {
                ForEach([DayOfWeek.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday], id: \.self) { day in
                    let isSelected = preferredDays.contains(day)
                    Text(dayPillLabel(day))
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(isSelected ? .black : Color.irTextSecondary.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isSelected ? Color.irPrimaryAccent : Color.irSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(10)
            .background(Color.irCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.irBorder, lineWidth: 0.5)
            )
        }
    }

    private var step3TargetTimeCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.purple.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: "stopwatch")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "goals.wizard.targetTime", defaultValue: "Target Time", comment: "Recap - target time"))
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                    .textCase(.uppercase)
                Text(targetTimeHours > 0 ? "\(targetTimeHours)h\(String(format: "%02d", targetTimeMinutes))" : "\(targetTimeMinutes)min")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.irTextPrimary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    private var step3InjuryNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.irWarning)
            Text(injuryDescription)
                .font(.system(size: 12))
                .lineSpacing(2)
                .foregroundStyle(Color.irTextPrimary)
            Spacer()
        }
        .padding(14)
        .background(Color.irWarning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irWarning.opacity(0.25), lineWidth: 0.5)
        )
    }

    // V4 RecapCell
    private func recapCell(icon: String, label: String, value: String, color: Color, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 24, height: 24, alignment: .leading)
                .padding(.bottom, 8)

            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .tracking(1.4)
                .foregroundStyle(Color.irTextSecondary.opacity(0.6))
                .textCase(.uppercase)
                .padding(.bottom, 4)

            Text(value)
                .font(.system(size: 15, weight: .bold, design: monospaced ? .monospaced : .rounded))
                .tracking(-0.15)
                .foregroundStyle(Color.irTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.irCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.irBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        Group {
            if isPastRace {
                nextButton(
                    title: String(localized: "goals.form.save", defaultValue: "Save", comment: "Save button")
                ) {
                    saveGoal()
                }
                .disabled(!isStep1Valid)
            } else if currentStep < 2 {
                nextButton(
                    title: String(localized: "goals.wizard.next", defaultValue: "Next", comment: "Wizard - next button")
                ) {
                    withAnimation { currentStep += 1 }
                }
                .disabled(currentStep == 0 && !isStep1Valid)
            } else {
                nextButton(
                    title: String(localized: "goals.wizard.create", defaultValue: "Create Goal ✓", comment: "Wizard - create button")
                ) {
                    saveGoal()
                }
            }
        }
    }

    // V4 NextBtn
    private func nextButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(Color.irPrimaryAccent)
                .clipShape(Capsule())
                .shadow(color: Color.irPrimaryAccent.opacity(0.35), radius: 12, y: 8)
        }
        .padding(.top, 6)
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
            targetTime: targetTimeSeconds,
            planStartDate: isPastRace ? nil : planStartDate
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
                let paces = runs.compactMap { w -> Double? in
                    guard let dist = w.distance, dist > 0 else { return nil }
                    return (w.duration / 60.0) / (dist / 1000.0)
                }
                historyAvgPace = paces.isEmpty ? nil : paces.reduce(0, +) / Double(paces.count)

                let totalKm = runs.compactMap { $0.distance }.reduce(0, +) / 1000.0
                let weeks = max(1, Calendar.current.dateComponents([.weekOfYear], from: threeMonthsAgo, to: Date()).weekOfYear ?? 1)
                historyWeeklyKm = totalKm / Double(weeks)

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

    /// Latest allowed plan start date = race date - 4 weeks (backend minimum).
    /// Falls back to today if the race is closer than 4 weeks (defensive — step 1 validates `> now`).
    private var maxPlanStartDate: Date {
        let today = Calendar.current.startOfDay(for: Date())
        let latest = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: targetDate) ?? today
        return max(today, Calendar.current.startOfDay(for: latest))
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

// MARK: - Day pill label helper

/// Normalize the locale's short weekday symbol so the pill always reads
/// as 3 lowercased letters + a single trailing period — `lun.` / `mon.`
/// (the locale's `shortWeekdaySymbols` already include a period in French,
/// which produced `lun..` when we appended one).
fileprivate func dayPillLabel(_ day: DayOfWeek) -> String {
    let base = day.shortName.replacingOccurrences(of: ".", with: "")
    return base.lowercased() + "."
}

// MARK: - Day Toggle Button (V4)

struct DayToggleButton: View {
    let day: DayOfWeek
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(dayPillLabel(day))
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(isSelected ? .black : Color.irTextSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Color.irPrimaryAccent : Color.irSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected ? Color.clear : Color.irBorder,
                            lineWidth: 0.5
                        )
                )
        }
        .buttonStyle(.plain)
    }
}
