//
//  ThorchainService+LimitSwapQuote.swift
//  VultisigApp
//

import BigInt
import Foundation

extension ThorchainService: LimitSwapQuoteServiceProtocol {

    func fetchCurrentMarketPrice(
        sourceAsset: String,
        sourceAmount: BigInt,
        sourceDecimals: Int,
        targetAsset: String,
        targetDecimals: Int,
        destinationAddress: String
    ) async throws -> Decimal {
        let quote = try await fetchSwapQuotes(
            address: destinationAddress,
            fromAsset: sourceAsset,
            toAsset: targetAsset,
            amount: sourceAmount.description,
            interval: 1,
            streamingQuantity: 0,
            // No minimum-output limit on the reference quote — this fetch only
            // derives the market price for the form, it never broadcasts.
            toleranceBps: 0,
            referredCode: "",
            vultTierDiscount: 0
        )

        guard let expectedRaw = Decimal(string: quote.expectedAmountOut) else {
            throw LimitSwapQuoteError.invalidExpectedAmount(quote.expectedAmountOut)
        }
        // THORChain returns expected_amount_out in 1e8 fixed-point regardless
        // of the target chain's natural decimals.
        let expectedTargetNatural = expectedRaw / pow(10, 8)

        guard let sourceRaw = Decimal(string: sourceAmount.description) else {
            throw LimitSwapQuoteError.invalidSourceAmount(sourceAmount.description)
        }
        let sourceNatural = sourceRaw / pow(10, sourceDecimals)
        guard sourceNatural != 0 else {
            throw LimitSwapQuoteError.zeroSourceAmount
        }

        return expectedTargetNatural / sourceNatural
    }
}
