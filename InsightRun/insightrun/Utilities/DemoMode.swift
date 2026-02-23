//
//  DemoMode.swift
//  InsightRun
//
//  Demo mode detection via launch arguments
//

import Foundation

enum DemoMode {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-DEMO_MODE")
    }
}
