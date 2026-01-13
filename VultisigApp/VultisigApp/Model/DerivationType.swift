//
//  DerivationType.swift
//  VultisigApp
//

import Foundation

/// Represents different derivation path types for key generation.
/// Currently only Solana has multiple derivation options, but this enum
/// is designed to be extensible for other chains in the future.
enum DerivationType: String, Codable, CaseIterable {
    case `default` = "default"  // Standard BIP-44 derivation
    case phantom = "phantom"    // Phantom/Solflare style (Solana: m/44'/501'/0')

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .phantom: return "Phantom/Solflare"
        }
    }
}
