//
//  SwapDiscountTierResolving.swift
//  VultisigApp
//
//  Test seam over the VULT discount-tier resolution used by the swap quote
//  path. Lets the interactor resolve the tier without the Thorguard NFT
//  eth_call on every quote fetch.
//

import Foundation

protocol SwapDiscountTierResolving {
    /// Resolves the discount tier for the vault. The VULT balance half is
    /// re-read every call, so a balance that lands late is honoured by the next
    /// quote; only the Thorguard NFT ownership behind it is session-cached, so
    /// the eth_call stays off the per-quote critical path. Safe to call
    /// repeatedly.
    @MainActor
    func resolveTierForSession(for vault: Vault) async -> VultDiscountTier?
}

extension VultTierService: SwapDiscountTierResolving {}
