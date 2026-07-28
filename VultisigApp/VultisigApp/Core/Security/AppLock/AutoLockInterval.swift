//
//  AutoLockInterval.swift
//  VultisigApp
//

import Foundation

/// How long the app may sit in the background before it re-locks.
///
/// The options match the desktop client so the two behave the same. `fiveMinutes`
/// is the default because it is the value the app hardcoded before this was
/// configurable — upgrading changes nothing until the user picks something else.
enum AutoLockInterval: Int, CaseIterable, Identifiable {
    case immediate = 0
    case oneMinute = 1
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30

    static let `default`: AutoLockInterval = .fiveMinutes

    var id: Int { rawValue }

    var duration: TimeInterval {
        TimeInterval(rawValue) * 60
    }

    /// Localization key for the row label.
    var titleKey: String {
        switch self {
        case .immediate:
            return "autoLockImmediately"
        case .oneMinute:
            return "autoLockOneMinute"
        case .fiveMinutes:
            return "autoLockFiveMinutes"
        case .tenMinutes:
            return "autoLockTenMinutes"
        case .fifteenMinutes:
            return "autoLockFifteenMinutes"
        case .thirtyMinutes:
            return "autoLockThirtyMinutes"
        }
    }
}
