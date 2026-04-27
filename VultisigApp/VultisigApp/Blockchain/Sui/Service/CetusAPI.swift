//
//  CetusAPI.swift
//  VultisigApp
//

import Foundation

enum CetusAPI: TargetType {
    case findRoutes(fromToken: String, toToken: String, amount: UInt64)

    static let cetusBaseURL = URL(string: "https://api-sui.cetus.zone")!

    var baseURL: URL { Self.cetusBaseURL }

    var path: String {
        switch self {
        case .findRoutes:
            return "/router_v2/find_routes"
        }
    }

    var method: HTTPMethod { .post }

    var task: HTTPTask {
        switch self {
        case .findRoutes(let fromToken, let toToken, let amount):
            return .requestCodable(
                CetusFindRoutesRequest(from: fromToken, target: toToken, amount: amount, byAmountIn: true),
                .jsonEncoding
            )
        }
    }

    var timeoutInterval: TimeInterval { 10 }
}

// MARK: - Request body

struct CetusFindRoutesRequest: Encodable {
    let from: String
    let target: String
    let amount: UInt64
    let byAmountIn: Bool

    enum CodingKeys: String, CodingKey {
        case from
        case target
        case amount
        case byAmountIn = "by_amount_in"
    }
}
