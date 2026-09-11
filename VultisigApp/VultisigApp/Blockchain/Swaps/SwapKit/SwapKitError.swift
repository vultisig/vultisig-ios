//
//  SwapKitError.swift
//  VultisigApp
//
//  Mapping from SwapKit's documented `/v3/swap` (and `/v3/quote`) error codes
//  to a typed Swift error. The wire shape per the Phase 0 spike is:
//      { "error": "<code>", "message": "<human>", "data": { ... } }
//

import Foundation

struct SwapKitErrorEnvelope: Decodable, Hashable {
    let error: String?
    let message: String?
}

enum SwapKitError: Error, LocalizedError, Equatable {
    case apiKeyMissing
    case apiKeyInvalid
    case insufficientBalance
    case insufficientAllowance
    case unableToBuildTransaction
    case swapRouteNotFound
    case outputAmountDeviationTooHigh
    case noRoutesFound
    /// Disambiguated form of `noRoutesFound` thrown when the cached
    /// `/v3/providers` snapshot shows at least one non-filtered provider
    /// enables both source and destination chains — meaning the pair is
    /// structurally supported, so the 404 must be amount-related rather
    /// than a pair-coverage gap. It presents under the same "Amount Too Small"
    /// title and body as `SwapCryptoLogic.Errors.swapAmountTooSmall`, so users
    /// see the tooltip the THORChain path already produces.
    case amountBelowProviderMinimum
    case blackListAsset
    case invalidSourceAddress
    case invalidDestinationAddress
    case isSanctionedAddress
    case addressScreeningFailed
    case unsupportedTxType(String)
    /// The `/v3/swap` response disagrees with itself about where the deposit
    /// goes, or states a transfer array the builder cannot honour. `detail` is
    /// diagnostic only — see `errorDescription` for why the user copy is shared
    /// with `unableToBuildTransaction`.
    case contradictoryResponse(detail: String)
    /// The `/v3/swap` response does not echo the swap that was requested — a
    /// different route, source, or destination than the one asked for.
    case responseEchoMismatch(detail: String)
    case providerNotEnabled
    case routeFiltered
    case malformedAmount(String)
    case generic(message: String)

    init?(envelope: SwapKitErrorEnvelope?) {
        guard let envelope, let code = envelope.error else { return nil }
        switch code {
        case "apiKeyInvalid":
            self = .apiKeyInvalid
        case "insufficientBalance":
            self = .insufficientBalance
        case "insufficientAllowance":
            self = .insufficientAllowance
        case "unableToBuildTransaction", "failedToRetrieveBalance":
            // SwapKit's NEAR-Intents proxy collapses upstream UTXO-indexer
            // failures into `failedToRetrieveBalance`. Surfacing the raw
            // string leaks an implementation detail and reads as "your
            // balance lookup failed" — but the user-facing meaning is the
            // same as `unableToBuildTransaction`: this route is currently
            // unavailable, try another provider. Map the two together so
            // both ride the friendlier "route currently unavailable" copy.
            self = .unableToBuildTransaction
        case "swapRouteNotFound":
            self = .swapRouteNotFound
        case "outputAmountDeviationTooHigh":
            self = .outputAmountDeviationTooHigh
        case "noRoutesFound":
            self = .noRoutesFound
        case "blackListAsset":
            self = .blackListAsset
        case "invalidSourceAddress":
            self = .invalidSourceAddress
        case "invalidDestinationAddress":
            self = .invalidDestinationAddress
        case "isSanctionedAddress":
            self = .isSanctionedAddress
        case "addressScreeningFailed":
            self = .addressScreeningFailed
        default:
            self = .generic(message: envelope.message ?? code)
        }
    }

    /// Names the divergent field and both values. Logged at rejection, never shown: both
    /// cases share the `unableToBuildTransaction` copy.
    var refusalDetail: String? {
        switch self {
        case .contradictoryResponse(let detail), .responseEchoMismatch(let detail):
            return detail
        default:
            return nil
        }
    }

