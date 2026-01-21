//
//  KeyImportSetupType.swift
//  VultisigApp
//

import Foundation

/// Represents the type of vault setup for key import
enum KeyImportSetupType: Hashable {
    /// Fast setup with server-based backup (1 device)
    case fast

    /// Secure multi-device setup
    /// - Parameter numberOfDevices: The number of devices (2-6+)
    case secure(numberOfDevices: Int)

    /// Display name for UI
    var displayName: String {
        switch self {
        case .fast:
            return "fastSetup".localized
        case .secure(let count):
            return String(format: "secureSetupDevices".localized, count)
        }
    }

    /// Number of devices including this one
    var deviceCount: Int {
        switch self {
        case .fast:
            return 1
        case .secure(let count):
            return count
        }
    }

    /// Whether this setup requires FastSign configuration
    var requiresFastSign: Bool {
        switch self {
        case .fast:
            return true
        case .secure:
            return false
        }
    }

    /// Rive animation file name for vault setup screen
    var vaultSetupAnimationName: String {
        switch self {
        case .fast:
            return "vault_setup_device1"
        case .secure(let count):
            // Use the device count directly (device2 for 2, device3 for 3, etc.)
            return "vault_setup_device\(count)"
        }
    }
}
