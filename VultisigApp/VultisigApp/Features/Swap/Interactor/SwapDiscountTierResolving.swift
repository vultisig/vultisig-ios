//
//  SwapDiscountTierResolving.swift
//  VultisigApp
//
//  Test seam over the VULT discount-tier resolution used by the swap quote
//  path. Lets the interactor read a per-session cached tier instead of
//  resolving it (VULT balance + Thorguard NFT eth_call) on every quote fetch.
//

import Foundation

protocol SwapDiscountTierResolving {
    /// Resolves the discount tier for the vault once and caches it for the
    /// session. Subsequent calls return the cached value without touching the
    /// network (no Thorguard eth_call). Safe to call repeatedly.
    func resolveTierForSession(for vault: Vault) async -> VultDiscountTier?
}

extension VultTierService: SwapDiscountTierResolving {}
