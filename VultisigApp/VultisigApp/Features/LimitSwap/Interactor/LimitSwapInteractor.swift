//
//  LimitSwapInteractor.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Reference-data lookups the limit-swap view-model needs from THORChain.
///
/// Phase 1 only needs the market-price reference: validation, memo assembly and
/// the byte-cap pre-flight are pure functions run inline in the view-model
/// (`LimitSwapFormViewModel.preparePlaceableOrder`), and order persistence is
/// owned by `LimitOrderStorageService` on the Done screen. The interactor is
/// kept as an injection seam so the market-price fetch is unit-testable with a
/// stubbed quote service.
protocol LimitSwapInteractor {

    /// Current market price (target natural units per source natural unit).
    func fetchMarketPrice(
        sourceAsset: String,
        sourceAmount: BigInt,
        sourceDecimals: Int,
        targetAsset: String,
        targetDecimals: Int,
        destinationAddress: String
    ) async throws -> Decimal

    /// Whether THORChain currently accepts resting limit orders (`EnableAdvSwapQueue`
    /// mimir). Fails CLOSED. Gates the Place-Order flow.
    func isAdvancedSwapQueueEnabled() async -> Bool

    /// Live THORChain inbound addresses, for the picker's routable-chain set.
    func fetchInboundAddresses() async -> [InboundAddress]

    /// Estimated source-chain broadcast fee for the limit deposit, in the fee
    /// coin's smallest units. Reuses the EXACT sign-path chain-specific fetch
    /// (`fetchSwapBlockChainSpecific` + `limitDepositChainSpecific`) so the
    /// estimate matches what will actually be signed, then derives the fee the
    /// same way the Send / market-swap path does (`SwapCryptoLogic.thorchainFee`:
    /// gas×limit for EVM, plan fee for UTXO, fixed gas for THOR `MsgDeposit`).
    /// Throws on fetch / plan failure.
    func estimateNetworkFee(
        sourceCoin: Coin,
        targetCoin: Coin,
        sourceAmount: BigInt,
        vault: Vault
    ) async throws -> BigInt
}

struct DefaultLimitSwapInteractor: LimitSwapInteractor {

    private let quoteService: LimitSwapQuoteServiceProtocol

    init(quoteService: LimitSwapQuoteServiceProtocol) {
        self.quoteService = quoteService
    }

    func fetchMarketPrice(
        sourceAsset: String,
        sourceAmount: BigInt,
        sourceDecimals: Int,
        targetAsset: String,
        targetDecimals: Int,
        destinationAddress: String
    ) async throws -> Decimal {
        try await quoteService.fetchCurrentMarketPrice(
            sourceAsset: sourceAsset,
            sourceAmount: sourceAmount,
            sourceDecimals: sourceDecimals,
            targetAsset: targetAsset,
            targetDecimals: targetDecimals,
            destinationAddress: destinationAddress
        )
    }

    func isAdvancedSwapQueueEnabled() async -> Bool {
        await quoteService.isAdvancedSwapQueueEnabled()
    }

    func fetchInboundAddresses() async -> [InboundAddress] {
        await quoteService.fetchInboundAddresses()
    }

    func estimateNetworkFee(
        sourceCoin: Coin,
        targetCoin: Coin,
        sourceAmount: BigInt,
        vault: Vault
    ) async throws -> BigInt {
        let fromAmount = sourceCoin.decimal(for: sourceAmount)
        // Same granular swap-shaped fetch (quote: nil) the sign path uses, then
        // the same native-EVM gas-limit alignment (`limitDepositChainSpecific`).
        let fetched = try await BlockChainService.shared.fetchSwapBlockChainSpecific(
            fromCoin: sourceCoin,
            toCoin: targetCoin,
            fromAmount: fromAmount,
            quote: nil
        )
        let chainSpecific = limitDepositChainSpecific(fetched, sourceCoin: sourceCoin)
        // Same fee derivation the Send / market-swap path uses.
        return try await SwapCryptoLogic.thorchainFee(
            for: chainSpecific,
            fromCoin: sourceCoin,
            fromAmount: fromAmount,
            vault: vault
        )
    }
}
