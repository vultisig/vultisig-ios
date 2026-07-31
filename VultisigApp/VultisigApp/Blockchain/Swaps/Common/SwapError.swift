//
//  SwapError.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 16.07.2024.
//

import Foundation

enum SwapError: Error, LocalizedError, Equatable {
    case routeUnavailable
    case recipientRouteUnavailable
    /// The built swap artifact does not target the intended external recipient
    /// (the provider dropped/misused the recipient param). Raised by
    /// `SwapRecipientVerifier` before signing so funds are never misdirected.
    case recipientVerificationFailed
    case noLiquidityPool
    case tradingHalted
    case swapAmountTooSmall
    /// The node refused the quote because its simulated output fell below the
    /// minimum-output floor derived from the requested slippage tolerance.
    /// Actionable by the user: raise the slippage setting or reduce the amount.
    case slippageToleranceTooTight
    case lessThenMinSwapAmount(amount: String)
    /// A THORChain secured-asset swap resolved to a destination that is not a
    /// THORChain address, so the mint would have no valid settlement target.
    /// Raised before quoting, with app-authored copy — distinct from
    /// `serverError`, which carries text we did not write.
    case securedAssetInvalidDestination(expectedPrefix: String, destination: String)
    /// An upstream provider rejected the quote with a message this app could not
    /// classify. The payload is the provider's own wording: it belongs in logs
    /// (`errorDescription`) and never on screen (`errorMessage`).
    case serverError(message: String)

    var errorDescription: String? {
        switch self {
        case .routeUnavailable:
            return "swapRouteNotAvailable".localized
        case .recipientRouteUnavailable:
            return "swapRecipientRouteNotAvailable".localized
        case .recipientVerificationFailed:
            return "swapRecipientVerificationFailed".localized
        case .noLiquidityPool:
            return "noLiquidityPool".localized
        case .tradingHalted:
            return "swapTradingHalted".localized
        case .swapAmountTooSmall:
            return "swapAmountTooSmall".localized
        case .slippageToleranceTooTight:
            return "swapSlippageToleranceTooTight".localized
        case .lessThenMinSwapAmount(let amount):
            return String(format: "swapAmountTooSmallRecommended".localized, amount)
        case let .securedAssetInvalidDestination(expectedPrefix, destination):
            return String(
                format: "swapSecuredAssetInvalidDestination".localized,
                expectedPrefix,
                destination
            )
        case .serverError(let msg):
            return msg
        }
    }
}

// MARK: - Tooltip presentation

extension SwapError: SwapErrorPresentable {
    /// Every case gets a domain title. `SwapError` is the swap flow's own typed
    /// vocabulary, so a case reaching the tooltip under a generic heading means
    /// the app knew exactly what went wrong and said "Unexpected Error" anyway.
    var errorTitle: String {
        switch self {
        case .routeUnavailable:
            return "swapErrorRouteUnavailableTitle".localized
        case .recipientRouteUnavailable:
            return "swapErrorRecipientRouteTitle".localized
        case .recipientVerificationFailed:
            return "swapErrorRecipientVerificationTitle".localized
        case .noLiquidityPool:
            return "swapErrorNoLiquidityPoolTitle".localized
        case .tradingHalted:
            return "swapErrorTradingHaltedTitle".localized
        case .swapAmountTooSmall, .lessThenMinSwapAmount:
            // Same verdict as `SwapCryptoLogic.Errors.swapAmountTooSmall`, so it
            // reuses that title rather than adding a second phrasing for it.
            return "swapErrorAmountTooSmallTitle".localized
        case .slippageToleranceTooTight:
            return "swapErrorSlippageTooTightTitle".localized
        case .securedAssetInvalidDestination:
            return "swapErrorInvalidDestinationTitle".localized
        case .serverError:
            return "swapErrorProviderRejectedTitle".localized
        }
    }

    var errorMessage: String {
        switch self {
        case .serverError:
            // The provider's own wording stays in `errorDescription` for the log
            // and is replaced here: an untranslated node body ("failed to
            // simulate swap: pool ETH.VULT-0X… doesn't exist") is not something
            // to put in front of someone deciding whether to trade.
            return "swapErrorProviderRejectedDescription".localized
        default:
            return errorDescription ?? "swapErrorProviderRejectedDescription".localized
        }
    }
}
