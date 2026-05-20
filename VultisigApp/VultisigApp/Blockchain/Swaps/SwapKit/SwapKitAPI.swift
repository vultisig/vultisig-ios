//
//  SwapKitAPI.swift
//  VultisigApp
//
//  TargetType definitions for the SwapKit V3 REST surface. Quote + Build are
//  separate calls (`POST /v3/quote` then `POST /v3/swap`) and tracking lives
//  off the base host (`POST /track`, not under `/v3`).
//

import Foundation

enum SwapKitAPI {
    case quote(SwapKitQuoteRequest)
    case swap(SwapKitSwapRequest)
    case track(SwapKitTrackRequest)
    case providers
}

extension SwapKitAPI: TargetType {
    var baseURL: URL {
        switch self {
        case .quote, .swap, .providers:
            return SwapKitConfig.baseURL
        case .track:
            return SwapKitConfig.trackBaseURL
        }
    }

    var path: String {
        switch self {
        case .quote:
            return "/quote"
        case .swap:
            return "/swap"
        case .track:
            return "/track"
        case .providers:
            return "/providers"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .providers:
            return .get
        case .quote, .swap, .track:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .quote(let request):
            return .requestCodable(request, .jsonEncoding)
        case .swap(let request):
            return .requestCodable(request, .jsonEncoding)
        case .track(let request):
            return .requestCodable(request, .jsonEncoding)
        case .providers:
            return .requestPlain
        }
    }

    var headers: [String: String]? {
        var values: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Referer": SwapKitConfig.referer
        ]
        if let key = SwapKitConfig.apiKey {
            // TODO: Per design §5, prefer hash-auth (`x-payload-hash + Referer`) over
            // raw `x-api-key` once partner contact confirms our key supports it.
            values["x-api-key"] = key
        }
        return values
    }

    var timeoutInterval: TimeInterval {
        SwapKitConfig.timeoutInterval
    }
}

// MARK: - Request payloads

struct SwapKitQuoteRequest: Encodable {
    let sellAsset: String
    let buyAsset: String
    let sellAmount: String
    let sourceAddress: String?
    let destinationAddress: String?
    let slippage: Double?
    let providers: [String]?
}

struct SwapKitSwapRequest: Encodable {
    let routeId: String
    let sourceAddress: String
    let destinationAddress: String
    let overrideSlippage: Bool?
}

struct SwapKitTrackRequest: Encodable {
    let hash: String
    let chainId: String
}