    static func from(httpData: Data?) -> SwapKitError? {
        guard let httpData,
              let envelope = try? JSONDecoder().decode(SwapKitErrorEnvelope.self, from: httpData)
        else {
            return nil
        }
        return SwapKitError(envelope: envelope)
    }

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "swapKitErrorApiKeyMissing".localized
        case .apiKeyInvalid:
            return "swapKitErrorApiKeyInvalid".localized
        case .insufficientBalance:
            return "swapKitErrorInsufficientBalance".localized
        case .insufficientAllowance:
            return "swapKitErrorInsufficientAllowance".localized
        case .unableToBuildTransaction:
            return "swapKitErrorUnableToBuildTransaction".localized
        case .swapRouteNotFound:
            return "swapKitErrorSwapRouteNotFound".localized
        case .outputAmountDeviationTooHigh:
            return "swapKitErrorOutputAmountDeviationTooHigh".localized
        case .noRoutesFound:
            return "swapKitErrorNoRoutesFound".localized
        case .amountBelowProviderMinimum:
            // Reuse the existing THORChain "amount too small" copy rather than
            // introducing a SwapKit-specific key: the user-facing meaning is
            // identical to `SwapCryptoLogic.Errors.swapAmountTooSmall`, whose
            // title this case borrows too.
            return "swapErrorAmountTooSmallDescription".localized
        case .blackListAsset:
            return "swapKitErrorBlackListAsset".localized
        case .invalidSourceAddress:
            return "swapKitErrorInvalidSourceAddress".localized
        case .invalidDestinationAddress:
            return "swapKitErrorInvalidDestinationAddress".localized
        case .isSanctionedAddress, .addressScreeningFailed:
            return "swapKitErrorAddressScreening".localized
        case .unsupportedTxType(let txType):
            return String(format: "swapKitErrorUnsupportedTxType".localized, txType)
        case .contradictoryResponse, .responseEchoMismatch:
            // Same user-facing meaning as `unableToBuildTransaction`: this route is
            // unusable, try another provider. See `refusalDetail` for the diagnostic.
            return "swapKitErrorUnableToBuildTransaction".localized
        case .providerNotEnabled:
            return "swapKitErrorProviderNotEnabled".localized
        case .routeFiltered:
            return "swapKitErrorRouteFiltered".localized
        case .malformedAmount(let raw):
            return String(format: "swapKitErrorMalformedAmount".localized, raw)
        case .generic(let message):
            return message
        }
    }
}

// MARK: - Tooltip presentation

extension SwapKitError: SwapErrorPresentable {
    /// Every case gets a domain title. A case reaching the tooltip under the
    /// generic heading means the app named the failure precisely in the body and
    /// then said "Unexpected Error" above it.
    var errorTitle: String {
        switch self {
        case .apiKeyMissing, .apiKeyInvalid, .providerNotEnabled:
            // Nothing about the trade is wrong — SwapKit itself is unusable here.
            return "swapErrorProviderRejectedTitle".localized
        case .insufficientBalance:
            return "swapErrorInsufficientFundsTitle".localized
        case .insufficientAllowance:
            return "swapErrorApprovalRequiredTitle".localized
        case .unableToBuildTransaction, .noRoutesFound, .routeFiltered,
             .unsupportedTxType, .contradictoryResponse, .responseEchoMismatch,
             .malformedAmount, .generic:
            return "swapErrorRouteUnavailableTitle".localized
        case .swapRouteNotFound:
            return "swapErrorRouteExpiredTitle".localized
        case .outputAmountDeviationTooHigh:
            return "swapErrorQuoteExpiredTitle".localized
        case .amountBelowProviderMinimum:
            // Same verdict and same body as `SwapCryptoLogic.Errors.swapAmountTooSmall`,
            // which this case used to be normalized into for the tooltip.
            return "swapErrorAmountTooSmallTitle".localized
        case .blackListAsset:
            return "swapErrorAssetBlockedTitle".localized
        case .invalidSourceAddress:
            return "swapErrorInvalidSourceTitle".localized
        case .invalidDestinationAddress:
            return "swapErrorInvalidDestinationTitle".localized
        case .isSanctionedAddress, .addressScreeningFailed:
            return "swapErrorAddressScreeningTitle".localized
        }
    }

    var errorMessage: String {
        switch self {
        case .unsupportedTxType, .contradictoryResponse, .responseEchoMismatch,
             .malformedAmount, .generic:
            // The only case-specific information these carry is a string this app
            // did not write for a screen: a txType token, a diverging field name,
            // an unparseable amount, an upstream body, an encoder failure. It stays
            // in `errorDescription` for the log. The body is the one thing true at
            // all three sites they are thrown from — quote, payload build and
            // signing — which is that this route cannot be used.
            return "swapKitErrorUnableToBuildTransaction".localized
        default:
            return errorDescription ?? "swapKitErrorUnableToBuildTransaction".localized
        }
    }
}
