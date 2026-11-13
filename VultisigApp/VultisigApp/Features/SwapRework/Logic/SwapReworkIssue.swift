//
//  SwapReworkIssue.swift
//  VultisigApp
//
//  The one thing blocking a swap, placed on the element that caused it and
//  paired with a single fix. Resolved from the existing swap errors
//  (`SwapError`, `SwapCryptoLogic.Errors`) plus the form's own quote clock and
//  price-move check, in priority order: a blocked route outranks a stale quote,
//  which outranks a balance problem.
//

import Foundation

enum SwapReworkIssue: Equatable {
    /// The amount is more than the balance.
    case overBalance
    /// Not enough of the fee coin for gas.
    case notEnoughGas
    /// The provider's minimum is above the amount.
    case amountTooSmall
    /// THORChain/Maya trading halted for the pair. Nothing has been sent.
    case tradingHalted(providerName: String)
    /// None of the providers quotes this pair.
    case noRoute
    /// The refresh is worse than what the user saw.
    case priceMoved(SwapPriceMove)
    /// The quote is past its refresh time and no new one has landed.
    case quoteExpired
    /// Anything else: shown with the existing presentation copy.
    case other(title: String, message: String)

    /// Blocks review. Every issue does: there is no warning-only state here.
    var blocksReview: Bool { true }

    struct Context: Equatable {
        var hasAmount: Bool
        var balanceError: SwapCryptoLogic.Errors?
        var quoteError: Error?
        var isQuoteExpired: Bool
        var priceMove: SwapPriceMove
        var nativeProviderName: String

        static func == (lhs: Context, rhs: Context) -> Bool {
            lhs.hasAmount == rhs.hasAmount
                && lhs.balanceError == rhs.balanceError
                && lhs.quoteError?.localizedDescription == rhs.quoteError?.localizedDescription
                && lhs.isQuoteExpired == rhs.isQuoteExpired
                && lhs.priceMove == rhs.priceMove
                && lhs.nativeProviderName == rhs.nativeProviderName
        }
    }

    static func resolve(_ context: Context) -> SwapReworkIssue? {
        guard context.hasAmount else { return nil }

        if let error = context.quoteError, let issue = issue(for: error, nativeProviderName: context.nativeProviderName) {
            return issue
        }
        if context.isQuoteExpired { return .quoteExpired }
        switch context.balanceError {
        case .insufficientFunds?: return .overBalance
        case .insufficientGas?: return .notEnoughGas
        default: break
        }
        if context.priceMove.needsConfirmation { return .priceMoved(context.priceMove) }
        return nil
    }

    /// Maps a provider/form error onto an issue. Nil for errors that are not
    /// about the swap itself (cancellations).
    static func issue(for error: Error, nativeProviderName: String) -> SwapReworkIssue? {
        if error is CancellationError { return nil }
        if let swapError = error as? SwapError {
            switch swapError {
            case .tradingHalted:
                return .tradingHalted(providerName: nativeProviderName)
            case .routeUnavailable, .noLiquidityPool, .recipientRouteUnavailable:
                return .noRoute
            case .swapAmountTooSmall, .lessThenMinSwapAmount:
                return .amountTooSmall
            default:
                break
            }
        }
        if let planError = error as? UTXOTransactionPlanError {
            switch planError {
            // The outputs cannot cover amount plus fee: a gas problem with a fix
            // (lower the amount or Max), not an "unexpected" one.
            case .insufficientFunds: return .notEnoughGas
            case .dustAmount: return .amountTooSmall
            default: break
            }
        }
        if let formError = error as? SwapCryptoLogic.Errors {
            switch formError {
            case .insufficientFunds: return .overBalance
            case .insufficientGas: return .notEnoughGas
            case .swapAmountTooSmall: return .amountTooSmall
            default: break
            }
        }
        return .other(
            title: SwapErrorPresentation.title(for: error),
            message: SwapErrorPresentation.message(for: error)
        )
    }

    static func == (lhs: SwapReworkIssue, rhs: SwapReworkIssue) -> Bool {
        switch (lhs, rhs) {
        case (.overBalance, .overBalance), (.notEnoughGas, .notEnoughGas),
             (.amountTooSmall, .amountTooSmall), (.noRoute, .noRoute), (.quoteExpired, .quoteExpired):
            return true
        case let (.tradingHalted(left), .tradingHalted(right)):
            return left == right
        case let (.priceMoved(left), .priceMoved(right)):
            return left == right
        case let (.other(leftTitle, leftMessage), .other(rightTitle, rightMessage)):
            return leftTitle == rightTitle && leftMessage == rightMessage
        default:
            return false
        }
    }
}
