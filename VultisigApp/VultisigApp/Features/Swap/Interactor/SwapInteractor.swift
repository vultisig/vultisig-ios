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
    func fetchQuote(
        amount: Decimal,
        fromCoin: Coin,
        toCoin: Coin,
        vault: Vault,
        referredCode: String,
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

    /// Sign-time fund-safety gate: re-check the source chain's live inbound for a
    /// native (THORChain / Maya) route immediately before building the keysign
    /// payload, BYPASSING the inbound cache. Throws `SwapError.tradingHalted` when
    /// the chain is halted or the live re-check can't be verified (fail-closed).
    /// No-op for aggregator routes — they never deposit into a native inbound vault.
    func assertSourceChainNotHalted(transaction: SwapTransaction) async throws

    /// Fetches chain-specific data and builds the keysign payload for a finalised
    /// `SwapTransaction`. Used by Verify when the user signs.
    func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async throws -> KeysignPayload

    /// Refresh balance for a single coin (typically called when the user picks a coin in
    /// the swap details screen).
    func updateBalance(for coin: Coin) async

    /// Fail-closed balance refresh for the sign-time funds check: throws if the
    /// live balance fetch fails, so an insufficient order can't slip through
    /// against a stale cached balance when the RPC is down. Defaults to the
    /// non-throwing `updateBalance` for test seams; production overrides it.
    func refreshBalanceOrThrow(for coin: Coin) async throws

    /// Resolve the VULT discount tier once on screen load. Its purpose is to warm
    /// the session cache of Thorguard NFT ownership so the per-quote path doesn't
    /// re-run the eth_call; the VULT balance half is re-read on every quote, so a
    /// balance that lands after this warm-up is still honoured.
    func warmDiscountTier(for vault: Vault) async
}

extension SwapInteractor {
    /// Default for test seams: best-effort refresh that never throws. Production
    /// `DefaultSwapInteractor` overrides this with the fail-closed implementation.
    func refreshBalanceOrThrow(for coin: Coin) async throws {
        await updateBalance(for: coin)
    }
}
