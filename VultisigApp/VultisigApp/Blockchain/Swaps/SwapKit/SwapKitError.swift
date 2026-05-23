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
    case blackListAsset
    case invalidSourceAddress
    case invalidDestinationAddress
    case isSanctionedAddress
    case addressScreeningFailed
    case unsupportedTxType(String)
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
