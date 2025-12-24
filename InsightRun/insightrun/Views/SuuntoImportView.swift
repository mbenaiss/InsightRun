//
//  SuuntoImportView.swift
//  InsightRun
//
//  View for importing Suunto JSON export files
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

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.orange)

                    Text("Import Suunto Workout")
                        .font(.title2.bold())

                    Text("Import a JSON file exported from the Suunto app to enrich your workout data with advanced metrics.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 40)

                Spacer()

                // Import button
                if importService.isImporting {
                    ProgressView("Importing...")
                        .padding()
                } else {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Select JSON File", systemImage: "doc.badge.plus")
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
                    Text("How to export from Suunto:")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        instructionRow(number: 1, text: "Open Suunto app on your phone")
                        instructionRow(number: 2, text: "Go to a workout and tap the share icon")
                        instructionRow(number: 3, text: "Choose \"Export as JSON\"")
                        instructionRow(number: 4, text: "Save to Files or send to your device")
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                Spacer()

                // Stats
                if let count = try? importService.getCachedWorkoutCount(), count > 0 {
                    Text("\(count) Suunto workouts imported")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .alert("Import Result", isPresented: $showResult) {
                Button("OK") {
                    if importedWorkout != nil && errorMessage == nil {
                        dismiss()
                    }
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                } else if let workout = importedWorkout {
                    if isMatched {
                        Text("Workout enriched!\n\n\(workout.activityType)\n\(formattedDistance(workout.distance))\n\(formattedDuration(workout.duration))\n\nSuunto data has been merged with the existing HealthKit workout.")
                    } else {
                        Text("Workout imported!\n\n\(workout.activityType)\n\(formattedDistance(workout.distance))\n\(formattedDuration(workout.duration))")
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
            guard url.pathExtension.lowercased() == "json" else {
                errorMessage = "Invalid file type. Please select a JSON file."
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
                            errorMessage = "File too large. Maximum size is 50MB."
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

                        case .enriched(_, let suuntoData):
                            importedWorkout = suuntoData
                            isMatched = true
                            errorMessage = nil

                        case .alreadyExists(let workout):
                            importedWorkout = workout
                            errorMessage = "This workout has already been imported."
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
        return String(format: "%.2f km", km)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60

        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, secs)
        } else {
            return String(format: "%dm %02ds", minutes, secs)
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
            .navigationTitle("Import Suunto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
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

            Text("Importing workout...")
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

            Text(isMatched ? "Workout Enriched!" : "Workout Imported!")
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
                        Text("Suunto data has been merged with the existing HealthKit workout.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
            }

            Button("Done") {
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

            Text("Import Failed")
                .font(.title2.bold())

            if let error = errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Close") {
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
            errorMessage = "No file provided"
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

                case .enriched(_, let suuntoData):
                    importedWorkout = suuntoData
                    isMatched = true
                    importState = .success

                case .alreadyExists(let workout):
                    importedWorkout = workout
                    errorMessage = "This workout has already been imported."
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
        String(format: "%.2f km", meters / 1000.0)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        } else {
            return String(format: "%d min", minutes)
        }
    }
}
