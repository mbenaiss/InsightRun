import BackgroundTasks
import UIKit

// The continued processing task (iOS 26+) gives minutes of runtime; the background task covers
// older systems and the moment before the system starts the continued task.
@MainActor
final class BackgroundWorkSession {
    // Apple asks to stop in-flight work when the system or the person ends the continued task.
    var onExpiration: (() -> Void)?
    private(set) var didExpire = false

    private let expectedDuration: TimeInterval
    private let startDate = Date()
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    // Typed as BGTask because stored properties cannot be limited to iOS 26.
    private var continuedTask: BGTask?
    private var progressUpdates: Task<Void, Never>?
    private var reportedProgress = 0.0
    private var outcome: Bool?

    /// `name` must match a `<bundle ID>.<name>.*` entry of `BGTaskSchedulerPermittedIdentifiers`.
    init(name: String, title: String, subtitle: String, expectedDuration: TimeInterval) {
        self.expectedDuration = expectedDuration
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.endBackgroundTask()
        }
        if #available(iOS 26.0, *) {
            submitContinuedTask(name: name, title: title, subtitle: subtitle)
        }
    }

    func report(progress: Double) {
        reportedProgress = max(reportedProgress, min(max(progress, 0), 1))
        if #available(iOS 26.0, *) { reportElapsedProgress() }
    }

    func end(success: Bool) {
        guard outcome == nil else { return }
        outcome = success
        completeContinuedTask(success: success)
        endBackgroundTask()
    }

    @available(iOS 26.0, *)
    private func submitContinuedTask(name: String, title: String, subtitle: String) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        // The scheduler refuses a single wildcard handler: each request registers its own identifier.
        let identifier = "\(bundleID).\(name).\(UUID().uuidString)"
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) {
            [weak self] task in
            MainActor.assumeIsolated {
                guard let self else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.attach(task)
            }
        }
        guard registered else { return }

        // The iOS 27 SDK replaces the synchronous submit, which misses some errors, and asks to call
        // its successor off the main thread. Older compilers lack the new API.
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            Task.detached {
                let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
                request.strategy = .fail
                do {
                    try await BGTaskScheduler.shared.submitTaskRequest(request)
                } catch {
                    print("⚠️ BackgroundWorkSession: continued processing unavailable: \(error)")
                }
            }
            return
        }
        #endif
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: subtitle)
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("⚠️ BackgroundWorkSession: continued processing unavailable: \(error)")
        }
    }

    @available(iOS 26.0, *)
    private func attach(_ task: BGTask) {
        guard outcome == nil, let task = task as? BGContinuedProcessingTask else {
            task.setTaskCompleted(success: outcome ?? false)
            return
        }
        continuedTask = task
        task.expirationHandler = { [weak self] in
            Task { @MainActor in self?.expire() }
        }
        task.progress.totalUnitCount = 100
        progressUpdates = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.reportElapsedProgress()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func expire() {
        guard outcome == nil else { return }
        didExpire = true
        completeContinuedTask(success: false)
        onExpiration?()
    }

    // The system expires tasks that look stalled: between real progress steps the bar follows the
    // elapsed time and flattens out instead of reaching the end before the work does.
    @available(iOS 26.0, *)
    private func reportElapsedProgress() {
        guard let task = continuedTask as? BGContinuedProcessingTask else { return }
        let elapsed = 1 - exp(-Date().timeIntervalSince(startDate) / expectedDuration)
        task.progress.completedUnitCount = min(95, Int64(max(elapsed, reportedProgress) * 100))
    }

    private func completeContinuedTask(success: Bool) {
        progressUpdates?.cancel()
        progressUpdates = nil
        guard let task = continuedTask else { return }
        continuedTask = nil
        if success, #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = task.progress.totalUnitCount
        }
        task.setTaskCompleted(success: success)
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
