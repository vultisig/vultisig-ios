//
//  AutoLockInterval.swift
//  VultisigApp
//

import Foundation

/// How long the app may sit in the background before it re-locks.
///
/// Stored in seconds so short intervals can be represented without rounding.
/// `fifteenMinutes` remains a valid migration-only value because earlier app
/// versions exposed it, and silently replacing it would change an existing
/// user's security policy. New selections come from ``selectableCases``.
enum AutoLockInterval: Int, CaseIterable, Identifiable {
    case immediate = 0
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
    case never = -1

    static let `default`: AutoLockInterval = .fiveMinutes

    static let selectableCases: [AutoLockInterval] = [
        .immediate,
        .fifteenSeconds,
        .thirtySeconds,
        .oneMinute,
        .fiveMinutes,
        .tenMinutes,
        .thirtyMinutes,
        .never
    ]

    var id: Int { rawValue }

    var duration: TimeInterval {
        self == .never ? .infinity : TimeInterval(rawValue)
    }

    /// Localization key for the row label.
    var titleKey: String {
        switch self {
        case .immediate:
            return "autoLockImmediately"
        case .fifteenSeconds:
            return "autoLockFifteenSeconds"
        case .thirtySeconds:
            return "autoLockThirtySeconds"
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
        case .never:
            return "autoLockNever"
        }
    }
}
