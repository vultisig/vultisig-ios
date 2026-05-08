//
//  SwapCryptoLogic+Draft.swift
//  VultisigApp
//
//  Pure helpers ported from `SwapDraftStore`'s instance methods +
//  extension into `SwapCryptoLogic` over `SwapDraft`. The `(tx:)` variants
//  on `SwapDraftStore` stay alive during §1–§4 so existing call sites keep
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

    // MARK: - Validation

    static func feeCoin(draft: SwapDraft) -> Coin {
        // Fees are always paid in the native token of the source chain.
        guard !draft.fromCoin.isNativeToken else { return draft.fromCoin }
        return draft.fromCoins.first { $0.chain == draft.fromCoin.chain && $0.isNativeToken }
            ?? draft.fromCoin
    }

    static func isSufficientBalance(draft: SwapDraft) -> Bool {
        balanceError(draft: draft) == nil
    }

    /// Returns the specific balance error, or nil if balance is sufficient.
    /// Differentiates between insufficient token balance and insufficient gas.
    static func balanceError(draft: SwapDraft) -> Errors? {
        let feeCoinValue = feeCoin(draft: draft)
        let fromFee = feeCoinValue.decimal(for: fee(draft: draft))

        let fromBalance = draft.fromCoin.balanceDecimal
        let feeCoinBalance = feeCoinValue.balanceDecimal

        let amount = draft.fromAmount.toDecimal()

        if feeCoinValue == draft.fromCoin {
            // Same coin pays for amount + gas.
            if fromFee + amount > fromBalance {
                // Amount alone fits but amount+fee doesn't ⇒ gas issue, not funds.
                if amount <= fromBalance, fromFee > 0 {
                    return .insufficientGas
                }
                return .insufficientFunds
            }
        } else {
            // Different coins: check gas token separately.
            if amount > fromBalance {
                return .insufficientFunds
            }
            if fromFee > feeCoinBalance {
                return .insufficientGas
            }
        }
        return nil
    }

    static func validateForm(draft: SwapDraft, isLoading: Bool) -> Bool {
        draft.fromCoin != draft.toCoin
            && draft.fromCoin != .example
            && draft.toCoin != .example
            && !draft.fromAmount.isEmpty
            && !toAmountDecimal(draft: draft).isZero
            && draft.quote != nil
            && fee(draft: draft) != .zero
            && isSufficientBalance(draft: draft)
            && !isLoading
    }
}
