//
//  SwapInteractor.swift
//  VultisigApp
//
//  Protocol layer between the Swap feature's ViewModels and the underlying
//  services (quotes, chain-specific data, fast vault, balance). Lets the VM
//  tests drive happy/error paths through mocks instead of network singletons.
//

import BigInt
import Foundation

protocol SwapInteractor {
    /// Fast Vault eligibility for a given vault — exists on the server AND wasn't a
    /// local-only backup.
    func loadFastVault(vault: Vault) async -> Bool

    /// Aggregator quote fetch + discount-tier resolution. Returns nil when there's no
    /// amount to quote; throws `SwapCryptoLogic.Errors.sameAsset` when from/to coins match.
    func fetchQuote(draft: SwapDraft, vault: Vault, referredCode: String) async throws -> SwapQuoteResult?

    /// Chain-specific fee/nonce/blockhash data needed to assemble the keysign payload.
    func fetchChainSpecific(draft: SwapDraft) async throws -> BlockChainSpecific

    /// Computes the network fee in the source coin's units. EVM uses gas math, UTXO
    /// plans a transfer to derive the fee, Cosmos/THOR/etc. read directly off chainSpecific.
    func computeThorchainFee(chainSpecific: BlockChainSpecific, draft: SwapDraft, vault: Vault) async throws -> BigInt

    /// Convenience: fetches chain-specific data and builds the keysign payload in one call.
    /// VMs that already have chainSpecific should call SwapCryptoLogic directly.
    func buildSwapKeysignPayload(draft: SwapDraft, vault: Vault) async throws -> KeysignPayload

    /// Refresh balance for a single coin (typically called when the user picks a coin in
    /// the swap details screen).
    func updateBalance(for coin: Coin) async
}
