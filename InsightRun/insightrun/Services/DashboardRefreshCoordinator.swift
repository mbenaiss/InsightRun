import Combine
import Foundation

@MainActor
final class DashboardRefreshCoordinator: ObservableObject {
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private var loadingDate: Date?
    private var completedDate: Date?
    private var completedAt: Date?

    func refresh(for date: Date, force: Bool = false, minimumInterval: TimeInterval = 60,
                 operation: @escaping @MainActor () async -> Void) async {
        if let task, loadingDate == date, !force, !task.isCancelled {
            await task.value
            return
        }
        let id = UUID()
        requestID = id
        task?.cancel()
        await task?.value
        guard requestID == id, !Task.isCancelled else { return }
        if !force, completedDate == date, let completedAt,
           Date().timeIntervalSince(completedAt) < minimumInterval { return }

        loadingDate = date
        let work = Task { await operation() }
        task = work
        await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        guard requestID == id else { return }
        task = nil
        if !work.isCancelled {
            completedDate = date
            completedAt = Date()
        }
    }

    func cancel() { task?.cancel() }
}

#if DEBUG
enum DashboardDiagnostics {
    static func record(_ event: String, date: Date? = nil) {
        guard ProcessInfo.processInfo.arguments.contains("-DASHBOARD_DIAGNOSTICS") else { return }
        let day = date.map { Calendar.current.startOfDay(for: $0).timeIntervalSince1970.description } ?? "none"
        print("DASHBOARD_CALL event=\(event) day=\(day)")
    }
}
#endif
