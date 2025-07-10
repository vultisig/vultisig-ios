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
    let cosmosTransactionScanning: Bool
    
    static let blockaid = SecurityProviderCapabilities(
        evmTransactionScanning: true,          // ✅ Working - /evm/json-rpc/scan 
        solanaTransactionScanning: true,       // ✅ Updated - Now working with "mainnet" chain name
        addressValidation: true,               // ✅ Updated - Should work for EVM, Solana, Sui
        tokenScanning: true,                   // ✅ Updated - Should work for supported chains
        siteScanning: true,                    // ✅ Working - /site/scan endpoint
        bitcoinTransactionScanning: true,      // ✅ Updated - Working with correct endpoint
        starknetTransactionScanning: false,    // ❌ Chain not available in app
        stellarTransactionScanning: false,     // ❌ Chain not available in app
        suiTransactionScanning: true,          // ✅ Updated - Should work with /sui/transaction/scan
        cosmosTransactionScanning: true        // ✅ Added - Should work with /cosmos/transaction/scan
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
        suiTransactionScanning: false,
        cosmosTransactionScanning: false
    )
}

/// Protocol for providers that support configurable capabilities
protocol CapabilityAwareSecurityProvider: SecurityProvider {
    var capabilities: SecurityProviderCapabilities { get }
} 
