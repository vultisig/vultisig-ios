//
//  SwapCryptoLogic+Draft.swift
//  VultisigApp
//
//  Pure helpers ported from `SwapTransaction`'s instance methods +
//  extension into `SwapCryptoLogic` over `SwapDraft`. The `(tx:)` variants
//  on `SwapTransaction` stay alive during §1–§4 so existing call sites keep
//  working; both go away in §5.
//

import BigInt
import Foundation

extension SwapCryptoLogic {

    // MARK: - Amount conversions

    static func fromAmountDecimal(draft: SwapDraft) -> Decimal {
        draft.fromAmount.toDecimal()
    }

    static func amountInCoinDecimal(draft: SwapDraft) -> BigInt {
        draft.fromCoin.raw(for: draft.fromAmount.toDecimal())
    }

    // MARK: - Fees

    static func fee(draft: SwapDraft) -> BigInt {
        switch draft.quote {
        case .thorchain, .thorchainChainnet, .thorchainStagenet, .mayachain:
            return draft.thorchainFee
        case let .oneinch(_, fee), let .kyberswap(_, fee), let .lifi(_, fee, _):
            return fee ?? 0
        case nil:
            return .zero
        }
    }

    static func inboundFeeDecimal(draft: SwapDraft) -> Decimal? {
        draft.quote?.inboundFeeDecimal(toCoin: draft.toCoin)
    }

    // MARK: - Quote-derived

    static func toAmountDecimal(draft: SwapDraft) -> Decimal {
        guard let quote = draft.quote else { return .zero }
        switch quote {
        case let .mayachain(quote),
             let .thorchain(quote),
             let .thorchainChainnet(quote),
             let .thorchainStagenet(quote):
            let expected = quote.expectedAmountOut.toDecimal()
            return expected / draft.toCoin.thorswapMultiplier
        case let .oneinch(quote, _), let .lifi(quote, _, _), let .kyberswap(quote, _):
            let amount = BigInt(quote.dstAmount) ?? BigInt.zero
            return draft.toCoin.decimal(for: amount)
        }
    }

    static func router(draft: SwapDraft) -> String? {
        draft.quote?.router
    }

    // MARK: - Branching predicates

    static func isApproveRequired(draft: SwapDraft) -> Bool {
        draft.fromCoin.shouldApprove && router(draft: draft) != nil
    }

    static func isDeposit(draft: SwapDraft) -> Bool {
        draft.fromCoin.chain == .mayaChain
    }

    // swiftlint:disable:next unused_parameter
    static func isAffiliate(draft: SwapDraft) -> Bool {
        true
    }
}
