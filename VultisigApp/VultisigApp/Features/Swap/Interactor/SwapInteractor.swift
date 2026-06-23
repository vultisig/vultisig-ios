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
    /// Aggregator quote fetch + discount-tier resolution. Returns nil when there's no
    /// amount to quote; throws `SwapCryptoLogic.Errors.sameAsset` when from/to coins match.
    /// `thorPools`/`mayaPools` are the live `Available` pool snapshots threaded
    /// from the swap screen so provider resolution at quote time matches the
    /// picker (a token made eligible by a live pool keeps its native provider);
    /// `nil` falls back to the static eligibility.
    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String,
        thorPools: [NativePoolAsset]?,
        mayaPools: [NativePoolAsset]?,
        slippageBps: Int?,
        recipientAddress: String?
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

    /// Resolve and cache the VULT discount tier (VULT balance + Thorguard NFT) for the
    /// wallet once per session. Called on screen load to warm the cache so the per-quote
    /// path reads the cached tier instead of re-running the Thorguard eth_call each time.
    func warmDiscountTier(for vault: Vault) async
}

extension SwapInteractor {
    /// Cold-start convenience: callers without live pool snapshots (e.g. the
    /// verify-screen refresh) resolve providers off the static fallback.
    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String
    ) async throws -> SwapQuoteResult? {
        try await fetchQuote(
            amount: amount,
            fromCoin: fromCoin,
            toCoin: toCoin,
            vault: vault,
            referredCode: referredCode,
            thorPools: nil,
            mayaPools: nil,
            slippageBps: nil,
            recipientAddress: nil
        )
    }

    /// Convenience for callers that pass slippage/recipient but have no live pool
    /// snapshots (e.g. the verify-screen refresh, which re-quotes an already-valid
    /// pair) — pools fall back to the static eligibility.
    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String,
        slippageBps: Int?,
        recipientAddress: String?
    ) async throws -> SwapQuoteResult? {
        try await fetchQuote(
            amount: amount,
            fromCoin: fromCoin,
            toCoin: toCoin,
            vault: vault,
            referredCode: referredCode,
            thorPools: nil,
            mayaPools: nil,
            slippageBps: slippageBps,
            recipientAddress: recipientAddress
        )
    }
}
