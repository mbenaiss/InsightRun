import SwiftUI

extension View {
    func workoutExportDestinationDialog(
        isPresented: Binding<Bool>,
        onSelect: @escaping (WorkoutExportDestination) -> Void
    ) -> some View {
        confirmationDialog(
            String(localized: "workout.export.destination", defaultValue: "Choose your run type", comment: "Running export destination dialog title"),
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            ForEach(WorkoutExportDestination.allCases) { destination in
                Button(destination.displayName) { onSelect(destination) }
                    .accessibilityIdentifier("export-destination-\(destination.rawValue)")
            }
            Button(String(localized: "Cancel", comment: "Cancel workout export"), role: .cancel) {}
        }
    }
}
