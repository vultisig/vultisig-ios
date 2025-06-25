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
    let siteScanning: Bool
    let bitcoinTransactionScanning: Bool
    let starknetTransactionScanning: Bool
    let stellarTransactionScanning: Bool
    let suiTransactionScanning: Bool
    
    static let blockaid = SecurityProviderCapabilities(
        evmTransactionScanning: true,          // ✅ Working - /evm/json-rpc/scan 
        solanaTransactionScanning: false,      // ❌ Not in GA - API returns "not supported in GA"
        addressValidation: false,              // ❌ Returns 403 "You cannot consume this service"
        tokenScanning: false,                  // ❌ Returns 403 "You cannot consume this service"
        siteScanning: true,                    // ✅ Working - /site/scan endpoint
        bitcoinTransactionScanning: false,     // ❌ Returns 404 "no Route matched"
        starknetTransactionScanning: false,    // ❌ Chain not available in app
        stellarTransactionScanning: false,     // ❌ Chain not available in app
        suiTransactionScanning: false          // ❌ Not supported by Blockaid API yet
    )
    
    /// No capabilities (disabled)
    static let none = SecurityProviderCapabilities(
        evmTransactionScanning: false,
        solanaTransactionScanning: false,
        addressValidation: false,
        tokenScanning: false,
        siteScanning: false,
        bitcoinTransactionScanning: false,
        starknetTransactionScanning: false,
        stellarTransactionScanning: false,
        suiTransactionScanning: false
    )
}

/// Protocol for providers that support configurable capabilities
protocol CapabilityAwareSecurityProvider: SecurityProvider {
    var capabilities: SecurityProviderCapabilities { get }
} 
