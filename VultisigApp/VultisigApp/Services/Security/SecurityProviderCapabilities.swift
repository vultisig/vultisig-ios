//
//  SecurityProviderCapabilities.swift
//  VultisigApp
//
//  Created by Assistant on 2025-01-14.
//

import Foundation

/// Defines what capabilities a security provider supports
struct SecurityProviderCapabilities {
    let evmTransactionScanning: Bool
    let solanaTransactionScanning: Bool
    let addressValidation: Bool
    let tokenScanning: Bool
    
    /// Blockaid EVM-only capabilities (current plan)
    static let blockaidEVM = SecurityProviderCapabilities(
        evmTransactionScanning: true,
        solanaTransactionScanning: false,
        addressValidation: false,
        tokenScanning: false
    )
    
    /// Blockaid full capabilities (higher plan)
    static let blockaidFull = SecurityProviderCapabilities(
        evmTransactionScanning: true,
        solanaTransactionScanning: true,
        addressValidation: true,
        tokenScanning: true
    )
    
    /// No capabilities (disabled)
    static let none = SecurityProviderCapabilities(
        evmTransactionScanning: false,
        solanaTransactionScanning: false,
        addressValidation: false,
        tokenScanning: false
    )
}

/// Protocol for providers that support configurable capabilities
protocol CapabilityAwareSecurityProvider: SecurityProvider {
    var capabilities: SecurityProviderCapabilities { get }
} 