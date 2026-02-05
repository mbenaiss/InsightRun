//
//  SuuntoImportView.swift
//  InsightRun
//
//  View for importing Suunto FIT export files
//

import SwiftUI
import UniformTypeIdentifiers

struct SuuntoImportView: View {
    @StateObject private var importService = SuuntoImportService.shared
    @State private var showFilePicker = false
    @State private var showResult = false
    @State private var importedWorkout: ParsedSuuntoWorkout?
    @State private var errorMessage: String?
    @State private var isMatched = false
    @State private var isSavedToHealthKit = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange)

                    Text(String(localized: "Import Suunto Workout", comment: "Title for Suunto import screen"))
                        .font(.title2.bold())

                    Text(String(localized: "Import a FIT file exported from the Suunto app to enrich your workout data with advanced metrics.", comment: "Description for Suunto import screen"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 40)

                Spacer()

                // Import button
                if importService.isImporting {
                    ProgressView(String(localized: "Importing...", comment: "Loading state during Suunto import"))
                        .padding()
                } else {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label(String(localized: "Select FIT File", comment: "Button to select a FIT file for import"), systemImage: "doc.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.orange)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 32)
                }

                // Instructions
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "How to export from Suunto:", comment: "Instructions header for Suunto export"))
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        instructionRow(number: 1, text: String(localized: "Open Suunto app on your phone", comment: "Suunto export instruction step 1"))
                        instructionRow(number: 2, text: String(localized: "Go to a workout and tap the share icon", comment: "Suunto export instruction step 2"))
                        instructionRow(number: 3, text: String(localized: "Choose \"Export as FIT\"", comment: "Suunto export instruction step 3"))
                        instructionRow(number: 4, text: String(localized: "Save to Files or send to your device", comment: "Suunto export instruction step 4"))
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                Spacer()

                // Stats
                if let count = try? importService.getCachedWorkoutCount(), count > 0 {
                    Text(String(localized: "\(count) Suunto workouts imported", comment: "Count of imported Suunto workouts"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close", comment: "Close button")) {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [UTType(filenameExtension: "fit") ?? .data],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .alert(String(localized: "Import Result", comment: "Alert title for import result"), isPresented: $showResult) {
                Button(String(localized: "OK", comment: "OK button")) {
                    if importedWorkout != nil && errorMessage == nil {
                        dismiss()
                    }
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                } else if let workout = importedWorkout {
                    if isMatched {
                        Text(String(localized: "Workout enriched!\n\n\(workout.activityType)\n\(formattedDistance(workout.distance))\n\(formattedDuration(workout.duration))\n\nSuunto data has been merged with the existing HealthKit workout.", comment: "Success message when workout was enriched"))
                    } else if isSavedToHealthKit {
                        Text(String(localized: "Workout imported and saved to Apple Health!\n\n\(workout.activityType)\n\(formattedDistance(workout.distance))\n\(formattedDuration(workout.duration))", comment: "Success message when workout saved to HealthKit"))
                    } else {
                        Text(String(localized: "Workout imported!\n\n\(workout.activityType)\n\(formattedDistance(workout.distance))\n\(formattedDuration(workout.duration))", comment: "Success message when workout imported"))
                    }
                }
            }
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(.orange.opacity(0.2))
                .foregroundStyle(.orange)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Validate file extension
            guard url.pathExtension.lowercased() == "fit" else {
                errorMessage = String(localized: "Invalid file type. Please select a FIT file.", comment: "Error for invalid file type")
                showResult = true
                return
            }

            // Start accessing the security-scoped resource
            let hasSecurityAccess = url.startAccessingSecurityScopedResource()

            Task {
                // Ensure security scope is released when task completes
                defer {
                    if hasSecurityAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    // Check file size before loading (max 50MB)
                    let maxFileSize: Int64 = 50 * 1024 * 1024
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    if let fileSize = attributes[.size] as? Int64, fileSize > maxFileSize {
                        await MainActor.run {
                            errorMessage = String(localized: "File too large. Maximum size is 50MB.", comment: "Error for file too large")
                            showResult = true
                        }
                        return
                    }

                    let importResult = try await importService.importWorkout(
                        from: url,
                        fileName: url.lastPathComponent
                    )

                    await MainActor.run {
                        switch importResult {
                        case .created(let workout):
                            importedWorkout = workout
                            isMatched = false
                            errorMessage = nil

                        case .createdAndSavedToHealthKit(let workout, _):
                            importedWorkout = workout
                            isMatched = false
                            isSavedToHealthKit = true
                            errorMessage = nil

                        case .enriched(_, let suuntoData):
                            importedWorkout = suuntoData
                            isMatched = true
                            errorMessage = nil

                        case .alreadyExists(let workout):
                            importedWorkout = workout
                            errorMessage = String(localized: "This workout has already been imported.", comment: "Error for duplicate import")
                        }
                        showResult = true
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                        showResult = true
                    }
                }
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
            showResult = true
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        let km = meters / 1000.0
        return String(format: "%.2f %@", km, String(localized: "km", comment: "Kilometer unit abbreviation"))
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%d%@ %02d%@ %02d%@", hours, String(localized: "h", comment: "Hour abbreviation"), minutes, String(localized: "m", comment: "Minute abbreviation"), secs, String(localized: "s", comment: "Second abbreviation"))
        } else {
            return String(format: "%d%@ %02d%@", minutes, String(localized: "m", comment: "Minute abbreviation"), secs, String(localized: "s", comment: "Second abbreviation"))
        }
    }
}

