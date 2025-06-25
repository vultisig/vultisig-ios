//
//  AvailableSecurityProviders.swift
//  VultisigApp
//
//  Created by Assistant on 2025-01-14.
//

import Foundation

/// Defines all available security providers in the system
enum AvailableSecurityProvider: String, CaseIterable {
    case blockaid = "blockaid"
    // Future providers can be easily added here
    // case xptTxScanner = "xptTxScanner"
    // case chainalysis = "chainalysis"
    
    /// Check if this provider is enabled via UserDefaults
    var isEnabled: Bool {
        switch self {
        case .blockaid:
            return UserDefaults.standard.object(forKey: "VultisigSecurityProvider_\(rawValue)") as? Bool ?? true
        }
    }
    
    /// Get the capabilities for this provider
    var capabilities: SecurityProviderCapabilities {
        switch self {
        case .blockaid:
            return .blockaid
        }
    }
    
    /// Create an instance of this provider
    func createProvider() -> SecurityProvider? {
        guard isEnabled else { return nil }
        
        switch self {
        case .blockaid:
            return BlockaidProvider(capabilities: capabilities)
        }
    }
    
    /// Display name for UI/logging
    var displayName: String {
        switch self {
        case .blockaid:
            return "Blockaid"
        }
    }
}
