//
//  SwapErrorPresentable.swift
//  VultisigApp
//

import Foundation

/// User-facing presentation of a swap-flow error: the title and body the swap
/// form's error tooltip renders.
///
/// Deliberately separate from `LocalizedError.errorDescription`. That stays the
/// *diagnostic* text and may carry a raw upstream provider string (a node body
/// with an uppercased contract address, a 500 page, an aggregator's internal
/// wording) which is useful in a log and hostile on screen. `errorMessage` is
/// always localized app copy.
///
/// Conforming an error type here is what keeps it out of the tooltip's generic
/// "Unexpected Error" fallback: title and body resolve through this one
/// protocol, so a type can never end up with a domain-correct body under a
/// generic title.
protocol SwapErrorPresentable: Error {
    /// Tooltip heading — a short domain verdict ("No Liquidity Pool").
    var errorTitle: String { get }
    /// Tooltip body. Localized app copy, never a raw upstream string.
    var errorMessage: String { get }
}

/// Resolves any error reaching the swap form into the tooltip's title and body.
///
/// Lives outside the view so the resolution is testable on its own: the bug this
/// replaces was that the view resolved title and body through two independent
/// `if let` ladders, and an error type present in one ladder but missing from the
/// other rendered a domain-correct sentence under "Unexpected Error".
enum SwapErrorPresentation {

    static func title(for error: Error) -> String {
        presentable(for: error)?.errorTitle ?? SwapCryptoLogic.Errors.unexpectedError.errorTitle
    }

    static func message(for error: Error) -> String {
        // Errors outside the swap flow's own vocabulary (fee-path failures,
        // aggregator bodies, transport errors) still relay their localized
        // description — it is the only signal available for them.
        presentable(for: error)?.errorMessage ?? error.localizedDescription
    }

    /// The single lookup both `title` and `message` go through, so they can never
    /// disagree about which vocabulary an error belongs to.
    static func presentable(for error: Error) -> SwapErrorPresentable? {
        if let presentable = error as? SwapErrorPresentable {
            return presentable
        }
        return normalizedSwapKitError(error)
    }

    /// Map terminal SwapKit error cases onto the swap flow's user-facing error
    /// vocabulary so the tooltip shows a domain-appropriate title and description
    /// instead of the generic "Unexpected Error" fallback. Only covers cases with
    /// a clear `SwapCryptoLogic.Errors` equivalent — everything else flows
    /// through `error.localizedDescription` as before.
    private static func normalizedSwapKitError(_ error: Error) -> SwapCryptoLogic.Errors? {
        guard let swapKitError = error as? SwapKitError else { return nil }
        switch swapKitError {
        case .amountBelowProviderMinimum:
            return .swapAmountTooSmall
        default:
            return nil
        }
    }
}
