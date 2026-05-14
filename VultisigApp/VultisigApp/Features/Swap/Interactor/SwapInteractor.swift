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
    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String
    ) async throws -> SwapQuoteResult?

    /// Chain-specific fee/nonce/blockhash data needed to assemble the keysign payload.
    func fetchChainSpecific(
        fromCoin: Coin,
        toCoin: Coin,
        fromAmount: Decimal,
        quote: SwapQuote?
    ) async throws -> BlockChainSpecific

    /// Computes the network fee in the source coin's units. EVM uses gas math, UTXO
    /// plans a transfer to derive the fee, Cosmos/THOR/etc. read directly off chainSpecific.
    func computeThorchainFee(
        chainSpecific: BlockChainSpecific,
        fromCoin: Coin,
        fromAmount: Decimal,
        vault: Vault
    ) async throws -> BigInt

    /// Fetches chain-specific data and builds the keysign payload for a finalised
    /// `SwapTransaction`. Used by Verify when the user signs.
    func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async throws -> KeysignPayload

    /// Refresh balance for a single coin (typically called when the user picks a coin in
    /// the swap details screen).
    func updateBalance(for coin: Coin) async
}
