//
//  SwapKitAPI.swift
//  VultisigApp
//
//  TargetType definitions for the SwapKit V3 REST surface, routed through
//  the Vultisig backend proxy (`api.vultisig.com/swapkit/`). The proxy
//  attaches the SwapKit partner API key server-side — iOS does not see or
//  ship the key. Quote + Build are separate calls (`POST /v3/quote` then
//  `POST /v3/swap`) and tracking lives off the proxy root (`POST /track`,
//  not under `/v3`).
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
        case .quote, .swap:
            // V3 surface: `/v3/quote`, `/v3/swap`. Base URL is
            // `.../swapkit/v3`; the path adds the leaf only.
            return SwapKitConfig.baseURL
        case .track, .providers:
            // Bare-host endpoints — SwapKit's `/track` and `/providers`
            // live at the host root, not under `/v3`. Hitting
            // `.../swapkit/v3/providers` returns 404 from the proxy.
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
        // The proxy attaches `x-api-key` server-side. iOS only sends the
        // `Referer` so the partner dashboard can attribute volume by client.
        return [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Referer": SwapKitConfig.referer
        ]
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