#Preview {
    SuuntoImportView()
}

// MARK: - Import from Share Sheet

struct SuuntoImportFromShareView: View {
    let fileURL: URL?
    let onDismiss: () -> Void

    @StateObject private var importService = SuuntoImportService.shared
    @State private var importState: ImportState = .loading
    @State private var importedWorkout: ParsedSuuntoWorkout?
    @State private var errorMessage: String?
    @State private var isMatched = false
    @State private var isSavedToHealthKit = false

    @Environment(\.dismiss) private var dismiss

    enum ImportState {
        case loading
        case success
        case error
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch importState {
                case .loading:
                    loadingView

                case .success:
                    successView

                case .error:
                    errorView
                }
            }
            .padding()
            .navigationTitle(String(localized: "Import Suunto", comment: "Navigation title for Suunto share import"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close", comment: "Close button")) {
                        onDismiss()
                        dismiss()
                    }
                }
            }
            .task {
                await performImport()
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text(String(localized: "Importing workout...", comment: "Loading state during workout import"))
                .font(.headline)

            if let url = fileURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var successView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text(isMatched ? String(localized: "Workout Enriched!", comment: "Success title when workout enriched") : (isSavedToHealthKit ? String(localized: "Saved to Apple Health!", comment: "Success title when saved to HealthKit") : String(localized: "Workout Imported!", comment: "Success title when workout imported")))
                .font(.title2.bold())

            if let workout = importedWorkout {
                VStack(spacing: 8) {
                    Text(workout.activityType)
                        .font(.headline)

                    HStack(spacing: 16) {
                        Label(formattedDistance(workout.distance), systemImage: "figure.run")
                        Label(formattedDuration(workout.duration), systemImage: "clock")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if isMatched {
                        Text(String(localized: "Suunto data has been merged with the existing HealthKit workout.", comment: "Detail message when workout enriched"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    } else if isSavedToHealthKit {
                        Text(String(localized: "Workout imported and saved to Apple Health!", comment: "Detail message when saved to HealthKit"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
            }

            Button(String(localized: "Done", comment: "Done button")) {
                onDismiss()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
    }

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text(String(localized: "Import Failed", comment: "Error title when import fails"))
                .font(.title2.bold())

            if let error = errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(String(localized: "Close", comment: "Close button")) {
                onDismiss()
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding(.top)
        }
    }

    private func performImport() async {
        guard let url = fileURL else {
            importState = .error
            errorMessage = String(localized: "No file provided", comment: "Error when no file is provided")
            return
        }

        // For shared files, try security-scoped access first, but don't fail if it returns false
        // Files shared via share sheet are copied to app's Inbox and may not need security scope
        let needsSecurityScope = url.startAccessingSecurityScopedResource()

        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            // Try to read the file - it may be directly accessible (Inbox) or security-scoped
            let result = try await importService.importWorkout(
                from: url,
                fileName: url.lastPathComponent
            )

            await MainActor.run {
                switch result {
                case .created(let workout):
                    importedWorkout = workout
                    isMatched = false
                    importState = .success

                case .createdAndSavedToHealthKit(let workout, _):
                    importedWorkout = workout
                    isMatched = false
                    isSavedToHealthKit = true
                    importState = .success

                case .enriched(_, let suuntoData):
                    importedWorkout = suuntoData
                    isMatched = true
                    importState = .success

                case .alreadyExists(let workout):
                    importedWorkout = workout
                    errorMessage = String(localized: "This workout has already been imported.", comment: "Error for duplicate import")
                    importState = .error
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                importState = .error
            }
        }
    }

    private func formattedDistance(_ meters: Double) -> String {
        String(format: "%.2f %@", meters / 1000.0, String(localized: "km", comment: "Kilometer unit abbreviation"))
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return String(format: "%d%@ %02d%@", hours, String(localized: "h", comment: "Hour abbreviation"), minutes, String(localized: "m", comment: "Minute abbreviation"))
        } else {
            return String(format: "%d %@", minutes, String(localized: "min", comment: "Minutes abbreviation"))
        }
    }
}
