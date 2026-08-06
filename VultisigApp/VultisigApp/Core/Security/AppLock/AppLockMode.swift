//
//  AppLockMode.swift
//  VultisigApp
//

import Foundation

/// How the app gates access when it comes back to the foreground.
///
/// One mode at a time, deliberately. Two independent lock systems layered on top
/// of each other is the most likely way this ships confusing — the passcode is
/// an alternative to the device-authentication gate, not an addition to it.
enum AppLockMode: String, CaseIterable, Identifiable {
    /// No gate.
    case off
    /// Face ID / Touch ID with the device passcode as fallback. What the app has
    /// always done, and the default for anyone upgrading.
    case deviceAuth
    /// A passcode specific to this app, which the device does not know.
    case passcode

    var id: String { rawValue }
}
