//
//  CrashReportingService.swift
//  InsightRun
//
//  Forwards MetricKit crash, hang and exit diagnostics to PostHog so that
//  silent terminations (crashes, jetsam, watchdog) become visible in analytics.
//

import Foundation
import MetricKit

// nonisolated: MetricKit invokes the subscriber on a background queue, and the
// project defaults to MainActor isolation.
nonisolated final class CrashReportingService: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReportingService()

    private static let maxCallStackBytes = 6_000

    private override init() {
        super.init()
    }

    /// Call once at app launch. MetricKit delivers diagnostics from previous
    /// runs shortly after the subscriber is registered.
    func start() {
        MXMetricManager.shared.add(self)
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                var properties: [String: Any] = [
                    "diagnostic_app_build": crash.metaData.applicationBuildVersion,
                    "diagnostic_os_version": crash.metaData.osVersion,
                    "diagnostic_device_type": crash.metaData.deviceType,
                    "period_start": Self.iso8601(payload.timeStampBegin),
                    "period_end": Self.iso8601(payload.timeStampEnd),
                    "call_stack": Self.truncatedCallStack(crash.callStackTree),
                ]
                if let reason = crash.terminationReason {
                    properties["termination_reason"] = reason
                }
                if let region = crash.virtualMemoryRegionInfo {
                    properties["virtual_memory_region"] = region
                }
                if let type = crash.exceptionType {
                    properties["exception_type"] = type.intValue
                }
                if let code = crash.exceptionCode {
                    properties["exception_code"] = code.intValue
                }
                if let signal = crash.signal {
                    properties["signal"] = signal.intValue
                }
                if #available(iOS 17.0, *), let reason = crash.exceptionReason {
                    properties["exception_reason"] = reason.composedMessage
                }
                Task { @MainActor in
                    AnalyticsService.shared.trackAppCrashDetected(properties: properties)
                }
            }

            for hang in payload.hangDiagnostics ?? [] {
                let properties: [String: Any] = [
                    "diagnostic_app_build": hang.metaData.applicationBuildVersion,
                    "diagnostic_os_version": hang.metaData.osVersion,
                    "hang_duration_ms": Int(hang.hangDuration.converted(to: .milliseconds).value),
                    "period_start": Self.iso8601(payload.timeStampBegin),
                    "period_end": Self.iso8601(payload.timeStampEnd),
                    "call_stack": Self.truncatedCallStack(hang.callStackTree),
                ]
                Task { @MainActor in
                    AnalyticsService.shared.trackAppHangDetected(properties: properties)
                }
            }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            guard let exits = payload.applicationExitMetrics else { continue }

            let foreground = exits.foregroundExitData
            let background = exits.backgroundExitData
            var properties: [String: Any] = [
                "period_start": Self.iso8601(payload.timeStampBegin),
                "period_end": Self.iso8601(payload.timeStampEnd),
                "fg_normal_exits": foreground.cumulativeNormalAppExitCount,
                "fg_memory_limit_exits": foreground.cumulativeMemoryResourceLimitExitCount,
                "fg_bad_access_exits": foreground.cumulativeBadAccessExitCount,
                "fg_abnormal_exits": foreground.cumulativeAbnormalExitCount,
                "fg_illegal_instruction_exits": foreground.cumulativeIllegalInstructionExitCount,
                "fg_watchdog_exits": foreground.cumulativeAppWatchdogExitCount,
                "bg_memory_limit_exits": background.cumulativeMemoryResourceLimitExitCount,
                "bg_memory_pressure_exits": background.cumulativeMemoryPressureExitCount,
                "bg_abnormal_exits": background.cumulativeAbnormalExitCount,
                "bg_watchdog_exits": background.cumulativeAppWatchdogExitCount,
            ]
            if let memory = payload.memoryMetrics {
                properties["peak_memory_mb"] = Int(memory.peakMemoryUsage.converted(to: .megabytes).value)
            }

            let abnormalForegroundExits = foreground.cumulativeMemoryResourceLimitExitCount
                + foreground.cumulativeBadAccessExitCount
                + foreground.cumulativeAbnormalExitCount
                + foreground.cumulativeIllegalInstructionExitCount
                + foreground.cumulativeAppWatchdogExitCount
            properties["fg_abnormal_exits_total"] = abnormalForegroundExits

            // Daily payloads with only normal exits are noise; keep the ones that matter.
            guard abnormalForegroundExits > 0 else { continue }

            Task { @MainActor in
                AnalyticsService.shared.trackAppExitMetrics(properties: properties)
            }
        }
    }

    // MARK: - Helpers

    private static func truncatedCallStack(_ tree: MXCallStackTree) -> String {
        let data = tree.jsonRepresentation()
        let bytes = data.prefix(maxCallStackBytes)
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

/// Current resident memory footprint of the process, in megabytes.
/// Uses the same figure Xcode's memory gauge and jetsam rely on (phys_footprint).
nonisolated enum MemoryFootprint {
    static func currentMB() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.phys_footprint / 1_048_576)
    }
}
