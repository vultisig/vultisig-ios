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
}
