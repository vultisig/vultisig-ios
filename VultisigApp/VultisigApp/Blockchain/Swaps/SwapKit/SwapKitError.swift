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
        case "unableToBuildTransaction":
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
            return "SwapKit API key not configured"
        case .apiKeyInvalid:
            return "SwapKit API key is invalid"
        case .insufficientBalance:
            return "Insufficient balance for this route"
        case .insufficientAllowance:
            return "Token allowance is insufficient — approve first"
        case .unableToBuildTransaction:
            return "This route is currently unavailable, try a different provider"
        case .swapRouteNotFound:
            return "Selected route has expired"
        case .outputAmountDeviationTooHigh:
            return "Quote drifted more than 5% — refresh to continue"
        case .noRoutesFound:
            return "No routes available for this pair"
        case .blackListAsset:
            return "This asset is blocked by the aggregator"
        case .invalidSourceAddress:
            return "Source address is invalid"
        case .invalidDestinationAddress:
            return "Destination address is invalid"
        case .isSanctionedAddress, .addressScreeningFailed:
            return "Address screening failed — contact support"
        case .unsupportedTxType(let txType):
            return "SwapKit txType \(txType) is not yet supported on iOS"
        case .providerNotEnabled:
            return "SwapKit is not enabled on this chain"
        case .routeFiltered:
            return "All routes were filtered out for this pair"
        case .generic(let message):
            return message
        }
    }
}
