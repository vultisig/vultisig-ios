//
//  HyperliquidInfoAPI.swift
//  VultisigApp
//
//  Read-only Hyperliquid `/info` endpoints. Nothing here signs or
//  writes; `/exchange` is deliberately absent until live signing.
//

import Foundation

enum HyperliquidInfoAPI: TargetType {
    case metaAndAssetContexts
    case candleSnapshot(coin: String, interval: HLCandleInterval, startTimeMs: Int64, endTimeMs: Int64)
    case clearinghouseState(user: String)
    case openOrders(user: String)
    case userFills(user: String)
    case frontendOpenOrders(user: String)
    case userAbstraction(user: String)
    case spotClearinghouseState(user: String)
    case ledgerUpdates(user: String, startTimeMs: Int64)
    case funding(user: String, startTimeMs: Int64)

    var baseURL: URL { URL(string: "https://api.hyperliquid.xyz")! }
    var path: String { "/info" }
    var method: HTTPMethod { .post }
    var timeoutInterval: TimeInterval { 20 }

    var task: HTTPTask {
        .requestParameters(body, .jsonEncoding)
    }

    var body: [String: Any] {
        switch self {
        case .metaAndAssetContexts:
            return ["type": "metaAndAssetCtxs"]
        case let .candleSnapshot(coin, interval, startTimeMs, endTimeMs):
            return [
                "type": "candleSnapshot",
                "req": ["coin": coin, "interval": interval.rawValue, "startTime": startTimeMs, "endTime": endTimeMs]
            ]
        case .clearinghouseState(let user):
            return ["type": "clearinghouseState", "user": user.lowercased()]
        case .openOrders(let user):
            return ["type": "openOrders", "user": user.lowercased()]
        case .userFills(let user):
            return ["type": "userFills", "user": user.lowercased()]
        case .frontendOpenOrders(let user):
            return ["type": "frontendOpenOrders", "user": user.lowercased()]
        case .userAbstraction(let user):
            return ["type": "userAbstraction", "user": user.lowercased()]
        case .spotClearinghouseState(let user):
            return ["type": "spotClearinghouseState", "user": user.lowercased()]
        case let .ledgerUpdates(user, startTimeMs):
            return ["type": "userNonFundingLedgerUpdates", "user": user.lowercased(), "startTime": startTimeMs]
        case let .funding(user, startTimeMs):
            return ["type": "userFunding", "user": user.lowercased(), "startTime": startTimeMs]
        }
    }
}
